import Foundation

nonisolated enum KokoroFP32InstallError: Error, Equatable, LocalizedError {
    case int8SupportMissing
    case notEnoughStorage(requiredBytes: Int64)
    case modelSizeMismatch(actual: Int64, expected: Int64)
    case modelDigestMismatch
    case archiveDigestMismatch
    case runtimeFingerprintMismatch
    case cancelled
    case operationInProgress
    case io(String)

    var errorDescription: String? {
        switch self {
        case .int8SupportMissing:
            return "Download the Int8 Voice Pack first. FP32 reuses its voices, tokens, and eSpeak data."
        case .notEnoughStorage(let requiredBytes):
            let megabytes = requiredBytes / 1_000_000
            return "Not enough storage space. At least \(megabytes)MB required."
        case .modelSizeMismatch(let actual, let expected):
            return "Official FP32 model size mismatch (\(actual) bytes, expected \(expected))."
        case .modelDigestMismatch:
            return "Official FP32 model failed SHA-256 verification."
        case .archiveDigestMismatch:
            return "Official Int8 Voice Pack failed SHA-256 verification."
        case .runtimeFingerprintMismatch:
            return "Assembled FP32 runtime failed its pinned fingerprint check."
        case .cancelled:
            return "FP32 install was cancelled."
        case .operationInProgress:
            return "A Kokoro model download is already in progress."
        case .io(let message):
            return message
        }
    }
}

/// Assembles an official v0.19 FP32 runtime from a downloaded `model.onnx` plus
/// the already-installed Int8 support files, then atomically replaces the
/// destination directory. Never loads the 320 MB tar archive into memory.
nonisolated enum KokoroFP32Installer {
    struct Spec: Equatable, Sendable {
        var modelFileName: String
        var expectedModelByteCount: Int64
        var expectedModelSHA256: String
        var expectedRuntimeContentSHA256: String
        var markerFileName: String
        var markerContents: String

        static func official() -> Spec {
            Spec(
                modelFileName: KokoroModelPack.fp32V019.modelFileName,
                expectedModelByteCount: KokoroModelPack.fp32V019.expectedModelByteCount,
                expectedModelSHA256: KokoroModelPack.fp32V019.expectedModelSHA256,
                expectedRuntimeContentSHA256: KokoroModelPack.fp32V019.expectedRuntimeContentSHA256
                    ?? "",
                markerFileName: KokoroModelPack.fp32V019.validationMarkerFileName ?? "",
                markerContents: KokoroModelPack.fp32V019.validationMarkerContents ?? ""
            )
        }
    }

    /// Peak space: the downloaded model, a staged copy of that model, a copy of
    /// Int8 support files, plus filesystem slack. Conservative on purpose.
    static func reservedInstallBytes(modelByteCount: Int64 = 345_555_491) -> Int64 {
        modelByteCount * 2 + 64_000_000 + 128_000_000
    }

    static func availableBytes(at url: URL, fileManager: FileManager = .default) -> Int64? {
        var probe = url
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: probe.path, isDirectory: &isDirectory) {
            probe = probe.deletingLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        if let capacity = values?.volumeAvailableCapacity, capacity > 0 {
            return Int64(capacity)
        }
        return nil
    }

    static func install(
        downloadedModel: URL,
        int8Directory: URL,
        destinationDirectory: URL,
        spec: Spec = .official(),
        fileManager: FileManager = .default,
        isCancelled: () -> Bool = { false }
    ) throws {
        try throwIfCancelled(isCancelled)
        guard KokoroRuntimeFingerprint.hasCompleteSupportFiles(in: int8Directory) else {
            throw KokoroFP32InstallError.int8SupportMissing
        }

        try verifyDownloadedModel(downloadedModel, spec: spec)
        try throwIfCancelled(isCancelled)

        let parent = destinationDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let stagingRoot = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destinationDirectory,
            create: true
        )
        let staged = stagingRoot.appendingPathComponent(
            destinationDirectory.lastPathComponent,
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: staged, withIntermediateDirectories: true)
            try throwIfCancelled(isCancelled)
            try copySupportFiles(
                from: int8Directory,
                to: staged,
                fileManager: fileManager
            )
            try throwIfCancelled(isCancelled)
            try placeModel(
                downloadedModel,
                in: staged,
                fileName: spec.modelFileName,
                fileManager: fileManager
            )
            try throwIfCancelled(isCancelled)

            let fingerprint = try KokoroRuntimeFingerprint.runtimeContentSHA256(
                modelFileName: spec.modelFileName,
                in: staged
            )
            try throwIfCancelled(isCancelled)
            guard fingerprint == spec.expectedRuntimeContentSHA256 else {
                throw KokoroFP32InstallError.runtimeFingerprintMismatch
            }

            try writeMarker(spec: spec, in: staged)
            try throwIfCancelled(isCancelled)
            try atomicallyReplace(
                destinationDirectory,
                with: staged,
                fileManager: fileManager
            )
            excludeFromBackup(destinationDirectory)
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            if let installError = error as? KokoroFP32InstallError {
                throw installError
            }
            throw KokoroFP32InstallError.io(error.localizedDescription)
        }
        try? fileManager.removeItem(at: stagingRoot)
    }

    static func verifyDownloadedModel(_ url: URL, spec: Spec) throws {
        let actualSize = try KokoroRuntimeFingerprint.byteCount(of: url)
        guard actualSize == spec.expectedModelByteCount else {
            throw KokoroFP32InstallError.modelSizeMismatch(
                actual: actualSize,
                expected: spec.expectedModelByteCount
            )
        }
        let digest = try KokoroRuntimeFingerprint.sha256Hex(ofFile: url)
        guard digest == spec.expectedModelSHA256 else {
            throw KokoroFP32InstallError.modelDigestMismatch
        }
    }

    private static func copySupportFiles(
        from int8Directory: URL,
        to staged: URL,
        fileManager: FileManager
    ) throws {
        for fileName in KokoroRuntimeFingerprint.rootSupportFileNames {
            let source = int8Directory.appendingPathComponent(fileName)
            let destination = staged.appendingPathComponent(fileName)
            try fileManager.copyItem(at: source, to: destination)
        }
        let sourceESpeak = int8Directory.appendingPathComponent(
            KokoroRuntimeFingerprint.eSpeakDirectoryName,
            isDirectory: true
        )
        let destinationESpeak = staged.appendingPathComponent(
            KokoroRuntimeFingerprint.eSpeakDirectoryName,
            isDirectory: true
        )
        try fileManager.copyItem(at: sourceESpeak, to: destinationESpeak)
        guard KokoroRuntimeFingerprint.hasCompleteSupportFiles(in: staged) else {
            throw KokoroFP32InstallError.int8SupportMissing
        }
    }

    private static func placeModel(
        _ downloadedModel: URL,
        in staged: URL,
        fileName: String,
        fileManager: FileManager
    ) throws {
        let destination = staged.appendingPathComponent(fileName)
        do {
            try fileManager.moveItem(at: downloadedModel, to: destination)
        } catch {
            try fileManager.copyItem(at: downloadedModel, to: destination)
            try? fileManager.removeItem(at: downloadedModel)
        }
    }

    private static func writeMarker(spec: Spec, in staged: URL) throws {
        guard let data = spec.markerContents.data(using: .utf8) else {
            throw KokoroFP32InstallError.io("Could not encode FP32 verification marker.")
        }
        try data.write(
            to: staged.appendingPathComponent(spec.markerFileName),
            options: .atomic
        )
    }

    private static func atomicallyReplace(
        _ destination: URL,
        with staged: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: staged,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    private static func throwIfCancelled(_ isCancelled: () -> Bool) throws {
        if isCancelled() { throw KokoroFP32InstallError.cancelled }
    }
}
