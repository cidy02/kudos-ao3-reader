#if os(iOS)
import CryptoKit
import Foundation
import OSLog

#if canImport(FluidAudio)
import FluidAudio
#endif

/// Downloads FluidAudio's staged Kokoro Core ML graphs after explicit user
/// consent. The zip is hosted on GitHub Releases (not Hugging Face).
@MainActor
@Observable
final class CoreMLKokoroPackInstaller {
    enum Status: Equatable {
        case idle
        case downloading(Double)
        case installing
        case completed
        case failed(String)
    }

    static let shared = CoreMLKokoroPackInstaller()

    private(set) var status: Status = KokoroAneAvailability.isPackInstalled
        ? .completed
        : .idle

    private var installTask: Task<Void, Never>?

    #if canImport(FluidAudio)
    private var manager: KokoroAneManager?
    #endif

    func install() {
        guard installTask == nil else { return }
        status = .downloading(0)
        installTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.readyManager()
                self.status = .completed
                Log.tts.info("Kokoro Neural Engine pack ready")
            } catch is CancellationError {
                self.status = .idle
            } catch let error as URLError where error.code == .cancelled {
                // How Swift task cancellation surfaces out of `URLSession`.
                self.status = .idle
            } catch {
                Log.tts.error(
                    "Kokoro ANE install failed: \(error.localizedDescription, privacy: .public)"
                )
                self.status = .failed(error.localizedDescription)
            }
            self.installTask = nil
        }
    }

    /// Only cancels. Clearing `installTask` is left to the task's own tail so
    /// a fresh `install()` cannot start a second download alongside one that
    /// is still winding down.
    func cancel() {
        installTask?.cancel()
        status = .idle
    }

    /// Shared synthesizer so install compile and playback load one ANE-resident chain.
    #if canImport(FluidAudio)
    func readyManager() async throws -> KokoroAneManager {
        if let manager { return manager }
        try await seedCacheFromGitHub()
        status = .installing
        let units = KokoroAnePlayback.computeUnits
        Log.tts.info(
            "Kokoro compute units: \(KokoroAnePlayback.prefersGpuOverBnns() ? "cpuAndGpu (avoid iOS 26 BNNS)" : "default ANE", privacy: .public)"
        )
        let created = KokoroAneManager(
            directory: try TtsCacheDirectory.ensure().appendingPathComponent("Models"),
            computeUnits: units
        )
        try await created.initialize()
        try KokoroAneAvailability.markInstalled()
        manager = created
        return created
    }

    /// Unpack the GitHub zip into FluidAudio's cache so `initialize()` never
    /// hits Hugging Face.
    ///
    /// Called only from `readyManager()`. Calling it from `install()` as well
    /// re-downloaded the whole pack a second time, because the install marker
    /// this checks is not written until `readyManager()` finishes.
    private func seedCacheFromGitHub() async throws {
        let modelsRoot = try TtsCacheDirectory.ensure().appendingPathComponent("Models")
        let aneDir = modelsRoot.appendingPathComponent("kokoro-82m-coreml/ANE")
        let required = [
            "KokoroAlbert.mlmodelc",
            "KokoroPostAlbert.mlmodelc",
            "KokoroAlignment.mlmodelc",
            "KokoroProsody.mlmodelc",
            "KokoroNoise_v2.mlmodelc",
            "KokoroVocoder.mlmodelc",
            "KokoroTail.mlmodelc",
            "vocab.json",
            "af_heart.bin",
        ]
        let alreadyPresent = required.allSatisfy { name in
            FileManager.default.fileExists(atPath: aneDir.appendingPathComponent(name).path)
        }
        if alreadyPresent, KokoroAneAvailability.isPackInstalled { return }

        // Hashing and inflating ~180 MB on the main actor froze the UI for
        // seconds. `fetchAndUnpack` is nonisolated, so the only work that
        // stays here is the progress hop.
        try await Self.fetchAndUnpack(into: modelsRoot) { [self] fraction in
            Task { @MainActor in self.status = .downloading(fraction) }
        }
    }

    private nonisolated static func fetchAndUnpack(
        into modelsRoot: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let (tempURL, _) = try await URLSession.shared.download(
            from: KokoroGitHubPack.downloadURL,
            delegate: delegate
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try Task.checkCancellation()

        // Hash in bounded chunks rather than `Data(contentsOf:)`, which held a
        // second full copy of the archive in memory next to MiniZip's.
        guard try KokoroGitHubPack.sha256Hex(ofFileAt: tempURL)
            == KokoroGitHubPack.expectedSHA256
        else {
            throw KokoroGitHubPackError.digestMismatch
        }
        try Task.checkCancellation()

        // Memory-mapped: MiniZip reads through it, and the pages stay
        // evictable under memory pressure instead of counting as dirty RSS.
        let data = try Data(contentsOf: tempURL, options: .mappedIfSafe)
        let zip = try MiniZip(data: data, limits: .kokoroAne)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kokoro-ane-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: staging) }
        try zip.unzip(to: staging)
        let unpacked = staging.appendingPathComponent("kokoro-82m-coreml")
        guard FileManager.default.fileExists(atPath: unpacked.path) else {
            throw KokoroGitHubPackError.missingPayload
        }
        try Task.checkCancellation()

        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let destination = modelsRoot.appendingPathComponent("kokoro-82m-coreml")
        // Swap via a sibling so a failed move cannot leave the app with no
        // models *and* a still-valid install marker.
        let previous = modelsRoot.appendingPathComponent(
            "kokoro-82m-coreml.replacing-\(UUID().uuidString)"
        )
        let hadPrevious = FileManager.default.fileExists(atPath: destination.path)
        if hadPrevious {
            try FileManager.default.moveItem(at: destination, to: previous)
        }
        do {
            try FileManager.default.moveItem(at: unpacked, to: destination)
        } catch {
            if hadPrevious {
                try? FileManager.default.moveItem(at: previous, to: destination)
            }
            throw error
        }
        if hadPrevious {
            try? FileManager.default.removeItem(at: previous)
        }
    }
    #endif
}

/// Forwards `URLSession` download progress. Informational only — if the
/// callback never fires the download still completes normally.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    /// Required by the protocol. The async `download(for:delegate:)` hands the
    /// file back through its return value, so there is nothing to do here.
    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo _: URL
    ) {}
}

enum KokoroGitHubPackError: Error, LocalizedError {
    case digestMismatch
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .digestMismatch:
            "The GitHub Kokoro pack failed SHA-256 verification."
        case .missingPayload:
            "The GitHub Kokoro pack did not contain kokoro-82m-coreml/."
        }
    }
}
#endif
