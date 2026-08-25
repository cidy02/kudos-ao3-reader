import Foundation
import Testing
@testable import Kudos

/// The rule under test is one sentence: an emphasised word must carry primary
/// stress. The interesting part is what it deliberately does *not* do.
@Suite("Kokoro emphasis")
struct KokoroEmphasisTests {
    /// The 5.7% case. `not` is `nˌɑt` unemphasised and `nˈɑt` emphasised —
    /// real values from the shipped lexicon, and the single most emphasised
    /// word in the corpus after proper nouns.
    @Test func aLoneSecondaryIsPromoted() {
        #expect(KokoroEmphasis.stressed("nˌɑt") == "nˈɑt")
        #expect(KokoroEmphasis.stressed("wˌI") == "wˈI")
        #expect(KokoroEmphasis.stressed("sˌO") == "sˈO")
    }

    /// The 9.6% case: no stress at all is a function word's weak form, and
    /// emphasis is exactly when English reaches for the strong one.
    @Test func aWeakFormGainsStress() {
        #expect(KokoroEmphasis.stressed("ju") == "jˈu")
        #expect(KokoroEmphasis.stressed("ɑɹ") == "ˈɑɹ")
        #expect(KokoroEmphasis.stressed("hæv") == "hˈæv")
    }

    /// The 68.1% case, and the one most likely to be "fixed" by someone who
    /// has not measured: a word that already carries primary stress has no
    /// lever. A second `ˈ` appears in no lexicon entry and would be a string
    /// the model never saw.
    @Test func aWordThatAlreadyHasPrimaryStressIsLeftAlone() {
        #expect(KokoroEmphasis.stressed("wˈɑnt") == nil)
        #expect(KokoroEmphasis.stressed("ˈɑskəɹ") == nil)
        #expect(KokoroEmphasis.stressed("dˈænjəl") == nil)
    }

    /// Only the first secondary is promoted, or a long word ends up with two
    /// primaries — which is not a thing English does.
    @Test func onlyTheFirstSecondaryIsPromoted() {
        let out = KokoroEmphasis.stressed("ˌæbˌsO")
        #expect(out == "ˈæbˌsO")
        #expect(out?.filter { $0 == KokoroEmphasis.primaryStress }.count == 1)
    }

    /// Stress goes before the vowel, matching the lexicon's own convention.
    @Test func addedStressPrecedesTheVowelNotTheWord() {
        #expect(KokoroEmphasis.stressed("hæv") == "hˈæv")
        #expect(KokoroEmphasis.stressed("bi") == "bˈi")
    }

    @Test func emptyOrVowellessInputChangesNothing() {
        #expect(KokoroEmphasis.stressed("") == nil)
        #expect(KokoroEmphasis.stressed("stɹ") == nil)
    }

    /// A long italic run is typographic, not emphatic — a letter, a dream
    /// sequence, a passage in another language. Stressing every word in one
    /// would be worse than leaving it alone. 6% of spans are 11+ words.
    @Test func longRunsAreNotTreatedAsEmphasis() {
        #expect(KokoroEmphasis.isEmphasisWorthApplying(to: "not"))
        #expect(KokoroEmphasis.isEmphasisWorthApplying(to: "did not say"))
        #expect(!KokoroEmphasis.isEmphasisWorthApplying(to: ""))
        #expect(!KokoroEmphasis.isEmphasisWorthApplying(
            to: "a whole paragraph set in italics because it is a letter"
        ))
    }
}
