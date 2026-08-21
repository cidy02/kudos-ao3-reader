#if os(iOS)
import Foundation
import Testing
@testable import Kudos

@Suite("Kokoro model configuration")
struct KokoroModelConfigurationTests {
    @Test func unknownPersistedValuesUseSafeDefaults() {
        #expect(KokoroModelPack.resolving(nil) == .int8V019)
        #expect(KokoroModelPack.resolving("removed-pack") == .int8V019)
        #expect(KokoroExecutionProvider.resolving(nil) == .cpu)
        #expect(KokoroExecutionProvider.resolving("ane-only") == .cpu)
        #expect(KokoroExecutionProvider.resolving("coreml") == .coreML)
    }

    @Test func officialFP32AndInt8PacksUseDistinctModelFiles() {
        #expect(KokoroModelPack.int8V019.modelDirectoryName == "kokoro-int8-en-v0_19")
        #expect(KokoroModelPack.int8V019.modelFileName == "model.int8.onnx")
        #expect(KokoroModelPack.fp32V019.modelDirectoryName == "kokoro-en-v0_19")
        #expect(KokoroModelPack.fp32V019.modelFileName == "model.onnx")
        #expect(KokoroModelPack.fp32V019.requiresInt8SupportFiles)
        #expect(!KokoroModelPack.int8V019.requiresInt8SupportFiles)
        #expect(KokoroModelPack.fp32V019.expectedModelByteCount == 345_555_491)
        #expect(
            KokoroModelPack.fp32V019.expectedModelSHA256
                == "10ff414106a038ce7e9e0126c6461e4dc8a86efaa89dc91d2009d69fe635e339"
        )
        #expect(
            KokoroModelPack.int8V019.expectedArchiveSHA256
                == "c9f0dd393615805b0bab050c340834d5e684e732aec91c0e860cd30e982c08bd"
        )
        #expect(
            KokoroModelPack.fp32V019.downloadURL.absoluteString.contains(
                "huggingface.co/csukuangfj/kokoro-en-v0_19/resolve/"
                    + "92805c485745946a0d945562d3aba19e7cbb2104/model.onnx"
            )
        )
        #expect(KokoroModelPack.fp32V019.validationMarkerContents != nil)
        #expect(KokoroModelPack.int8V019.validationMarkerContents == nil)
        #expect(
            KokoroFP32Installer.reservedInstallBytes()
                > KokoroModelPack.fp32V019.expectedModelByteCount
        )
    }

    @Test func runtimeConfigurationTracksBothModelAndProvider() {
        let cpuInt8 = KokoroRuntimeConfiguration(
            modelPack: .int8V019,
            executionProvider: .cpu
        )
        let coreMLInt8 = KokoroRuntimeConfiguration(
            modelPack: .int8V019,
            executionProvider: .coreML
        )
        let cpuFP32 = KokoroRuntimeConfiguration(
            modelPack: .fp32V019,
            executionProvider: .cpu
        )

        #expect(cpuInt8 != coreMLInt8)
        #expect(cpuInt8 != cpuFP32)
        #expect(coreMLInt8.executionProvider.sherpaIdentifier == "coreml")
        #expect(KokoroExecutionProvider.coreML.sherpaIdentifier == "coreml")

        #expect(
            KokoroRuntimeConfiguration.needsEngineReplacement(
                currentKind: .kokoro,
                currentConfiguration: cpuInt8,
                requestedKind: .kokoro,
                requestedConfiguration: coreMLInt8
            )
        )
    }

    @Test func missingFP32FallsBackToInt8OrApple() {
        let requested = KokoroRuntimeConfiguration(
            modelPack: .fp32V019,
            executionProvider: .coreML
        )

        #expect(
            KokoroRuntimeConfiguration.resolved(
                requested: requested,
                isModelDownloaded: { _ in false }
            ) == nil
        )
        #expect(
            KokoroRuntimeConfiguration.resolved(
                requested: requested,
                isModelDownloaded: { $0 == .int8V019 }
            ) == KokoroRuntimeConfiguration(
                modelPack: .int8V019,
                executionProvider: .coreML
            )
        )
        #expect(
            KokoroRuntimeConfiguration.resolved(
                requested: requested,
                isModelDownloaded: { $0 == .fp32V019 }
            ) == requested
        )
    }

    @Test func runtimeFingerprintKeepsOfficialRootFileOrder() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let eSpeakDirectory = temporaryRoot.appendingPathComponent("espeak-ng-data")

        try fileManager.createDirectory(at: eSpeakDirectory, withIntermediateDirectories: true)
        for fileName in ["model.onnx", "voices.bin", "tokens.txt"] {
            try Data(fileName.utf8).write(to: temporaryRoot.appendingPathComponent(fileName))
        }
        try Data("z".utf8).write(to: eSpeakDirectory.appendingPathComponent("z"))
        try Data("a".utf8).write(to: eSpeakDirectory.appendingPathComponent("a"))

        let paths = try KokoroRuntimeFingerprint.runtimeContentFiles(
            modelFileName: "model.onnx",
            in: temporaryRoot
        ).map(\.relativePath)
        #expect(paths == [
            "model.onnx",
            "voices.bin",
            "tokens.txt",
            "espeak-ng-data/a",
            "espeak-ng-data/z"
        ])
    }

    @Test func staleDownloadCompletionCannotMatchTheCurrentTask() {
        #expect(TTSDownloadManager.isCurrentDownloadTask(
            callbackTaskIdentifier: 41,
            activeTaskIdentifier: 41
        ))
        #expect(!TTSDownloadManager.isCurrentDownloadTask(
            callbackTaskIdentifier: 41,
            activeTaskIdentifier: 42
        ))
        #expect(!TTSDownloadManager.isCurrentDownloadTask(
            callbackTaskIdentifier: 41,
            activeTaskIdentifier: nil
        ))
    }

    @Test func persistedOperationsAreScopedToOneSafeIncomingFile() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let id = UUID()

        let downloading = KokoroInstallOperation(
            id: id,
            pack: .fp32V019,
            phase: .downloading
        )
        try KokoroInstallOperationStore.write(downloading, in: temporaryRoot)
        #expect(KokoroInstallOperationStore.read(in: temporaryRoot) == downloading)

        let installing = KokoroInstallOperation(
            id: id,
            pack: .fp32V019,
            phase: .installing,
            preservedFileName: ".incoming-\(UUID().uuidString)"
        )
        try KokoroInstallOperationStore.write(installing, in: temporaryRoot)
        #expect(KokoroInstallOperationStore.read(in: temporaryRoot) == installing)

        let unsafe = KokoroInstallOperation(
            id: id,
            pack: .fp32V019,
            phase: .installing,
            preservedFileName: "../outside-model.onnx"
        )
        #expect(!unsafe.isValid)

        KokoroInstallOperationStore.remove(in: temporaryRoot)
        #expect(KokoroInstallOperationStore.read(in: temporaryRoot) == nil)

        let nonDirectoryRoot = temporaryRoot.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: nonDirectoryRoot)
        do {
            try KokoroInstallOperationStore.write(downloading, in: nonDirectoryRoot)
            Issue.record("Persisting beneath a file must fail.")
        } catch {
            // The caller can remove its preserved download and fail closed.
        }
    }

    @MainActor
    @Test func immediateRetryCannotOverwriteAnUnresolvedRelaunchDownload() async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let operation = KokoroInstallOperation(
            id: UUID(),
            pack: .int8V019,
            phase: .downloading
        )
        try KokoroInstallOperationStore.write(operation, in: temporaryRoot)
        let manager = TTSDownloadManager(modelsRoot: temporaryRoot)

        do {
            try await manager.downloadModel(for: .int8V019)
            Issue.record("A rehydrating download must block an immediate retry.")
        } catch let error as KokoroFP32InstallError {
            #expect(error == .operationInProgress)
        } catch {
            Issue.record("Expected operationInProgress, got \(error)")
        }
        #expect(KokoroInstallOperationStore.read(in: temporaryRoot) == operation)
    }

    @MainActor
    @Test func unverifiedFP32FilesNeverBecomeReady() async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let manager = TTSDownloadManager(modelsRoot: temporaryRoot)
        let directory = manager.modelDirectory(for: .fp32V019)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for fileName in KokoroModelPack.fp32V019.requiredFileNames {
            try Data("not the official pack".utf8).write(
                to: directory.appendingPathComponent(fileName)
            )
        }
        try fileManager.createDirectory(
            at: directory.appendingPathComponent("espeak-ng-data"),
            withIntermediateDirectories: true
        )
        try Data("not eSpeak data".utf8).write(
            to: directory
                .appendingPathComponent("espeak-ng-data")
                .appendingPathComponent("phondata")
        )

        #expect(!manager.isModelDownloaded(for: .fp32V019))
        await manager.verifyDeveloperInstalledModelPack(.fp32V019)
        #expect(!manager.isModelDownloaded(for: .fp32V019))
        guard case .failed = manager.status else {
            Issue.record("An unverified FP32 side-load must fail closed.")
            return
        }
    }

    @MainActor
    @Test func fp32DownloadRequiresInstalledInt8Support() async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let manager = TTSDownloadManager(modelsRoot: temporaryRoot)

        do {
            try await manager.downloadModel(for: .fp32V019)
            Issue.record("FP32 download must refuse to start without Int8 support files.")
        } catch let error as KokoroFP32InstallError {
            #expect(error == .int8SupportMissing)
        } catch {
            Issue.record("Expected int8SupportMissing, got \(error)")
        }
        #expect(!manager.isModelDownloaded(for: .fp32V019))
        guard case .failed = manager.status else {
            Issue.record("Missing Int8 support must surface as a failed status.")
            return
        }
    }
}
#endif
