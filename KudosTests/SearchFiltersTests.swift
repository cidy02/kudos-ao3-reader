import Foundation
import Testing
@testable import Kudos

struct SearchFiltersTests {
    @Test func filterSelectionCyclesIncludeExcludeClear() {
        #expect(FilterSelectionState.clear.next == .included)
        #expect(FilterSelectionState.included.next == .excluded)
        #expect(FilterSelectionState.excluded.next == .clear)
    }

    @Test func defaultsDoNotAlterTheQuery() {
        let filters = AO3SearchFilters()

        #expect(!filters.hasActiveFilters)
        #expect(filters.searchQuery.isEmpty)
        #expect(filters.structuredRatingID == nil)
    }

    /// Saved Searches persist the whole filter set via Codable, so a round-trip must
    /// reproduce every facet exactly.
    @Test func filtersCodableRoundTripIsLossless() throws {
        var filters = AO3SearchFilters()
        filters.query = "found family"
        filters.fandom = "Naruto, Bleach"
        filters.excludedAdditionalTags = "Angst"
        filters.rating = .teen
        filters.ratingMatch = .orHigher
        filters.includeNotRated = false
        filters.warnings = [.noWarnings]
        filters.categories = [.gen]
        filters.excludedCategories = [.mm]
        filters.crossover = .exclude
        filters.completion = .complete
        filters.wordsFrom = "1000"
        filters.wordsTo = "50000"
        filters.updated = .week
        filters.language = .english
        filters.sort = .kudos

        let data = try JSONEncoder().encode(filters)
        let decoded = try JSONDecoder().decode(AO3SearchFilters.self, from: data)
        #expect(decoded == filters)
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

    @Test func warningExclusionsUseAO3FieldSyntax() {
        var filters = AO3SearchFilters()
        filters.excludedWarnings = [.noWarnings, .underage]

        #expect(
            filters.searchQuery
                == "-archive_warning_ids:16 -archive_warning_ids:20"
        )
    }

    @Test func categoryExclusionsUseAO3FieldSyntax() {
        var filters = AO3SearchFilters()
        filters.excludedCategories = [.mm, .other]

        #expect(filters.searchQuery == "-category_ids:23 -category_ids:24")
    }
}
