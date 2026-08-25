#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// The pre-flight runs the same frontend playback does, and there is exactly
/// one fallback observer to install. Most of what can go wrong is about that,
/// not about phonemes.
@Suite("Kokoro cast pre-flight")
struct KokoroCastPreflightTests {
    /// The important guard. `setNeuralFallbackObserver` replaces rather than
    /// adds, so scanning while Read Aloud is running would redirect the
    /// engine's own guesses into the scan's collector — the words the reader
    /// most wants recorded would be the ones silently lost.
    @Test func scanningDuringPlaybackIsRefused() async {
        await #expect(throws: KokoroCastPreflight.ScanError.playbackActive) {
            try await KokoroCastPreflight.scan(texts: ["Aziraphale"], isPlaying: true)
        }
    }

    /// Checked before the pack, so the refusal is the same on a device where
    /// the engine is unavailable *and* something is playing.
    @Test func theActiveCheckPrecedesAvailability() async {
        // No pack is installed in the simulator, so an unguarded
        // implementation would report `.unavailable` here instead.
        #expect(!KokoroCastPreflight.isAvailable)
        await #expect(throws: KokoroCastPreflight.ScanError.playbackActive) {
            try await KokoroCastPreflight.scan(texts: ["Crowley"], isPlaying: true)
        }
    }

    /// Without the Core ML pack there is no frontend to ask — sherpa-onnx
    /// takes text and returns audio, exposing no G2P — so the caller must be
    /// told rather than handed an empty result that looks like "nothing found".
    @Test func scanningWithoutTheEngineIsRefused() async {
        await #expect(throws: KokoroCastPreflight.ScanError.unavailable) {
            try await KokoroCastPreflight.scan(texts: ["Rhiannon"], isPlaying: false)
        }
    }
}
#endif
