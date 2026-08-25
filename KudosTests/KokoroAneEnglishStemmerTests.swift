#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// Regular-inflection derivation in `KokoroAneEnglishPhonemizer.resolveWord`.
///
/// The downloaded lexicon has patchy coverage of the regular suffixes:
/// `walking` / `walked` / `cats` / `asked` are present, but `wanted` /
/// `belongs` / `characters` / `companies` / `towards` are absent. Misaki
/// compensates with three stemmers (`stem_s`, `stem_ed`, `stem_ing`).
/// Measured over 2.44M corpus words: 113,827 reach G2P (4.7%) and the
/// three stemmers recover 49,457 of them — 43.4%.
///
/// Possessive `X's` is the `"'s"` branch of `stem_s`, so it falls out of
/// the general version rather than being special-cased. The existing
/// `KokoroAneEnglishPossessiveTests` suite is the possessive contract
/// and is not modified here.
///
/// Stand-in IPA is chosen so each stem actually ends in the phoneme the
/// allomorph keys on. Affricates and `ɡ` are the single Misaki
/// codepoints; ASCII `g` is not in the consonant set. Derivation is
/// gated on the stem already being a lexicon hit — G2P handed the whole
/// token already applies the suffix, so deriving on top would double it.
@Suite("Kokoro English inflection stemmers")
struct KokoroAneEnglishStemmerTests {

    /// Distinctive stand-in tokens. Each derivation base ends in the
    /// phoneme the allomorph keys on. `characters` is a marker so a
    /// re-derivation cannot hide behind the same IPA.
    private let words: [String: [String]] = [
        // -s
        "cat": ["k", "ˈ", "æ", "t"],
        "bus": ["b", "ˈ", "ʌ", "s"],
        "dog": ["d", "ˈ", "ɔ", "ɡ"],
        "company": ["k", "ˈ", "ʌ", "m", "p", "ə", "n", "i"],
        "that": ["ð", "ˈ", "æ", "t"],
        "anna": ["ˈ", "ɑ", "n", "ə"],
        "character": ["k", "ˈ", "ɛ", "ɹ", "ə", "k", "t", "ɚ"],
        // Not what `_s` would emit from `character` (`kˈɛɹəktɚz`).
        "characters": ["Q"],
        // -ed
        "ask": ["ˈ", "æ", "s", "k"],
        "need": ["n", "ˈ", "i", "d"],
        "open": ["ˈ", "O", "p", "ə", "n"],
        // American `notice` already has the flap; last phoneme is `s`,
        // so `_ed` appends `/t/` → `nˈOɾəst`.
        "notice": ["n", "ˈ", "O", "ɾ", "ə", "s"],
        // `t` preceded by a taut (`A` ∈ US_TAUS) → `ɾᵻd`.
        "wait": ["w", "ˈ", "A", "t"],
        // `t` preceded by `n` (not a taut) → `ᵻd`, no flap.
        "want": ["w", "ˈ", "ɑ", "n", "t"],
        // -ing
        "walk": ["w", "ˈ", "ɔ", "k"],
        "make": ["m", "ˈ", "A", "k"],
        "run": ["ɹ", "ˈ", "ʌ", "n"],
        "panic": ["p", "ˈ", "æ", "n", "ɪ", "k"],
        // `t` preceded by a taut (`ɪ` ∈ US_TAUS) → `ɾɪŋ`.
        "sit": ["s", "ˈ", "ɪ", "t"],
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

    // MARK: - stem_s

    /// `/s/` after `ptkfθ`. `cats` is the first-branch drop of a single
    /// `s` (`cat` is known, `cats` is not).
    @Test func voicelessStemTakesS() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("cats") { await recorder.g2p($0) }
        #expect(actual == "kˈæts")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `/ᵻz/` after a sibilant. `buses` is the `es` branch (`bus` is
    /// known, `buse` is not). Fails if the epenthetic vowel is `ɪ`, or
    /// if `s` is treated as voiceless and takes `/s/`.
    @Test func sibilantEsTakesEpentheticVowel() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("buses") { await recorder.g2p($0) }
        #expect(actual == "bˈʌsᵻz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `/z/` after a voiced consonant. IPA `ɡ` (U+0261), not ASCII `g`.
    @Test func voicedStemTakesZ() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("dogs") { await recorder.g2p($0) }
        #expect(actual == "dˈɔɡz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `ies` → stem `y`. `companies` is the most frequent `ies` miss in
    /// the corpus once `company` is known.
    @Test func iesRewritesToY() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("companies") { await recorder.g2p($0) }
        #expect(actual == "kˈʌmpəniz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `that's` is the `"'s"` branch of `stem_s` — the same branch that
    /// implements possessives, and the single most frequent `-s`
    /// recovery in the corpus (2,081 combined).
    @Test func thatsTakesSFromThat() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("that's") { await recorder.g2p($0) }
        #expect(actual == "ðˈæts")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// Possessives still fall out of general `stem_s`. The dedicated
    /// possessive suite is the full contract; this pins that widening
    /// the stemmer did not special-case `'s` away.
    @Test func possessiveStillDerivesFromStemS() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("Anna's") { await recorder.g2p($0) }
        #expect(actual == "ˈɑnəz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - stem_ed

    /// `/t/` after `pkfθʃsʧ`. `asked` strips `ed` to `ask`.
    @Test func voicelessEdTakesT() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("asked") { await recorder.g2p($0) }
        #expect(actual == "ˈæskt")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `/ᵻd/` after `d`. Fails if the epenthetic vowel is `ɪ`.
    @Test func dFinalEdTakesEpentheticVowel() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("needed") { await recorder.g2p($0) }
        #expect(actual == "nˈidᵻd")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `/d/` otherwise. `opened` is a frequent corpus recovery (478).
    @Test func otherwiseEdTakesD() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("opened") { await recorder.g2p($0) }
        #expect(actual == "ˈOpənd")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `noticed` must come out `nˈOɾəst` with the flap. The flap is
    /// already in the American stem (`notice` → `nˈOɾəs`); `_ed` then
    /// appends `/t/` because the stem ends in `/s/` (`s` ∈ `pkfθʃsʧ`).
    /// A paraphrase that tapped the final `t` of a made-up stem would
    /// emit `ɾᵻd` instead.
    @Test func noticedKeepsStemFlapAndAddsT() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("noticed") { await recorder.g2p($0) }
        #expect(actual == "nˈOɾəst")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// The `_ed` tapping rule itself: stem ends in `t` preceded by a
    /// `US_TAUS` character (`A`). `t` is replaced, not appended —
    /// `wˈAt` → `wˈAɾᵻd`, not `wˈAtᵻd`.
    @Test func tFinalStemAfterTausTakesFlap() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("waited") { await recorder.g2p($0) }
        #expect(actual == "wˈAɾᵻd")
        #expect(!actual.contains("tᵻ"))
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// A `t`-final stem whose preceding phoneme is not a taut keeps
    /// the `t` and takes `ᵻd`. `wanted` is the most frequent `-ed`
    /// recovery in the corpus (1,546).
    @Test func tFinalStemOtherwiseTakesEpenthetic() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("wanted") { await recorder.g2p($0) }
        #expect(actual == "wˈɑntᵻd")
        #expect(!actual.contains("ɾ"))
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - stem_ing

    /// Plain drop of `ing` when the stem is known.
    @Test func plainIngAppendsIng() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("walking") { await recorder.g2p($0) }
        #expect(actual == "wˈɔkɪŋ")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `e`-drop: `making` → `make`. `mak` is not in the stand-in
    /// lexicon, so the first branch must not win.
    @Test func eDropIngRestoresE() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("making") { await recorder.g2p($0) }
        #expect(actual == "mˈAkɪŋ")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// Doubled consonant: `running` → `run`. The regex class is
    /// `bcdgklmnprstvxz`; `n` is in it.
    @Test func doubledConsonantIngDropsTheDouble() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("running") { await recorder.g2p($0) }
        #expect(actual == "ɹˈʌnɪŋ")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `cking$` alternate of the same regex. `panicking` → `panic`
    /// because `panick` / `panicke` are unknown.
    @Test func ckingIngDropsCk() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("panicking") { await recorder.g2p($0) }
        #expect(actual == "pˈænɪkɪŋ")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    /// `sitting`-type tapping: stem ends in `t` preceded by a taut
    /// (`ɪ` ∈ US_TAUS) → `ɾɪŋ`, not `tɪŋ`.
    @Test func sittingTakesFlapIng() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("sitting") { await recorder.g2p($0) }
        #expect(actual == "sˈɪɾɪŋ")
        #expect(!actual.contains("tɪŋ"))
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }

    // MARK: - Gate

    /// An inflected form whose stem is unknown must not be rewritten
    /// from a G2P of the stem. Fallback sees the whole token, for each
    /// suffix, exactly as before the stemmers existed.
    @Test func unknownStemFallsThroughToG2PWithTheWholeToken() async throws {
        let recorder = FallbackRecorder()
        let plural = try await phonemize("blorps") { await recorder.g2p($0) }
        let past = try await phonemize("fnorded") { await recorder.g2p($0) }
        let gerund = try await phonemize("xyzzying") { await recorder.g2p($0) }
        #expect(plural == "<g2p:blorps>")
        #expect(past == "<g2p:fnorded>")
        #expect(gerund == "<g2p:xyzzying>")
        let recorded = await recorder.words
        #expect(
            recorded == ["blorps", "fnorded", "xyzzying"],
            "fallback must see the whole token, not the stem: \(recorded)"
        )
    }

    /// An inflected form already in the lexicon must not be re-derived.
    /// The marker `Q` is not what `_s` would emit from `character`
    /// (`kˈɛɹəktɚz`). `characters` is a frequent corpus recovery (423)
    /// and is present in this stand-in on purpose.
    @Test func lexiconInflectedFormIsReturnedAsIs() async throws {
        let recorder = FallbackRecorder()
        let actual = try await phonemize("characters") { await recorder.g2p($0) }
        #expect(actual == "Q")
        #expect(actual != "kˈɛɹəktɚz")
        let recorded = await recorder.words
        #expect(recorded.isEmpty)
    }
}
#endif
