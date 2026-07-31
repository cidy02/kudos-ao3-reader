#if os(iOS)
import Foundation
import ReadiumNavigator
import ReadiumShared
import Testing
@testable import Kudos

@Suite("Reader speech preferences")
struct ReaderSpeechPreferencesTests {
    @Test func cleanUtteranceTextCollapsesWhitespaceAndSoftHyphens() {
        let raw = "Hello\u{00A0}world.\n\nNext\u{00AD}line   here."
        let cleaned = ReaderSpeechPreferences.cleanUtteranceText(raw)
        #expect(cleaned == "Hello world. Nextline here.")
    }

    @Test func cleanUtteranceTextTrimsEdges() {
        #expect(ReaderSpeechPreferences.cleanUtteranceText("  hi  ") == "hi")
    }

    @Test func resolvedVoiceIdentifierKeepsStoredPreferenceWhenPresent() {
        let voices = [
            makeVoice(id: "a", name: "A", language: "en-US", quality: .medium),
            makeVoice(id: "b", name: "B", language: "en-US", quality: .higher),
        ]
        let resolved = ReaderSpeechPreferences.resolvedVoiceIdentifier(
            preferredID: "a",
            language: Language(code: .bcp47("en")),
            voices: voices
        )
        #expect(resolved == "a")
    }

    @Test func resolvedVoiceIdentifierPicksBestWhenPreferenceMissing() {
        let voices = [
            makeVoice(id: "compact", name: "Compact", language: "en-US", quality: .low),
            makeVoice(id: "premium", name: "Premium", language: "en-US", quality: .higher),
            makeVoice(id: "fr", name: "French", language: "fr-FR", quality: .higher),
        ]
        let resolved = ReaderSpeechPreferences.resolvedVoiceIdentifier(
            preferredID: "",
            language: Language(code: .bcp47("en")),
            voices: voices
        )
        #expect(resolved == "premium")
    }

    @Test func resolvedVoiceIdentifierFallsBackWhenStoredVoiceGone() {
        let voices = [
            makeVoice(id: "only", name: "Only", language: "en-GB", quality: .high),
        ]
        let resolved = ReaderSpeechPreferences.resolvedVoiceIdentifier(
            preferredID: "deleted-voice",
            language: Language(code: .bcp47("en")),
            voices: voices
        )
        #expect(resolved == "only")
    }

    @Test func bestVoicePrefersMatchingLanguage() {
        let voices = [
            makeVoice(id: "en", name: "English", language: "en-US", quality: .medium),
            makeVoice(id: "de", name: "German", language: "de-DE", quality: .higher),
        ]
        let best = ReaderSpeechPreferences.bestVoice(
            for: Language(code: .bcp47("de")),
            from: voices
        )
        #expect(best?.identifier == "de")
    }

    private func makeVoice(
        id: String,
        name: String,
        language: String,
        quality: TTSVoice.Quality
    ) -> TTSVoice {
        TTSVoice(
            identifier: id,
            language: Language(code: .bcp47(language)),
            name: name,
            gender: .unspecified,
            quality: quality
        )
    }
}
#endif
