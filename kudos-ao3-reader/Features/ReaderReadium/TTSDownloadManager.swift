import CryptoKit
import Foundation
import OSLog
import SWCompression

/// Manages the background downloading and extraction of the Kokoro TTS model.
@MainActor
@Observable
public final class TTSDownloadManager: NSObject {
    public enum Status: Equatable {
        case idle
        case downloading(progress: Double) // 0.0 to 1.0
        case extracting
        case verifying
        case completed
        case failed(error: String)
    }

    public private(set) var status: Status = .idle
    private(set) var statusPack: KokoroModelPack?
    private var downloadTask: URLSessionDownloadTask?
    @ObservationIgnored
    private var activeOperationPack: KokoroModelPack?
    // @Observable rewrites stored properties into tracked computed accessors,
    // which lazy can't participate in — @ObservationIgnored opts this one out
    // (it's implementation detail, not observed UI state, so that's correct).
    @ObservationIgnored
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "tts_model_download")
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let modelsRoot: URL
    public let modelDirectory: URL

    public override convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.init(modelsRoot: appSupport.appendingPathComponent("TTS_Models", isDirectory: true))
    }

    /// Test-only injection point. Production always uses Application Support.
    init(modelsRoot: URL) {
        self.modelsRoot = modelsRoot
        self.modelDirectory = modelsRoot.appendingPathComponent(
            KokoroModelPack.int8V019.modelDirectoryName,
            isDirectory: true
        )
        super.init()

        if isModelDownloaded() {
            self.statusPack = .int8V019
            self.status = .completed
        }
    }

    func modelDirectory(for pack: KokoroModelPack) -> URL {
        guard pack != .int8V019 else { return modelDirectory }
        return modelsRoot.appendingPathComponent(
            pack.modelDirectoryName,
            isDirectory: true
        )
    }

    public func isModelDownloaded() -> Bool {
        isModelDownloaded(for: .int8V019)
    }

    func isModelDownloaded(for pack: KokoroModelPack) -> Bool {
        let fm = FileManager.default
        let modelDirectory = modelDirectory(for: pack)
        let requiredFiles = pack.requiredFileNames
        let requiredDirs = ["espeak-ng-data"]

        for file in requiredFiles {
            let path = modelDirectory.appendingPathComponent(file).path
            if !fm.fileExists(atPath: path) { return false }
            if (try? fm.attributesOfItem(atPath: path)[.size] as? Int) == 0 { return false }
        }

        for dir in requiredDirs {
            var isDir: ObjCBool = false
            let path = modelDirectory.appendingPathComponent(dir).path
            if !fm.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue { return false }
        }

        guard pack.requiresDeveloperInstallation else { return true }
        return isDeveloperPackValidated(pack, in: modelDirectory)
    }

    func refreshStatus(for pack: KokoroModelPack) {
        guard activeOperationPack == nil else { return }
        statusPack = pack
        status = isModelDownloaded(for: pack) ? .completed : .idle
    }

    /// Checks a developer side-load on device before making FP32 eligible for
    /// playback. This keeps a partial/wrong `espeak-ng-data` tree from reaching
    /// Sherpa, whose native frontend can terminate the process on bad data.
    func verifyDeveloperInstalledModelPack(_ pack: KokoroModelPack) async {
        guard pack.requiresDeveloperInstallation,
              activeOperationPack == nil,
              let expectedFingerprint = pack.expectedRuntimeContentSHA256,
              let markerFileName = pack.validationMarkerFileName,
              let markerContents = pack.validationMarkerContents
        else {
            refreshStatus(for: pack)
            return
        }

        let directory = modelDirectory(for: pack)
        let markerURL = directory.appendingPathComponent(markerFileName)
        try? FileManager.default.removeItem(at: markerURL)
        activeOperationPack = pack
        statusPack = pack
        status = .verifying

        let modelFileName = pack.modelFileName
        let fingerprint = await Task.detached(priority: .utility) {
            try? Self.runtimeContentFingerprint(
                modelFileName: modelFileName,
                in: directory
            )
        }.value

        guard !Task.isCancelled else {
            activeOperationPack = nil
            status = .idle
            return
        }

        guard fingerprint == expectedFingerprint else {
            activeOperationPack = nil
            status = .failed(
                error: "FP32 verification failed. Side-load the official v0.19 pack again."
            )
            return
        }

        guard let markerData = markerContents.data(using: .utf8) else {
            activeOperationPack = nil
            status = .failed(error: "Could not encode FP32 verification marker.")
            return
        }
        do {
            try markerData.write(to: markerURL, options: .atomic)
            activeOperationPack = nil
            status = .completed
        } catch {
            activeOperationPack = nil
            status = .failed(error: "Could not save FP32 verification: \(error.localizedDescription)")
        }
    }

    /// FP32 is intentionally not extracted on-device: the current BZip2/TAR
    /// dependencies materialize the whole ~320 MB archive in memory. It is a
    /// developer-installed test pack until a streaming installer exists.
    func downloadModel(for pack: KokoroModelPack) async throws {
        guard !pack.requiresDeveloperInstallation else {
            let message = "FP32 test packs must be installed by a developer for now."
            statusPack = pack
            status = .failed(error: message)
            throw NSError(
                domain: "TTSDownloadManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        try await downloadModel()
    }

    public func downloadModel() async throws {
        statusPack = .int8V019
        // Space pre-check (approx 200MB expected for kokoro-int8-en-v0_19)
        let fm = FileManager.default
        let sysAttrs = try fm.attributesOfFileSystem(forPath: NSHomeDirectory())
        if let freeSpace = sysAttrs[.systemFreeSize] as? NSNumber,
           freeSpace.int64Value < 300_000_000 {
            status = .failed(error: "Not enough storage space. At least 300MB required.")
            throw NSError(
                domain: "TTSDownloadManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not enough storage space."]
            )
        }

        if isModelDownloaded() {
            statusPack = .int8V019
            status = .completed
            return
        }

        let url = URL(
            string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/"
                + "kokoro-int8-en-v0_19.tar.bz2"
        )!

        activeOperationPack = .int8V019
        statusPack = .int8V019
        status = .downloading(progress: 0)
        let task = urlSession.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }

    public func pause() {
        downloadTask?.suspend()
    }

    public func resume() {
        downloadTask?.resume()
    }

    public func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        activeOperationPack = nil
        status = .idle
    }

    private func isDeveloperPackValidated(
        _ pack: KokoroModelPack,
        in modelDirectory: URL
    ) -> Bool {
        guard let markerFileName = pack.validationMarkerFileName,
              let expectedMarkerContents = pack.validationMarkerContents
        else {
            return false
        }

        let markerURL = modelDirectory.appendingPathComponent(markerFileName)
        guard (try? String(contentsOf: markerURL, encoding: .utf8)) == expectedMarkerContents,
              let markerValues = try? markerURL.resourceValues(
                  forKeys: [.contentModificationDateKey]
              ),
              let markerDate = markerValues.contentModificationDate,
              let contentFiles = try? Self.runtimeContentFiles(
                  modelFileName: pack.modelFileName,
                  in: modelDirectory
              )
        else {
            return false
        }

        let modificationDates = contentFiles.compactMap {
            (try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        }
        guard modificationDates.count == contentFiles.count,
              let newestContentDate = modificationDates.max()
        else {
            return false
        }
        return newestContentDate <= markerDate
    }

    private nonisolated static func runtimeContentFingerprint(
        modelFileName: String,
        in modelDirectory: URL
    ) throws -> String {
        var hasher = SHA256()
        for file in try runtimeContentFiles(
            modelFileName: modelFileName,
            in: modelDirectory
        ) {
            hasher.update(data: Data(file.relativePath.utf8))
            hasher.update(data: Data([0]))

            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func runtimeContentFiles(
        modelFileName: String,
        in modelDirectory: URL
    ) throws -> [(relativePath: String, url: URL)] {
        let fileManager = FileManager.default
        let rootFileNames = [modelFileName, "voices.bin", "tokens.txt"]
        var files: [(relativePath: String, url: URL)] = []

        for fileName in rootFileNames {
            let url = modelDirectory.appendingPathComponent(fileName)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                throw CocoaError(.fileNoSuchFile)
            }
            files.append((fileName, url))
        }

        let eSpeakDirectory = modelDirectory.appendingPathComponent(
            "espeak-ng-data",
            isDirectory: true
        )
        var isESpeakDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: eSpeakDirectory.path,
            isDirectory: &isESpeakDirectory
        ), isESpeakDirectory.boolValue,
              let enumerator = fileManager.enumerator(
                  at: eSpeakDirectory,
                  includingPropertiesForKeys: [.isRegularFileKey]
              )
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [URLResourceKey.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = "espeak-ng-data/" + String(
                url.path.dropFirst(eSpeakDirectory.path.count + 1)
            )
            files.append((relativePath, url))
        }

        guard files.count > rootFileNames.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }
}

extension TTSDownloadManager: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            Task { @MainActor in
                if case .downloading = self.status {
                    self.status = .downloading(progress: progress)
                }
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            self.downloadTask = nil
            self.status = .extracting
        }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempDir) }

            let data = try Data(contentsOf: location)
            let decompressedData = try BZip2.decompress(data: data)
            let entries = try TarContainer.open(container: decompressedData)
            
            for entry in entries {
                // Remove the top-level folder prefix from archive paths.
                var relativePath = entry.info.name
                let prefix = "kokoro-int8-en-v0_19/"
                if relativePath.hasPrefix(prefix) {
                    relativePath = String(relativePath.dropFirst(prefix.count))
                }
                if relativePath.isEmpty { continue }

                let targetURL = self.modelDirectory.appendingPathComponent(relativePath)

                if entry.info.type == .directory {
                    try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                } else if let fileData = entry.data {
                    let parent = targetURL.deletingLastPathComponent()
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                    try fileData.write(to: targetURL)
                }
            }

            Task { @MainActor in
                if self.isModelDownloaded() {
                    self.activeOperationPack = nil
                    self.status = .completed
                } else {
                    self.activeOperationPack = nil
                    self.status = .failed(error: "Extraction completed but verification failed.")
                    try? fm.removeItem(at: self.modelDirectory)
                }
            }
        } catch {
            Task { @MainActor in
                self.activeOperationPack = nil
                self.status = .failed(error: error.localizedDescription)
            }
            try? fm.removeItem(at: self.modelDirectory)
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let taskIdentifier = task.taskIdentifier
        if let error = error {
            Task { @MainActor in
                guard self.downloadTask?.taskIdentifier == taskIdentifier else { return }
                self.downloadTask = nil
                self.activeOperationPack = nil
                self.status = .failed(error: error.localizedDescription)
            }
        }
    }
}
