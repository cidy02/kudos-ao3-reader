import Testing
@testable import Kudos

struct SearchFiltersTests {
    @Test func tagSelectionCyclesIncludeExcludeClear() {
        #expect(TagFilterState.clear.next == .included)
        #expect(TagFilterState.included.next == .excluded)
        #expect(TagFilterState.excluded.next == .clear)
    }

    @Test func defaultsDoNotAlterTheQuery() {
        let filters = AO3SearchFilters()

        #expect(!filters.hasActiveFilters)
        #expect(filters.searchQuery.isEmpty)
        #expect(filters.structuredRatingID == nil)
    }

    @Test func exactRatingUsesStructuredField() {
        var filters = AO3SearchFilters()
        filters.query = "slow burn"
        filters.rating = .mature
        filters.includeNotRated = false

        #expect(filters.searchQuery == "slow burn")
        #expect(filters.structuredRatingID == "12")
    }

    @Test func ratingPlusUsesAORatingExpression() {
        var filters = AO3SearchFilters()
        filters.rating = .mature
        filters.ratingMatch = .orHigher
        filters.includeNotRated = false

        #expect(filters.searchQuery == "(rating_ids:12 OR rating_ids:13)")
        #expect(filters.structuredRatingID == nil)
    }

    @Test func ratingMinusCanIncludeUnratedWorks() {
        var filters = AO3SearchFilters()
        filters.rating = .teen
        filters.ratingMatch = .orLower
        filters.includeNotRated = true

        #expect(
            filters.searchQuery
                == "(rating_ids:10 OR rating_ids:11 OR rating_ids:9)"
        )
        #expect(filters.structuredRatingID == nil)
    }

    @Test func anyRatingCanExcludeUnratedWorks() {
        var filters = AO3SearchFilters()
        filters.includeNotRated = false

        #expect(filters.hasActiveFilters)
        #expect(filters.searchQuery == "-rating_ids:9")
        #expect(filters.structuredRatingID == nil)
    }

    @Test func categorizedExclusionsBecomeDeduplicatedQueryClauses() {
        var filters = AO3SearchFilters()
        filters.excludedFandoms = "Naruto, Star Wars"
        filters.excludedCharacters = "Naruto"
        filters.excludedRelationships = "Alice/Bob"

        #expect(
            filters.searchQuery
                == "-\"Naruto\" -\"Star Wars\" -\"Alice/Bob\""
        )
    }
}
