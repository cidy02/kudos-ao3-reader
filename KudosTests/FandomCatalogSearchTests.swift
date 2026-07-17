import Foundation
import Testing
@testable import Kudos

/// The pure fandom-catalog search index behind Global Search's "Fandoms on AO3"
/// section (`FandomCatalog.searchIndex` / `rankedMatches`). These statics carry
/// the matching + ranking logic; the singleton only wires them to its cached
/// category lists, rebuilding the index lazily when the catalog changes.
struct FandomCatalogSearchTests {
    private func fandom(_ name: String, _ count: Int?) -> AO3Fandom {
        AO3Fandom(name: name, workCount: count)
    }

    @Test func searchIndexDedupesAcrossCategoriesKeepingHighestCount() {
        let index = FandomCatalog.searchIndex(over: [
            [fandom("Marvel", 120), fandom("Doctor Who", 900)],
            [fandom("Marvel", 4_000), fandom("Sherlock (TV)", 500)]
        ])

        // One entry per normalized name; the cross-category duplicate keeps the
        // copy with the higher work count, deterministically.
        #expect(index.count == 3)
        let marvel = index.first { $0.normalizedName == "marvel" }
        #expect(marvel?.fandom.workCount == 4_000)
        // Pre-sorted by work count descending so per-query scans never sort.
        #expect(index.map(\.normalizedName) == ["marvel", "doctor who", "sherlock (tv)"])
    }

    @Test func searchIndexNormalizesNamesForDiacriticAndCaseFolding() {
        let index = FandomCatalog.searchIndex(over: [[fandom("Pokémon", 10_000)]])
        #expect(index.first?.normalizedName == "pokemon")

        // End to end: a query typed without the accent still finds it.
        let matches = FandomCatalog.rankedMatches(
            in: index,
            normalizedQuery: WorkSearchIndex.normalize("POKEMON"),
            limit: 12
        )
        #expect(matches.map(\.name) == ["Pokémon"])
    }

    @Test func rankedMatchesPutsPrefixMatchesFirstThenByWorkCount() {
        let index = FandomCatalog.searchIndex(over: [[
            fandom("The Harbormaster", 9_000),   // substring match only
            fandom("Harry Potter - J. K. Rowling", 400_000),
            fandom("Harold Finch Mysteries", 50),
            fandom("Star Trek", 200_000)         // no match at all
        ]])

        let matches = FandomCatalog.rankedMatches(in: index, normalizedQuery: "har", limit: 12)

        // Both prefix matches (by count) come before the higher-count substring match.
        #expect(matches.map(\.name) == [
            "Harry Potter - J. K. Rowling",
            "Harold Finch Mysteries",
            "The Harbormaster"
        ])
    }

    @Test func rankedMatchesHonorsLimitAcrossBothBuckets() {
        let prefixHeavy = (1...20).map { fandom("Star Wars Sequel \($0)", 1_000 - $0) }
        let index = FandomCatalog.searchIndex(over: [prefixHeavy])

        let matches = FandomCatalog.rankedMatches(in: index, normalizedQuery: "star", limit: 12)
        #expect(matches.count == 12)
        // The early-exit scan must still surface the highest-count entries first.
        #expect(matches.first?.name == "Star Wars Sequel 1")

        // A limit larger than the substring bucket cap still fills from both buckets.
        let mixed = FandomCatalog.searchIndex(over: [[
            fandom("Star Trek", 300), fandom("Lone Star State", 200)
        ]])
        #expect(
            FandomCatalog.rankedMatches(in: mixed, normalizedQuery: "star", limit: 12)
                .map(\.name) == ["Star Trek", "Lone Star State"]
        )
    }
}
