import Testing
@testable import Kudos

@Suite("Reader TTS engine selection")
struct ReaderTTSEngineKindTests {
    @Test func missingModelUsesSystemVoice() {
        #expect(ReaderTTSEngineKind.preferred(modelDownloaded: false) == .system)
    }

    @Test func downloadedModelUsesKokoro() {
        #expect(ReaderTTSEngineKind.preferred(modelDownloaded: true) == .kokoro)
    }
}
