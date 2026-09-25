import Testing
@testable import Kudos

/// The Search tab's filter panel and results screen (wave-3 audit, search-filters:
/// 1au.2, 1k.7, 1k.4, 1ax.2).
@MainActor
struct SearchPanelRulesTests {
    /// Refine reads "Include Not Rated" only once a rating is chosen (pinned by
    /// `AO3SummaryFilterRatingTests`), so under Any it is not drawn there. Search
    /// always draws it: off sends `-rating_ids:9`.
    @Test func includeNotRatedIsDrawnOnlyWhereItFilters() {
        #expect(!AO3FilterPanel.showsIncludeNotRated(mode: .refine, rating: .any))
        #expect(AO3FilterPanel.showsIncludeNotRated(mode: .refine, rating: .teen))
        #expect(AO3FilterPanel.showsIncludeNotRated(mode: .search, rating: .any))
    }

    /// Try Again after a failed page tap retries that page, not page 1.
    @Test func retryKeepsTheReaderOnTheirPage() {
        #expect(SearchRetry.page(requested: 5, current: 4, hasResults: true) == 5)
        #expect(SearchRetry.page(requested: nil, current: 4, hasResults: true) == 4)
        // The first load failed: nothing to stay on, so search again from the top.
        #expect(SearchRetry.page(requested: 5, current: 1, hasResults: false) == nil)
    }

    /// The toolbar badge counts what the hero's Filters cell counts: every label
    /// but the subject (the heading names it) and the sort.
    @Test func filterBadgeMatchesTheHeroFiltersCell() {
        var filters = AO3SearchFilters()
        filters.fandom = "Fandom A"
        filters.rating = .teen
        filters.completion = .complete

        let heroCell = filters.summaryLabels(excluding: filters.searchSubject.text)
            .filter { !$0.text.hasPrefix("Sort: ") }
            .count
        #expect(SearchFilterBadge.count(for: filters) == heroCell)
        #expect(SearchFilterBadge.count(for: filters) == 2)
        #expect(SearchFilterBadge.count(for: AO3SearchFilters()) == 0)
    }

    /// Named from the search subject, as the sheet's caption says: never the first
    /// of several fandoms.
    @Test func savedSearchNameIsTheSubject() {
        var twoFields = AO3SearchFilters()
        twoFields.fandom = "Fandom A, Fandom B"
        twoFields.characters = "Character C"
        #expect(SearchView.defaultSavedSearchName(for: twoFields) == "Saved Search")
        twoFields.query = "enemies to lovers"
        #expect(SearchView.defaultSavedSearchName(for: twoFields) == "enemies to lovers")

        var oneCharacter = AO3SearchFilters()
        oneCharacter.characters = "Character C"
        #expect(SearchView.defaultSavedSearchName(for: oneCharacter) == "Character C")

        var oneFandomAndQuery = AO3SearchFilters()
        oneFandomAndQuery.fandom = "Fandom A"
        oneFandomAndQuery.query = "slow burn"
        #expect(SearchView.defaultSavedSearchName(for: oneFandomAndQuery) == "Fandom A")
    }
}
