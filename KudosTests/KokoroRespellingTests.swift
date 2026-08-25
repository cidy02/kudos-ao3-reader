import Foundation
import Testing
@testable import Kudos

/// Respelling exists because the pronunciation store takes IPA and nobody
/// types IPA. `her-MY-oh-nee` is what dictionaries and fandom wikis use.
///
/// The phonemizer is injected, so these run without a downloaded model pack
/// and assert the *assembly* — splitting, stress placement, stress stripping —
/// rather than re-testing G2P, which has its own suites.
@Suite("Kokoro respelling")
struct KokoroRespellingTests {
    /// A stand-in with distinctive values, so a wrong syllable order or a
    /// dropped syllable is visible in the output rather than plausible.
    private let table: [String: String] = [
        "her": "hɜɹ",
        "my": "mˈI",      // carries its own stress, which must be stripped
        "oh": "O",
        "nee": "ni",
        "an": "ˈæn",
        "na": "nə"
    ]

    private func phonemize(_ syllable: String) async -> String? { table[syllable] }

    @Test func capitalisedSyllableTakesPrimaryStress() async throws {
        let ipa = await KokoroRespelling.ipa(forRespelling: "her-MY-oh-nee") {
            await phonemize($0)
        }
        // her + m<ˈ>I + O + ni — the mark sits before the vowel of the
        // stressed syllable, matching `hɜɹmˈIəni` in the real lexicon.
        #expect(ipa == "hɜɹmˈIOni")
    }

    /// A syllable's own lookup may carry stress; only the respelling's mark
    /// should survive, or the word ends up with two primaries.
    @Test func syllableStressIsStrippedBeforeReassembly() async throws {
        let ipa = await KokoroRespelling.ipa(forRespelling: "AN-na") { await phonemize($0) }
        #expect(ipa == "ˈænnə")   // æ is the first vowel, so the mark leads
        #expect(ipa?.filter { $0 == KokoroRespelling.primaryStress }.count == 1)
    }

    /// All-capitals means "no marked stress", not "stress everything" — else
    /// `ANNA` would come out with a primary on each syllable.
    @Test func allCapitalsMeansNoMarkedStress() async throws {
        let ipa = await KokoroRespelling.ipa(forRespelling: "AN-NA") { await phonemize($0) }
        #expect(ipa == "ænnə")
        #expect(ipa?.contains(KokoroRespelling.primaryStress) == false)
    }

    @Test func stressIndexIsNilWhenNothingIsCapitalised() {
        #expect(KokoroRespelling.stressedIndex(in: ["her", "my"]) == nil)
        #expect(KokoroRespelling.stressedIndex(in: ["her", "MY"]) == 1)
        #expect(KokoroRespelling.stressedIndex(in: ["HER", "MY"]) == nil)
    }

    @Test func emptyAndMalformedInputIsHandled() async throws {
        #expect(await KokoroRespelling.ipa(forRespelling: "") { await phonemize($0) } == nil)
        #expect(await KokoroRespelling.ipa(forRespelling: "---") { await phonemize($0) } == nil)
        // Doubled and trailing hyphens must not produce empty syllables.
        let ipa = await KokoroRespelling.ipa(forRespelling: "her--my-") { await phonemize($0) }
        #expect(ipa == "hɜɹmI")   // no capitals, so no stress is added
    }

    /// A syllable G2P cannot resolve is skipped rather than aborting: a
    /// partial pronunciation the reader can edit beats a blank failure.
    @Test func unresolvableSyllablesAreSkipped() async throws {
        let ipa = await KokoroRespelling.ipa(forRespelling: "her-zzz-nee") { await phonemize($0) }
        #expect(ipa == "hɜɹni")
    }

    @Test func nothingResolvableReturnsNil() async throws {
        #expect(await KokoroRespelling.ipa(forRespelling: "zzz-qqq") { await phonemize($0) } == nil)
    }

    /// Someone pasting IPA they already have should not have it re-processed
    /// as if it were spelling.
    @Test func ipaIsRecognisedAndNotTreatedAsRespelling() {
        #expect(KokoroRespelling.looksLikeIPA("hɜɹmˈIəni"))
        #expect(KokoroRespelling.looksLikeIPA("mˈI"))
        #expect(!KokoroRespelling.looksLikeIPA("her-MY-oh-nee"))
        #expect(!KokoroRespelling.looksLikeIPA("anna"))
    }
    /// The mark goes before the vowel, not the syllable — `wˈɑnt`, never
    /// `ˈwɑnt`. Getting this wrong yields a string the model never saw.
    @Test func stressIsPlacedBeforeTheVowelNotTheSyllable() {
        #expect(KokoroRespelling.stressing("wɑnt") == "wˈɑnt")
        #expect(KokoroRespelling.stressing("æn") == "ˈæn")
        #expect(KokoroRespelling.stressing("stɹ") == "stɹ")   // no vowel: unmarked
    }
}
