#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// Ranking the proper nouns a work repeats, from three sources that fail
/// differently. The load-bearing rule: the guessed log is the only *evidence*
/// — tags and NER are priors that reorder it, never sources of their own.
@Suite("Kokoro cast discovery")
struct KokoroCastDiscoveryTests {
    private func guess(_ word: String, _ count: Int) -> KokoroGuessedWordStore.Entry {
        .init(word: word, count: count, lastSeen: Date(timeIntervalSince1970: 0))
    }

    /// A word the lexicon already knows needs no correction however prominent
    /// it is, so a tag alone must never conjure a candidate.
    @Test func onlyGuessedWordsBecomeCandidates() {
        let ranked = KokoroCastDiscovery.rank(
            guessed: [guess("Marvolo", 5)],
            characterTags: ["Harry Potter", "Hermione Granger"]
        )
        #expect(ranked.map(\.word) == ["Marvolo"])
    }

    @Test func frequencyOrdersTheList() {
        let ranked = KokoroCastDiscovery.rank(
            guessed: [guess("rare", 1), guess("common", 9)]
        )
        #expect(ranked.map(\.word) == ["common", "rare"])
    }

    /// Being in the cast list is a strong hint that a name matters, so it
    /// outranks a slightly more frequent word that nothing else vouches for.
    @Test func aTaggedCharacterOutranksAMoreFrequentStranger() {
        let ranked = KokoroCastDiscovery.rank(
            guessed: [guess("Severus", 5), guess("noise", 8)],
            characterTags: ["Severus Snape"]
        )
        #expect(ranked.first?.word == "Severus")
    }

    @Test func recognisedNamesAreBoostedButLessThanTags() {
        let tagged = KokoroCastDiscovery.rank(
            guessed: [guess("A", 10)], characterTags: ["A"]
        ).first
        let recognised = KokoroCastDiscovery.rank(
            guessed: [guess("A", 10)], recognisedNames: ["A"]
        ).first
        #expect((tagged?.score ?? 0) > (recognised?.score ?? 0))
        #expect((recognised?.score ?? 0) > 10)
    }

    /// Disambiguators are cataloguing, not part of the name.
    @Test func characterTagsAreStrippedOfDisambiguators() {
        let names = KokoroCastDiscovery.namesFromCharacterTags(
            ["Hermione Granger (Harry Potter)"]
        )
        #expect(names.contains("Hermione Granger"))
        #expect(names.contains("Hermione"))
        #expect(names.contains("Granger"))
        #expect(!names.contains(where: { $0.contains("(") }))
    }

    /// Surnames matter on their own: a reader hears "Granger" far more often
    /// than the full tag, so the individual words have to be kept too.
    @Test func shortTagFragmentsAreDropped() {
        let names = KokoroCastDiscovery.namesFromCharacterTags(["Y Su (Some Fandom)"])
        // "Y" and "Su" are too short to be useful keys and would match noise.
        #expect(!names.contains("Y"))
        #expect(!names.contains("Su"))
        #expect(names.contains("Y Su"))
    }

    /// Ties must not shuffle between launches, or the list reorders itself
    /// every time it is opened.
    @Test func tiesBreakAlphabeticallyForAStableOrder() {
        let ranked = KokoroCastDiscovery.rank(
            guessed: [guess("zeta", 3), guess("alpha", 3)]
        )
        #expect(ranked.map(\.word) == ["alpha", "zeta"])
    }

    @Test func emptyInputProducesNoCandidates() {
        #expect(KokoroCastDiscovery.rank(guessed: []).isEmpty)
        #expect(KokoroCastDiscovery.namesFromCharacterTags([]).isEmpty)
        #expect(KokoroCastDiscovery.namesFromCharacterTags(["()"]).isEmpty)
    }

    /// NER is the source with no prior for invented words, which is exactly
    /// what fanfiction is full of — so this documents the limit rather than
    /// asserting it finds everything.
    @Test func recognisedNamesFindsOrdinaryPeopleNames() {
        let names = KokoroCastDiscovery.recognisedNames(
            in: "Sarah Connor walked to London with Michael."
        )
        #expect(names.contains("Sarah Connor") || names.contains("Sarah"))
    }
}
#endif
