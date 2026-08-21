#if os(iOS)
import CryptoKit
import Foundation
import Testing
@testable import Kudos

@Suite("Kokoro FP32 installer")
struct KokoroFP32InstallerTests {
    @Test func successfulInstallIsAtomicAndLeavesAMarker() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        try KokoroFP32Installer.install(
            downloadedModel: harness.downloadedModel,
            int8Directory: harness.int8Directory,
            destinationDirectory: harness.destination,
            spec: harness.spec
        )

        #expect(FileManager.default.fileExists(
            atPath: harness.destination.appendingPathComponent("model.onnx").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: harness.destination.appendingPathComponent("voices.bin").path
        ))
        let marker = try String(
            contentsOf: harness.destination.appendingPathComponent(harness.spec.markerFileName),
            encoding: .utf8
        )
        #expect(marker == harness.spec.markerContents)
        #expect(!FileManager.default.fileExists(atPath: harness.downloadedModel.path))
    }

    @Test func installReplacesAnExistingDestination() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: harness.destination, withIntermediateDirectories: true)
        try Data("stale".utf8).write(
            to: harness.destination.appendingPathComponent("stale.txt")
        )

        try KokoroFP32Installer.install(
            downloadedModel: harness.downloadedModel,
            int8Directory: harness.int8Directory,
            destinationDirectory: harness.destination,
            spec: harness.spec
        )

        #expect(!fileManager.fileExists(
            atPath: harness.destination.appendingPathComponent("stale.txt").path
        ))
        #expect(fileManager.fileExists(
            atPath: harness.destination.appendingPathComponent("model.onnx").path
        ))
    }

    @Test func sizeMismatchLeavesDestinationUntouched() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        var spec = harness.spec
        spec.expectedModelByteCount += 1

        do {
            try KokoroFP32Installer.install(
                downloadedModel: harness.downloadedModel,
                int8Directory: harness.int8Directory,
                destinationDirectory: harness.destination,
                spec: spec
            )
            Issue.record("Size mismatch must fail closed.")
        } catch let error as KokoroFP32InstallError {
            guard case .modelSizeMismatch = error else {
                Issue.record("Expected modelSizeMismatch, got \(error)")
                return
            }
        }
        #expect(!FileManager.default.fileExists(atPath: harness.destination.path))
    }

    @Test func digestMismatchLeavesDestinationUntouched() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        var spec = harness.spec
        spec.expectedModelSHA256 = String(repeating: "0", count: 64)

        do {
            try KokoroFP32Installer.install(
                downloadedModel: harness.downloadedModel,
                int8Directory: harness.int8Directory,
                destinationDirectory: harness.destination,
                spec: spec
            )
            Issue.record("Digest mismatch must fail closed.")
        } catch let error as KokoroFP32InstallError {
            #expect(error == .modelDigestMismatch)
        }
        #expect(!FileManager.default.fileExists(atPath: harness.destination.path))
    }

    @Test func fingerprintMismatchLeavesDestinationUntouched() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        var spec = harness.spec
        spec.expectedRuntimeContentSHA256 = String(repeating: "ab", count: 32)

        do {
            try KokoroFP32Installer.install(
                downloadedModel: harness.downloadedModel,
                int8Directory: harness.int8Directory,
                destinationDirectory: harness.destination,
                spec: spec
            )
            Issue.record("Fingerprint mismatch must fail closed.")
        } catch let error as KokoroFP32InstallError {
            #expect(error == .runtimeFingerprintMismatch)
        }
        #expect(!FileManager.default.fileExists(atPath: harness.destination.path))
    }

    @Test func missingInt8SupportFailsBeforeCopy() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        try FileManager.default.removeItem(at: harness.int8Directory)

        do {
            try KokoroFP32Installer.install(
                downloadedModel: harness.downloadedModel,
                int8Directory: harness.int8Directory,
                destinationDirectory: harness.destination,
                spec: harness.spec
            )
            Issue.record("Missing Int8 support must fail closed.")
        } catch let error as KokoroFP32InstallError {
            #expect(error == .int8SupportMissing)
        }
        #expect(!FileManager.default.fileExists(atPath: harness.destination.path))
    }

    @Test func cancellationLeavesDestinationUntouched() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        do {
            try KokoroFP32Installer.install(
                downloadedModel: harness.downloadedModel,
                int8Directory: harness.int8Directory,
                destinationDirectory: harness.destination,
                spec: harness.spec,
                isCancelled: { true }
            )
            Issue.record("Cancellation must fail closed.")
        } catch let error as KokoroFP32InstallError {
            #expect(error == .cancelled)
        }
        #expect(!FileManager.default.fileExists(atPath: harness.destination.path))
    }

    @Test func lateCancellationLeavesDestinationUntouched() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        var cancellationChecks = 0

        do {
            try KokoroFP32Installer.install(
                downloadedModel: harness.downloadedModel,
                int8Directory: harness.int8Directory,
                destinationDirectory: harness.destination,
                spec: harness.spec,
                isCancelled: {
                    cancellationChecks += 1
                    return cancellationChecks > 5
                }
            )
            Issue.record("Cancellation after hashing must fail closed.")
        } catch let error as KokoroFP32InstallError {
            #expect(error == .cancelled)
        }
        #expect(!FileManager.default.fileExists(atPath: harness.destination.path))
    }

    @Test func reservedBytesCoverTwoModelCopies() {
        let model = KokoroModelPack.fp32V019.expectedModelByteCount
        let reserved = KokoroFP32Installer.reservedInstallBytes(modelByteCount: model)
        #expect(reserved >= model * 2)
        #expect(reserved > 800_000_000)
    }

    private struct Harness {
        let root: URL
        let int8Directory: URL
        let destination: URL
        let downloadedModel: URL
        let spec: KokoroFP32Installer.Spec

        init() throws {
            let fileManager = FileManager.default
            root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            int8Directory = root.appendingPathComponent("int8")
            destination = root.appendingPathComponent("fp32")
            downloadedModel = root.appendingPathComponent("incoming-model.onnx")
            try fileManager.createDirectory(at: int8Directory, withIntermediateDirectories: true)
            try Data("voices-bin".utf8).write(
                to: int8Directory.appendingPathComponent("voices.bin")
            )
            try Data("tokens-txt".utf8).write(
                to: int8Directory.appendingPathComponent("tokens.txt")
            )
            let eSpeak = int8Directory.appendingPathComponent("espeak-ng-data")
            try fileManager.createDirectory(at: eSpeak, withIntermediateDirectories: true)
            try Data("z".utf8).write(to: eSpeak.appendingPathComponent("z"))
            try Data("a".utf8).write(to: eSpeak.appendingPathComponent("a"))

            let modelData = Data("tiny-fp32-model".utf8)
            try modelData.write(to: downloadedModel)

            let assembled = root.appendingPathComponent("assembled")
            try fileManager.copyItem(at: int8Directory, to: assembled)
            try fileManager.copyItem(
                at: downloadedModel,
                to: assembled.appendingPathComponent("model.onnx")
            )
            let fingerprint = try KokoroRuntimeFingerprint.runtimeContentSHA256(
                modelFileName: "model.onnx",
                in: assembled
            )
            spec = KokoroFP32Installer.Spec(
                modelFileName: "model.onnx",
                expectedModelByteCount: Int64(modelData.count),
                expectedModelSHA256: SHA256.hash(data: modelData)
                    .map { String(format: "%02x", $0) }
                    .joined(),
                expectedRuntimeContentSHA256: fingerprint,
                markerFileName: ".kudos-kokoro-fp32-v0_19-verified",
                markerContents: "test-marker\nruntime-content-sha256=\(fingerprint)\n"
            )
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
#endif
