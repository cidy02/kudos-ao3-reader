#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// Contextual weak forms for `the`/`The` and `to`/`To` in
/// `KokoroAneEnglishPhonemizer.phonemize`.
///
/// The bundled lexicon stores only the strong form (`ði`, `tu`), so
/// "the book" currently says "thee book". Measured in the 20-work corpus:
/// 105,383 `the` and 67,403 `to` — about 7% of every word spoken. The
/// rule is Misaki's phoneme-based `future_vowel`, not a letter rule:
/// `the hour` takes `ði` (silent h, vowel-initial IPA) and
/// `the university` takes `ðə` (the `/j/` glide).
///
/// Follows upstream FluidAudio's phonemizer tests: a stand-in Misaki
/// lexicon, not the downloaded pack. These always run in CI.
@Suite("Kokoro English the/to sandhi")
struct KokoroAneEnglishWeakFormTests {

    /// Distinctive stand-in tokens. `hour` is stress-then-vowel so a
    /// first-character rule (which would see `ˈ`) cannot cheat; `go`
    /// uses IPA `ɡ` (U+0261), because ASCII `g` is not in Misaki's
    /// consonant set and would be skipped through to the following vowel.
    private let words: [String: [String]] = [
        // A SENTINEL, not the real gold. With `ði` here, every assertion of
        // `ði` below would pass whether or not the sandhi pass ran — which is
        // exactly how two of these tests were vacuous. `ðX` is never a correct
        // output, so any `ði`/`ðə` result proves the pass rewrote it.
        "the": ["ð", "X"],
        "to": ["t", "u"],
        "book": ["b", "ˈ", "ʊ", "k"],
        "apple": ["ˈ", "æ", "p", "ə", "l"],
        "go": ["ɡ", "ˈ", "O"],
        "eat": ["ˈ", "i", "t"],
        "hour": ["ˈ", "aʊ", "ɚ"],
        "university": ["j", "ˌ", "u", "n", "ə", "v", "ˈ", "ɜ", "ɹ", "s", "ə", "t", "i"],
        "yes": ["j", "ˈ", "ɛ", "s"],
        "him": ["h", "ˈ", "ɪ", "m"],
        // Scope guard: Misaki's `a` rule is POS-gated (`ɐ` if DT). A
        // context-free override would turn the letter name into a schwa.
        "a": ["A"],
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
        customLexicon: [String: String] = [:],
        allowedPunctuation: Set<Character> = [],
        fallback: @escaping (String) async throws -> [String]?
    ) async throws -> String {
        try await KokoroAneEnglishFrontend.phonemize(
            text,
            wordToPhonemes: words,
            customLexicon: customLexicon,
            allowedPunctuation: allowedPunctuation,
            fallback: fallback
        )
    }

    // MARK: - `the`

    @Test func theBookTakesTheSchwa() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("the book") { await recorder.g2p($0) }
        #expect(actual == "ðə bˈʊk")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    @Test func theAppleTakesTheVowelForm() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("the apple") { await recorder.g2p($0) }
        #expect(actual == "ði ˈæpəl")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// Silent h: the lexicon entry begins with a vowel, so this is `ði`
    /// even though the spelling starts with a consonant. A letter-based
    /// rule gets it wrong; that is the whole point of running on phonemes.
    @Test func theHourTakesTheVowelForm() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("the hour") { await recorder.g2p($0) }
        #expect(actual == "ði ˈaʊɚ")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// The `/j/` glide is a consonant, so this is `ðə` even though the
    /// spelling starts with a vowel. Paired with `the hour` to prove the
    /// trigger is the following phoneme, not the following letter.
    @Test func theUniversityTakesTheSchwa() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("the university") { await recorder.g2p($0) }
        #expect(actual == "ðə jˌunəvˈɜɹsəti")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// Misaki `future_vowel == True` is not truthiness: unknown falls
    /// back to `ðə`, the opposite of the lexicon's constant `ði`.
    @Test func theAtEndOfInputTakesTheSchwa() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("the") { await recorder.g2p($0) }
        #expect(actual == "ðə")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// The splitter glues the comma onto `the`, so the next token in
    /// Misaki is punctuation (unknown), not `apple`. Looking through the
    /// comma would emit `ði` here.
    @Test func theWithTrailingCommaTakesTheSchwaEvenBeforeAVowel() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize(
            "the, apple",
            allowedPunctuation: [","],
            fallback: { await recorder.g2p($0) }
        )
        #expect(actual == "ðə, ˈæpəl")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    @Test func capitalisedTheBehavesLikeThe() async throws {
        let recorder = FallbackRecorder()
        let beforeConsonant = try await phonemize("The book") { await recorder.g2p($0) }
        let beforeVowel = try await phonemize("The apple") { await recorder.g2p($0) }
        #expect(beforeConsonant == "ðə bˈʊk")
        #expect(beforeVowel == "ði ˈæpəl")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// All-caps `THE` is POS-gated in Misaki (`tag == 'DT'`). Without a
    /// tagger we leave it as whatever the lexicon holds.
    @Test func allCapsTHEIsNotRewritten() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("THE book") { await recorder.g2p($0) }
        // The sentinel gold, untouched. Asserting `ði` here was ambiguous —
        // it could mean "left alone" or "rewritten to the vowel form".
        // `ðX` can only mean the pass skipped it, which is the point.
        #expect(actual == "ðX bˈʊk")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - `to`

    @Test func toGoTakesTheSchwa() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("to go") { await recorder.g2p($0) }
        #expect(actual == "tə ɡˈO")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    @Test func toEatTakesTheLaxVowel() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("to eat") { await recorder.g2p($0) }
        #expect(actual == "tʊ ˈit")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// Unknown neighbour keeps the lexicon gold (`tu`), unlike `the`
    /// which falls back to the schwa.
    @Test func toAtEndOfInputKeepsTheLexiconForm() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("to") { await recorder.g2p($0) }
        #expect(actual == "tu")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    @Test func toWithTrailingCommaKeepsTheLexiconFormEvenBeforeAVowel() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize(
            "to, eat",
            allowedPunctuation: [","],
            fallback: { await recorder.g2p($0) }
        )
        #expect(actual == "tu, ˈit")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    @Test func capitalisedToBehavesLikeTo() async throws {
        let recorder = FallbackRecorder()
        let beforeConsonant = try await phonemize("To go") { await recorder.g2p($0) }
        let beforeVowel = try await phonemize("To eat") { await recorder.g2p($0) }
        #expect(beforeConsonant == "tə ɡˈO")
        #expect(beforeVowel == "tʊ ˈit")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    @Test func allCapsTOIsNotRewritten() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("TO go") { await recorder.g2p($0) }
        #expect(actual == "tu ɡˈO")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - Scope and non-interference

    /// `a` is POS-gated in Misaki. The lexicon stores the FACE diphthong
    /// (the letter name); a context-free schwa override is out of scope.
    @Test func indefiniteArticleIsNotRewritten() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("a book") { await recorder.g2p($0) }
        #expect(actual == "A bˈʊk")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    @Test func textWithNoTheOrToIsUnchanged() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("yes him book apple") { await recorder.g2p($0) }
        #expect(actual == "jˈɛs hˈɪm bˈʊk ˈæpəl")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }
    // MARK: - Adversarial-review fixes

    /// A custom entry is tier 1 and outranks this pass. Before the guard, the
    /// reader's own correction was looked up and then silently overwritten in
    /// every context — and the public API documents `["to": "tə"]` as its
    /// example, so this is the first thing anyone would try.
    @Test func aCustomPronunciationIsNotOverwritten() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize(
            "to apple", customLexicon: ["to": "CUSTOM"]
        ) { await recorder.g2p($0) }
        #expect(actual == "CUSTOM ˈæpəl", "custom entry must win over the sandhi pass")
    }

    /// Misaki excludes `"`, `\u{201C}` and `\u{201D}` from `NON_QUOTE_PUNCTS`, so a
    /// quoted title stays transparent and the vowel behind it still counts.
    /// Fic is full of these, so it is a live path rather than a corner case.
    @Test func aQuoteDoesNotHideTheFollowingVowel() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize(
            "to \u{201C}apple\u{201D}", allowedPunctuation: ["\u{201C}", "\u{201D}"]
        ) { await recorder.g2p($0) }
        #expect(
            actual.hasPrefix("tʊ"),
            "a quote must not end the vowel context, got \(actual)"
        )
    }

    /// The counterpart: a real non-quote mark *does* end it, so `to` keeps the
    /// lexicon's `tu` rather than guessing from across the comma.
    @Test func aCommaDoesEndTheVowelContext() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize(
            "to, apple", allowedPunctuation: [","]
        ) { await recorder.g2p($0) }
        #expect(actual.hasPrefix("tu,"), "a comma should leave the gold form, got \(actual)")
    }
}
#endif
