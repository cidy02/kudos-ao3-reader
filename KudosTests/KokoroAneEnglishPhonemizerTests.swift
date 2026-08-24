#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// Fanfic recoveries in `KokoroAneEnglishPhonemizer.resolveWord`:
/// apostrophe reinsertion (`DONT` → `don't`) and de-elongation
/// (`YESSS` → `yes`), plus the ordering that keeps `cant` / `beer` /
/// genuine initialisms unchanged.
///
/// Follows upstream FluidAudio's phonemizer tests: a stand-in Misaki
/// lexicon, not the downloaded pack. These always run in CI.
@Suite("Kokoro English fanfic recoveries")
struct KokoroAneEnglishPhonemizerRecoveryTests {

    /// Distinctive stand-in tokens so a wrong recovery cannot collide
    /// with letter-name spelling (spaces between letters) or G2P
    /// (`<g2p:…>`).
    private let words: [String: [String]] = [
        "don't": ["d", "ˈ", "O", "n", "t"],
        "i'm": ["a", "ɪ", "m"],
        "you're": ["j", "ʊ", "ɹ"],
        "he's": ["h", "i", "z"],
        "c'mon": ["k", "ə", "m", "ˈ", "ɑ", "n"],
        "ain't": ["ˈ", "eɪ", "n", "t"],
        "yes": ["j", "ˈ", "ɛ", "s"],
        "yay": ["j", "ˈ", "A"],
        "him": ["h", "ˈ", "ɪ", "m"],
        "you": ["j", "ˈ", "u"],
        "me": ["m", "ˈ", "i"],
        // Ordinary words that must win before recoveries run.
        "cant": ["k", "ˈ", "æ", "n", "t"],
        "can't": ["k", "ˈ", "ɑ", "n", "t"],
        "beer": ["b", "ˈ", "ɪ", "ɹ"],
        // Traps. Each of these is a real lexicon entry that an unguarded
        // recovery would reach, so a guard test without them would pass
        // whether or not the guard exists.
        "p's": ["p", "ˈ", "i", "z"],
        "b's": ["b", "ˈ", "i", "z"],
        "i": ["ˈ", "I"],
        "l": ["ˈ", "ɛ", "l"],
        "xi": ["z", "ˈ", "aɪ"],
        // Native-double traps: each pair is a real word whose spelling already
        // doubles, next to the shorter word an over-eager collapse produced.
        "good": ["ɡ", "ˈ", "ʊ", "d"], "god": ["ɡ", "ˈ", "ɑ", "d"],
        "soon": ["s", "ˈ", "u", "n"], "son": ["s", "ˈ", "ʌ", "n"],
        "all": ["ˈ", "ɔ", "l"], "al": ["ˈ", "æ", "l"],
    ]

    /// Per-letter names used to spell all-caps initialisms. Enough of
    /// the alphabet to cover the tokens these tests send through
    /// `EnglishInitialisms.isCandidate`.
    private let letters: [String: [String]] = [
        "A": ["ˈ", "A"],
        "C": ["s", "ˈ", "i"],
        "D": ["d", "ˈ", "i"],
        "E": ["ˈ", "i"],
        "F": ["ˈ", "ɛ", "f"],
        "G": ["dʒ", "ˈ", "i"],
        "H": ["ˈ", "A", "tʃ"],
        "I": ["ˈ", "I"],
        "M": ["ˈ", "ɛ", "m"],
        "N": ["ˈ", "ɛ", "n"],
        "O": ["ˈ", "O"],
        "P": ["p", "ˈ", "i"],
        "R": ["ˈ", "ɑ", "ɹ"],
        "S": ["ˈ", "ɛ", "s"],
        "T": ["t", "ˈ", "i"],
        "U": ["j", "ˈ", "u"],
        "B": ["b", "ˈ", "i"],
        "L": ["ˈ", "ɛ", "l"],
        "V": ["v", "ˈ", "i"],
        "X": ["ˈ", "ɛ", "k", "s"],
        "Y": ["w", "ˈ", "aɪ"],
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
            caseSensitiveWordToPhonemes: letters,
            fallback: fallback
        )
    }

    // MARK: - Apostrophe reinsertion

    @Test func strippedContractionsResolveAsContractionsNotLetterNames() async throws {
        let recorder = FallbackRecorder()
        let cases: [(token: String, contraction: String)] = [
            ("DONT", "don't"),
            ("IM", "i'm"),
            ("YOURE", "you're"),
            ("HES", "he's"),
            ("CMON", "c'mon"),
            ("AINT", "ain't"),
        ]
        for item in cases {
            let recovered = try await phonemize(item.token) { await recorder.g2p($0) }
            let expected = try await phonemize(item.contraction) { await recorder.g2p($0) }
            #expect(
                recovered == expected,
                "\(item.token) should read as \(item.contraction), got \(recovered)"
            )
            #expect(
                !recovered.contains(" "),
                "\(item.token) must not be spelled as letter names (\(recovered))"
            )
        }
        let recorded = await recorder.words
        #expect(recorded.isEmpty, "contractions must not reach G2P: \(recorded)")
    }

    @Test func lowercaseStrippedContractionAlsoRecovers() async throws {
        let recorder = FallbackRecorder()
        let recovered = try await phonemize("dont") { await recorder.g2p($0) }
        #expect(recovered == "dˈOnt")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - De-elongation

    @Test func elongatedWordsResolveToTheBaseWord() async throws {
        let recorder = FallbackRecorder()
        let cases: [(token: String, base: String)] = [
            ("YESSS", "yes"),
            ("YAYYY", "yay"),
            ("HIMMM", "him"),
            ("YOUU", "you"),
            ("MEE", "me"),
        ]
        for item in cases {
            let recovered = try await phonemize(item.token) { await recorder.g2p($0) }
            let expected = try await phonemize(item.base) { await recorder.g2p($0) }
            #expect(
                recovered == expected,
                "\(item.token) should read as \(item.base), got \(recovered)"
            )
            #expect(
                !recovered.contains(" "),
                "\(item.token) must not be spelled as letter names (\(recovered))"
            )
        }
        let recorded = await recorder.words
        #expect(recorded.isEmpty, "de-elongated words must not reach G2P: \(recorded)")
    }

    @Test func lowercaseElongationAlsoRecovers() async throws {
        let recorder = FallbackRecorder()
        let recovered = try await phonemize("yesss") { await recorder.g2p($0) }
        #expect(recovered == "jˈɛs")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - Initialism regressions

    @Test func genuineInitialismsStillSpellAsLetterNames() async throws {
        let recorder = FallbackRecorder()
        let cases: [(token: String, expected: String)] = [
            ("PDF", "pˈi dˈi ˈɛf"),
            ("TG", "tˈi dʒˈi"),
            ("DNA", "dˈi ˈɛn ˈA"),
            ("TV", "tˈi vˈi"),
        ]
        for item in cases {
            let spelled = try await phonemize(item.token) { await recorder.g2p($0) }
            #expect(spelled == item.expected, "\(item.token) → \(spelled)")
        }
        let recorded = await recorder.words
        #expect(recorded.isEmpty, "initialisms must not reach G2P: \(recorded)")
    }

    // MARK: - Ordering regressions

    @Test func cantStaysTheOrdinaryWordNotTheContraction() async throws {
        let recorder = FallbackRecorder()
        let result = try await phonemize("cant") { await recorder.g2p($0) }
        #expect(result == "kˈænt", "cant must not become can't")
        let contraction = try await phonemize("can't") { await recorder.g2p($0) }
        #expect(result != contraction)
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    @Test func beerIsUnchangedByDeElongation() async throws {
        let recorder = FallbackRecorder()
        let result = try await phonemize("beer") { await recorder.g2p($0) }
        #expect(result == "bˈɪɹ")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }
    // MARK: - Guards (measured regressions in the first implementation)

    /// The lexicon carries `p's` / `b's` as letter *plurals*, so unguarded
    /// apostrophe reinsertion read `PS` (the postscript) as "peas" and `BS`
    /// as "bees". Measured: 22 occurrences in the corpus, every one wrong.
    @Test func singleLetterPluralsAreNotTreatedAsContractions() async throws {
        let recorder = FallbackRecorder()
        for token in ["PS", "BS"] {
            let actual = try await phonemize(token) { await recorder.g2p($0) }
            #expect(
                actual.contains(" "),
                "\(token) must stay letter-spelled, not become a plural (\(actual))"
            )
        }
    }

    /// A token spelled only from Roman numeral letters is a numeral, not an
    /// elongated word. Unguarded, `II` collapsed to `i` and `XXXII` (32) to
    /// `xi` (11) — 42 of 73 de-elongation hits in the corpus were this.
    @Test func romanNumeralsAreNotDeElongated() async throws {
        let recorder = FallbackRecorder()
        for token in ["II", "III", "XXXII", "LL"] {
            let actual = try await phonemize(token) { await recorder.g2p($0) }
            #expect(
                actual.contains(" "),
                "\(token) is a numeral and must stay letter-spelled (\(actual))"
            )
        }
    }

    /// The guards must not cost us the recoveries they sit next to.
    @Test func guardsDoNotBlockGenuineRecoveries() async throws {
        let recorder = FallbackRecorder()
        let expectedYes = try await phonemize("yes") { await recorder.g2p($0) }
        let expectedMe = try await phonemize("me") { await recorder.g2p($0) }
        // Hoisted out of `#expect`: the macro expansion loses `try`, so an
        // inline `try await` in the condition does not compile.
        let yesss = try await phonemize("YESSS") { await recorder.g2p($0) }
        let mee = try await phonemize("MEE") { await recorder.g2p($0) }
        #expect(yesss == expectedYes)
        #expect(mee == expectedMe)
    }
    /// Written elongation lands on the *end* of a word — a writer holds the
    /// last sound. Collapsing every run at once flattened the word's own
    /// spelling too, so `GOODD` resolved to `god` and `SOONN` to `son`.
    /// Found by replaying the real lexicon, not by inspection.
    @Test func elongationDoesNotFlattenAWordsOwnDoubleLetter() async throws {
        let recorder = FallbackRecorder()
        let cases = [("GOODD", "good"), ("SOONN", "soon"), ("ALLL", "all")]
        for item in cases {
            let actual = try await phonemize(item.0) { await recorder.g2p($0) }
            let expected = try await phonemize(item.1) { await recorder.g2p($0) }
            #expect(actual == expected, "\(item.0) should read as \(item.1), got \(actual)")
        }
    }

    /// `normalizeKey` keeps `'` and drops `-`, so the candidate `p'-s` is four
    /// characters — past a raw length check — yet still normalizes to `p's`.
    @Test func hyphenDoesNotSmuggleALetterPluralPastTheGuard() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("P-S") { await recorder.g2p($0) }
        let peas = try await phonemize("p's") { await recorder.g2p($0) }
        #expect(actual != peas, "P-S must not read as a letter plural (\(actual))")
    }

    /// The numeral guard has to tolerate decoration: testing the whole token
    /// let `XXX-II` through, where it collapsed to `x-i` and resolved as XI.
    @Test func decoratedRomanNumeralsStayNumerals() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("XXX-II") { await recorder.g2p($0) }
        let xi = try await phonemize("xi") { await recorder.g2p($0) }
        #expect(actual != xi, "XXX-II (32) must not read as XI (11): \(actual)")
    }
    /// Apostrophe reinsertion is quadratic in token length, and fanfic
    /// supplies unbroken keysmashes and long URLs. Nothing longer than the
    /// lexicon's longest key can match, so long tokens must not pay for the
    /// search — they should fall straight through to G2P.
    @Test func veryLongTokensSkipTheApostropheSearch() async throws {
        let recorder = FallbackRecorder()
        let keysmash = String(repeating: "asdfghjkl", count: 12)   // 108 chars
        let actual = try await phonemize(keysmash) { await recorder.g2p($0) }
        #expect(actual.contains("<g2p:"), "long token should reach G2P, got \(actual)")
        let seen = await recorder.words
        #expect(seen == [keysmash], "expected one G2P call, got \(seen.count)")
    }
}
#endif
