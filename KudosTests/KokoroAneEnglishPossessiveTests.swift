#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// Possessive `X's` derivation in `KokoroAneEnglishPhonemizer.resolveWord`.
///
/// Proper-noun possessives miss the lexicon entirely and fall to neural
/// G2P with the apostrophe attached. Verified against the real
/// `us_lexicon_cache.json`: not one possessive is present, while every
/// base is (`anna` → `ˈɑnə`, `alice` → `ˈælɪs`, `pat` → `pˈæt`,
/// `james` → `ʤˈAmz`). Measured over a 20-work corpus: 5,896
/// proper-noun possessives, 462 distinct; when the base is in the
/// lexicon the possessive is there only ~37% of the time.
///
/// The allomorph is Misaki `_s` (MIT), not the textbook rule. The
/// voiceless set is exactly `ptkfθ`; the American epenthetic vowel is
/// `ᵻ` (U+1D7B), not `ɪ`; affricates are the single codepoints `ʧ`/`ʤ`.
/// Derivation is gated on the stem already being a lexicon hit — G2P
/// handed the whole token already applies the clitic, so deriving on
/// top would double it.
///
/// Follows upstream FluidAudio's phonemizer tests: a stand-in Misaki
/// lexicon, not the downloaded pack. These always run in CI.
@Suite("Kokoro English possessive allomorphs")
struct KokoroAneEnglishPossessiveTests {

    /// Distinctive stand-in tokens. Each derivation base ends in the
    /// phoneme the allomorph keys on. `cecil's` is a marker so a
    /// re-derivation cannot hide behind the same IPA.
    private let words: [String: [String]] = [
        "pat": ["p", "ˈ", "æ", "t"],
        "alice": ["ˈ", "æ", "l", "ɪ", "s"],
        "anna": ["ˈ", "ɑ", "n", "ə"],
        "mitch": ["m", "ˈ", "ɪ", "ʧ"],
        "ridge": ["ɹ", "ˈ", "ɪ", "ʤ"],
        "james": ["ʤ", "ˈ", "A", "m", "z"],
        "cecil": ["s", "ˈ", "ɛ", "s", "ə", "l"],
        // Not what `_s` would emit from `cecil` (`sˈɛsəlz`).
        "cecil's": ["Q"],
        // Contractions must keep winning as lexicon hits, including
        // `he's` which is `'s`-shaped and would otherwise look like a
        // possessive of `he`.
        "wasn't": ["w", "ˈ", "ʌ", "z", "ə", "n", "t"],
        "don't": ["d", "ˈ", "O", "n", "t"],
        "he's": ["h", "i", "z"],
        "he": ["h", "ˈ", "i"],
    ]

    private actor FallbackRecorder {
        var words: [String] = []
        func g2p(_ word: String) -> [String]? {
            words.append(word)
            return ["<g2p:\(word)>"]
        }
    }

    private func phonemize(
        _ text: String,
        fallback: @escaping (String) async throws -> [String]?
    ) async throws -> String {
        try await KokoroAneEnglishFrontend.phonemize(
            text,
            wordToPhonemes: words,
            fallback: fallback
        )
    }

    // MARK: - Allomorphs

    /// `/s/` after `ptkfθ`. A "all voiceless consonants" rule would
    /// also get `Pat's` right and then fail `Alice's`.
    @Test func voicelessStemTakesS() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("Pat's") { await recorder.g2p($0) }
        #expect(actual == "pˈæts")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `/ᵻz/` after a sibilant. Fails if the epenthetic vowel is `ɪ`,
    /// or if `s` is treated as voiceless and takes `/s/` (`ˈælɪss`).
    @Test func sibilantStemTakesEpentheticVowel() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("Alice's") { await recorder.g2p($0) }
        #expect(actual == "ˈælɪsᵻz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `/z/` after a vowel. The common proper-noun case (`Anna's`).
    @Test func vowelStemTakesZ() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("Anna's") { await recorder.g2p($0) }
        #expect(actual == "ˈɑnəz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// Single-codepoint affricates `ʧ`/`ʤ`. A comparison against the
    /// digraphs `tʃ`/`dʒ` silently fails and falls through to `/z/`.
    @Test func affricateStemTakesEpentheticVowel() async throws {
        let recorder = FallbackRecorder()
        let ch = try await phonemize("Mitch's") { await recorder.g2p($0) }
        let jh = try await phonemize("Ridge's") { await recorder.g2p($0) }
        #expect(ch == "mˈɪʧᵻz")
        #expect(jh == "ɹˈɪʤᵻz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - Case

    @Test func capitalisationDoesNotChangeTheAllomorph() async throws {
        let recorder = FallbackRecorder()
        let title = try await phonemize("Anna's") { await recorder.g2p($0) }
        let lower = try await phonemize("anna's") { await recorder.g2p($0) }
        let upper = try await phonemize("ANNA'S") { await recorder.g2p($0) }
        #expect(title == "ˈɑnəz")
        #expect(lower == "ˈɑnəz")
        #expect(upper == "ˈɑnəz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - Gate

    /// `liv` is absent from the real cache, which is why `Liv's` (360
    /// occurrences) is the most frequent miss. Deriving from a G2P of
    /// the stem would hand fallback `liv` and then append a clitic on
    /// top of a fallback that already applied one.
    @Test func unknownStemFallsThroughToG2PWithTheWholeToken() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("Liv's") { await recorder.g2p($0) }
        #expect(actual == "<g2p:liv's>")
        let recorded = await recorder.words
        #expect(
            recorded == ["liv's"],
            "fallback must see the whole token, not the stem: \(recorded)"
        )
    }

    /// A possessive that is already in the lexicon must not be
    /// re-derived. The marker `Q` is not what `_s` would emit from
    /// `cecil` (`sˈɛsəlz`).
    @Test func lexiconPossessiveIsReturnedAsIs() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("Cecil's") { await recorder.g2p($0) }
        #expect(actual == "Q")
        #expect(actual != "sˈɛsəlz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `James'` (apostrophe, no `s`) is out of scope: Misaki `stem_s`
    /// requires `word.endswith('s')`. The splitter also emits a trailing
    /// apostrophe as its own token, so this resolves as the base. Either
    /// way it must not grow the extra syllable `James's` does.
    @Test func apostropheOnlyPossessiveIsNotDerived() async throws {
        let recorder = FallbackRecorder()
        let bare = try await phonemize("James") { await recorder.g2p($0) }
        let apostropheOnly = try await phonemize("James'") { await recorder.g2p($0) }
        let withS = try await phonemize("James's") { await recorder.g2p($0) }
        #expect(bare == "ʤˈAmz")
        #expect(apostropheOnly == "ʤˈAmz")
        #expect(withS == "ʤˈAmzᵻz")
        #expect(!apostropheOnly.contains("ᵻ"))
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - Contractions

    /// `wasn't` does not end in `'s`; `don't` is a different clitic;
    /// `he's` is `'s`-shaped but a lexicon contraction of `he`, whose
    /// derived form would keep the stem stress (`hˈiz`).
    @Test func contractionsStillResolveFromTheLexicon() async throws {
        let recorder = FallbackRecorder()
        let wasnt = try await phonemize("wasn't") { await recorder.g2p($0) }
        let dont = try await phonemize("don't") { await recorder.g2p($0) }
        let hes = try await phonemize("he's") { await recorder.g2p($0) }
        #expect(wasnt == "wˈʌzənt")
        #expect(dont == "dˈOnt")
        #expect(hes == "hiz")
        #expect(hes != "hˈiz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }
}
#endif
