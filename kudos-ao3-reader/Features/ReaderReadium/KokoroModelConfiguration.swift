import Foundation

/// The two Kokoro v0.19 model variants that use Sherpa's compatible voice,
/// token, and eSpeak support files. FP32 is installed in-app by downloading
/// only the official `model.onnx` and copying support files from the Int8 pack.
nonisolated enum KokoroModelPack: String, CaseIterable, Sendable {
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
        KokoroRuntimeFingerprint.rootFileNames(modelFileName: modelFileName)
    }

    /// FP32 reuses the Int8 pack's `voices.bin`, `tokens.txt`, and
    /// `espeak-ng-data` rather than unpacking the 320 MB official tar.
    var requiresInt8SupportFiles: Bool {
        self == .fp32V019
    }

    var downloadURL: URL {
        switch self {
        case .int8V019:
            URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/"
                + "kokoro-int8-en-v0_19.tar.bz2")!
        case .fp32V019:
            URL(string: "https://huggingface.co/csukuangfj/kokoro-en-v0_19/resolve/"
                + "92805c485745946a0d945562d3aba19e7cbb2104/model.onnx?download=true")!
        }
    }

    var expectedModelByteCount: Int64 {
        switch self {
        case .int8V019:
            0
        case .fp32V019:
            345_555_491
        }
    }

    var expectedModelSHA256: String {
        switch self {
        case .int8V019:
            ""
        case .fp32V019:
            "10ff414106a038ce7e9e0126c6461e4dc8a86efaa89dc91d2009d69fe635e339"
        }
    }

    /// The Int8 archive is verified before extraction. FP32 verifies the
    /// single model file with `expectedModelSHA256` instead.
    var expectedArchiveSHA256: String? {
        switch self {
        case .int8V019:
            "c9f0dd393615805b0bab050c340834d5e684e732aec91c0e860cd30e982c08bd"
        case .fp32V019:
            nil
        }
    }

    var reservedInstallBytes: Int64 {
        switch self {
        case .int8V019:
            300_000_000
        case .fp32V019:
            KokoroFP32Installer.reservedInstallBytes(modelByteCount: expectedModelByteCount)
        }
    }

    /// FP32 remains ineligible for playback until the assembled runtime has
    /// been fingerprinted and this marker written locally.
    var validationMarkerFileName: String? {
        switch self {
        case .int8V019:
            nil
        case .fp32V019:
            ".kudos-kokoro-fp32-v0_19-verified"
        }
    }

    /// SHA-256 of the assembled runtime: `model.onnx`, `voices.bin`,
    /// `tokens.txt`, then every regular eSpeak file in sorted relative-path
    /// order. Root files are never lexically reordered. README/LICENSE are
    /// excluded.
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
        model-sha256=\(expectedModelSHA256)
        runtime-content-sha256=\(expectedRuntimeContentSHA256)
        source=huggingface:csukuangfj/kokoro-en-v0_19@92805c485745946a0d945562d3aba19e7cbb2104
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
nonisolated enum KokoroExecutionProvider: String, CaseIterable, Sendable {
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
nonisolated struct KokoroRuntimeConfiguration: Equatable, Sendable {
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
