import Foundation

/// The two Kokoro v0.19 model variants that use Sherpa's compatible voice,
/// token, and eSpeak support files. FP32 is a developer-installed benchmark
/// pack until the app has a streaming archive installer.
enum KokoroModelPack: String, CaseIterable, Sendable {
    case int8V019 = "int8-v0.19"
    case fp32V019 = "fp32-v0.19"

    static let defaultPack: Self = .int8V019

    var displayName: String {
        switch self {
        case .int8V019: "Efficient (Int8)"
        case .fp32V019: "Full precision (FP32)"
        }
    }

    var modelDirectoryName: String {
        switch self {
        case .int8V019: "kokoro-int8-en-v0_19"
        case .fp32V019: "kokoro-en-v0_19"
        }
    }

    var modelFileName: String {
        switch self {
        case .int8V019: "model.int8.onnx"
        case .fp32V019: "model.onnx"
        }
    }

    var requiredFileNames: [String] {
        [modelFileName, "voices.bin", "tokens.txt"]
    }

    var requiresDeveloperInstallation: Bool {
        self == .fp32V019
    }

    /// FP32 is side-loaded, rather than app-downloaded, so it is not eligible
    /// for playback until the app has fingerprinted the complete official
    /// runtime data and written this marker locally.
    var validationMarkerFileName: String? {
        switch self {
        case .int8V019:
            nil
        case .fp32V019:
            ".kudos-kokoro-fp32-v0_19-verified"
        }
    }

    /// SHA-256 of the runtime files from the official Sherpa v0.19 FP32
    /// archive. The digest covers `model.onnx`, `voices.bin`, `tokens.txt`,
    /// and every regular file under `espeak-ng-data`, with each relative path
    /// included in the hash stream. It deliberately excludes README/LICENSE.
    var expectedRuntimeContentSHA256: String? {
        switch self {
        case .int8V019:
            nil
        case .fp32V019:
            "57dbaeaaab06ab7a813a996be93f0c9c9a1ccb45ef0d9921bc09e0f559cbce6a"
        }
    }

    var validationMarkerContents: String? {
        guard let expectedRuntimeContentSHA256 else { return nil }
        return """
        kudos-kokoro-pack=fp32-v0.19
        runtime-content-sha256=\(expectedRuntimeContentSHA256)
        """
    }

    static func resolving(_ rawValue: String?) -> Self {
        guard let rawValue, let pack = Self(rawValue: rawValue) else {
            return defaultPack
        }
        return pack
    }
}

/// Requests the ONNX Runtime execution provider used by Sherpa. Core ML is an
/// experiment: ORT may still use CPU/GPU for unsupported graph segments, so it
/// must not be represented as a guaranteed Neural Engine mode.
enum KokoroExecutionProvider: String, CaseIterable, Sendable {
    case cpu
    case coreML = "coreml"

    static let defaultProvider: Self = .cpu

    var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .coreML: "Core ML (Experimental)"
        }
    }

    var sherpaIdentifier: String { rawValue }

    static func resolving(_ rawValue: String?) -> Self {
        guard let rawValue, let provider = Self(rawValue: rawValue) else {
            return defaultProvider
        }
        return provider
    }
}

/// The complete choice that determines how a Kokoro service is constructed.
/// It is Equatable so a changed model or provider replaces a retained service
/// before the next utterance.
struct KokoroRuntimeConfiguration: Equatable, Sendable {
    let modelPack: KokoroModelPack
    let executionProvider: KokoroExecutionProvider

    /// FP32 keeps its selected preference while unavailable, but the reader
    /// only constructs a Kokoro service for a verified FP32 pack or a usable
    /// Int8 fallback. `nil` leaves engine selection on Apple TTS.
    static func resolved(
        requested: Self,
        isModelDownloaded: (KokoroModelPack) -> Bool
    ) -> Self? {
        if isModelDownloaded(requested.modelPack) {
            return requested
        }

        let int8Fallback = Self(
            modelPack: .int8V019,
            executionProvider: requested.executionProvider
        )
        return isModelDownloaded(int8Fallback.modelPack) ? int8Fallback : nil
    }

    static func needsEngineReplacement(
        currentKind: ReaderTTSEngineKind?,
        currentConfiguration: Self?,
        requestedKind: ReaderTTSEngineKind,
        requestedConfiguration: Self?
    ) -> Bool {
        currentKind != requestedKind || currentConfiguration != requestedConfiguration
    }
}
