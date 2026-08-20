import Testing
@testable import Kudos

@Suite("Reader TTS engine selection")
struct ReaderTTSEngineKindTests {
    @Test func automaticUsesSystemVoiceWhenModelIsMissing() {
        #expect(
            ReaderTTSEngineKind.effective(
                requestedRawValue: "",
                modelDownloaded: false
            ) == .system
        )
    }

    @Test func automaticUsesKokoroWhenModelIsDownloaded() {
        #expect(
            ReaderTTSEngineKind.effective(
                requestedRawValue: "",
                modelDownloaded: true
            ) == .kokoro
        )
    }

    @Test func explicitAppleChoiceWinsWhenKokoroIsDownloaded() {
        #expect(
            ReaderTTSEngineKind.effective(
                requestedRawValue: ReaderTTSEngineKind.system.rawValue,
                modelDownloaded: true
            ) == .system
        )
    }

    @Test func explicitKokoroChoiceUsesAppleUntilPackIsReady() {
        #expect(
            ReaderTTSEngineKind.effective(
                requestedRawValue: ReaderTTSEngineKind.kokoro.rawValue,
                modelDownloaded: false
            ) == .system
        )
        #expect(
            ReaderTTSEngineKind.effective(
                requestedRawValue: ReaderTTSEngineKind.kokoro.rawValue,
                modelDownloaded: true
            ) == .kokoro
        )
    }

    @Test func unknownStoredChoiceBehavesAsAutomatic() {
        #expect(
            ReaderTTSEngineKind.effective(
                requestedRawValue: "future-engine",
                modelDownloaded: true
            ) == .kokoro
        )
    }
}
