import Testing
@testable import Kudos

/// The Search tab's filter panel and results screen (wave-3 audit, search-filters:
/// 1au.2, 1k.7, 1k.4, 1ax.2).
@MainActor
struct SearchPanelRulesTests {
    /// Try Again after a failed page tap retries that page, not page 1.
    @Test func retryKeepsTheReaderOnTheirPage() {
        #expect(SearchRetry.page(requested: 5, current: 4, hasResults: true) == 5)
        #expect(SearchRetry.page(requested: nil, current: 4, hasResults: true) == 4)
        // The first load failed: nothing to stay on, so search again from the top.
        #expect(SearchRetry.page(requested: 5, current: 1, hasResults: false) == nil)
    }

    /// Closing the filter panel without Apply drops its edits for the search on screen, or
    /// on its way; in Browse, after Back, there is no search and the edits stand. A search
    /// abandoned during its first load used to come back there (review A32-12).
    @Test func aClosedPanelPutsBackTheSearchOnScreenAndNothingInBrowse() {
        var abandoned = AO3SearchFilters()
        abandoned.fandom = "Fandom A"
        abandoned.completion = .complete
        var edited = AO3SearchFilters(query: "typed since")
        edited.rating = .teen

        var back = abandoned
        back.query = "typed since"
        // Results on screen, and a first search still loading: the edits go, the query stays.
        #expect(SearchPanelClose.restored(live: edited, loaded: abandoned, requested: nil, isIdle: false) == back)
        #expect(SearchPanelClose.restored(live: edited, loaded: nil, requested: abandoned, isIdle: false) == back)
        // Browse: whatever an abandoned search left behind, the edits stand.
        #expect(SearchPanelClose.restored(live: edited, loaded: nil, requested: abandoned, isIdle: true) == nil)
        #expect(SearchPanelClose.restored(live: edited, loaded: nil, requested: nil, isIdle: false) == nil)
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
