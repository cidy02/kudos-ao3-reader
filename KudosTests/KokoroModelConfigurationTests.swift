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
    }

    @Test func officialFP32AndInt8PacksUseDistinctModelFiles() {
        #expect(KokoroModelPack.int8V019.modelDirectoryName == "kokoro-int8-en-v0_19")
        #expect(KokoroModelPack.int8V019.modelFileName == "model.int8.onnx")
        #expect(KokoroModelPack.fp32V019.modelDirectoryName == "kokoro-en-v0_19")
        #expect(KokoroModelPack.fp32V019.modelFileName == "model.onnx")
        #expect(KokoroModelPack.fp32V019.requiresDeveloperInstallation)
        #expect(KokoroModelPack.fp32V019.validationMarkerContents != nil)
        #expect(KokoroModelPack.int8V019.validationMarkerContents == nil)
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
}
#endif
