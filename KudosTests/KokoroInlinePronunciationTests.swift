import Foundation
import Testing
@testable import Kudos

/// `[Worcester](/wˈʊstəɹ/)` — the notation Kokoro-FastAPI and MisakiSwift
/// already use, so corrections move between frontends instead of being
/// trapped in this app.
@Suite("Kokoro inline pronunciation")
struct KokoroInlinePronunciationTests {
    @Test func parsesASingleEntry() {
        let entries = KokoroInlinePronunciation.entries(in: "[Worcester](/wˈʊstəɹ/)")
        #expect(entries == [.init(word: "Worcester", phonemes: "wˈʊstəɹ")])
    }

    /// A pasted list usually has prose around it. Ignoring the gaps means a
    /// reader can paste a whole note without editing it down first.
    @Test func parsesEntriesEmbeddedInOtherText() {
        let text = """
        Corrections for this fandom:
        [Aziraphale](/ˈæzɪɹəfeɪl/) — the angel
        [Crowley](/kɹˈoʊli/), the other one
        """
        #expect(KokoroInlinePronunciation.entries(in: text).map(\.word)
            == ["Aziraphale", "Crowley"])
    }

    @Test func toleratesWhitespaceInsideTheBrackets() {
        let entries = KokoroInlinePronunciation.entries(in: "[ Liv ] ( / lˈɪv / )")
        #expect(entries == [.init(word: "Liv", phonemes: "lˈɪv")])
    }

    /// The word pattern is lazy, so adjacent brackets bind to the nearer one
    /// rather than being swallowed into a single oversized "word".
    @Test func adjacentBracketsBindToTheNearestPair() {
        let entries = KokoroInlinePronunciation.entries(in: "[a][b](/x/)")
        #expect(entries == [.init(word: "b", phonemes: "x")])
    }

    /// An unterminated entry must not consume the rest of the input — the
    /// phoneme run excludes `/` precisely so one typo cannot eat a whole list.
    @Test func anUnterminatedEntryDoesNotSwallowTheRest() {
        let text = "[broken](/oops [Liv](/lˈɪv/)"
        #expect(KokoroInlinePronunciation.entries(in: text).map(\.word) == ["Liv"])
    }

    @Test func rejectsMalformedAndEmptyForms() {
        #expect(KokoroInlinePronunciation.entries(in: "").isEmpty)
        #expect(KokoroInlinePronunciation.entries(in: "[Worcester]").isEmpty)
        #expect(KokoroInlinePronunciation.entries(in: "[Worcester](wˈʊstəɹ)").isEmpty)
        #expect(KokoroInlinePronunciation.entries(in: "[](//)").isEmpty)
        #expect(KokoroInlinePronunciation.entries(in: "[Worcester](//)").isEmpty)
    }

    /// Square brackets are common in prose; they must not be mistaken for
    /// pronunciation markup.
    @Test func ordinaryProseIsNotNotation() {
        #expect(!KokoroInlinePronunciation.looksLikeInlineNotation(
            "She [sic] walked away (quickly)."
        ))
        #expect(KokoroInlinePronunciation.looksLikeInlineNotation("[Liv](/lˈɪv/)"))
    }

    /// Round-trip: what we render must parse back to the same entries, or the
    /// export is a dead end.
    @Test func renderingRoundTrips() {
        let entries = [
            KokoroInlinePronunciation.Entry(word: "Tobio", phonemes: "tˈoʊbioʊ"),
            KokoroInlinePronunciation.Entry(word: "Oikawa", phonemes: "ɔɪkˈɑwə")
        ]
        let rendered = KokoroInlinePronunciation.text(for: entries)
        #expect(KokoroInlinePronunciation.entries(in: rendered) == entries)
    }

    /// Duplicates are preserved rather than resolved here — last-wins is the
    /// caller's policy, and a parser that silently dropped one would hide it.
    @Test func duplicatesArePreservedForTheCallerToResolve() {
        let entries = KokoroInlinePronunciation.entries(in: "[Sam](/a/)\n[Sam](/b/)")
        #expect(entries.map(\.phonemes) == ["a", "b"])
    }
}
