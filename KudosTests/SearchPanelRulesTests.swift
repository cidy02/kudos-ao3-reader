import Foundation
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

    /// Docked filter edits stay in the draft until Show Works commits them, so results
    /// summaries, pagination, and Show Works counts reflect the applied query.
    @Test func dockedDraftEditsStayIsolatedUntilShowWorks() {
        var applied = AO3SearchFilters(query: "lighthouse")
        applied.completion = .complete

        var draft = applied
        draft.rating = .mature

        // Draft diverged from applied: Show Works drops the stale count; applied is untouched.
        #expect(AO3FilterPanel.resultsButtonTitle(
            mode: .search, filters: applied, referenceFilters: applied, totalWorks: 42, refineCount: 0
        ) == "Show 42 Works")
        #expect(AO3FilterPanel.resultsButtonTitle(
            mode: .search, filters: draft, referenceFilters: applied, totalWorks: 42, refineCount: 0
        ) == "Show Works")

        // Typing a new query syncs into the draft without discarding unapplied facets.
        let synced = SearchDockedFilterDraft.syncedDraft(draft, query: "sherlock")
        #expect(synced.query == "sherlock")
        #expect(synced.rating == .mature)
        #expect(applied.rating == .any)

        // Show Works commits the draft with the live search-bar query.
        let committed = SearchDockedFilterDraft.committed(draft: draft, query: "sherlock")
        #expect(committed.query == "sherlock")
        #expect(committed.rating == .mature)
        #expect(committed.completion == .complete)

        // Reset in docked mode clears facets in the draft while keeping the query.
        let reset = SearchDockedFilterDraft.resetDraft(query: "sherlock")
        #expect(reset.query == "sherlock")
        #expect(!reset.hasActiveFilters)
    }

    /// Tapping a result filter chip while Filters is docked never claims `.searchFilters`
    /// on the router, so an AO3 link submitted right after opens immediately rather than
    /// waiting for a dismissal callback that never comes.
    @Test func dockedFilterChipNeverStrandsAO3LinkInRouter() throws {
        #expect(!SearchDockedFilterDraft.shouldOpenRouterPanel(isFiltersDocked: true))
        #expect(SearchDockedFilterDraft.shouldOpenRouterPanel(isFiltersDocked: false))

        let workURL = try #require(URL(string: "https://archiveofourown.org/works/12345"))
        let router = AppRouter()
        router.selection = .search
        if SearchDockedFilterDraft.shouldOpenRouterPanel(isFiltersDocked: true) {
            router.panel = .searchFilters
        }
        router.openAO3Link(workURL)
        #expect(router.isPresentingLinkedWork)
        #expect(router.pendingWorkLink?.id == 12345)

        // If stale `.searchFilters` ownership was held before entering docked mode,
        // clearing it and invoking `panelDidDismiss()` delivers any queued link.
        let staleRouter = AppRouter()
        staleRouter.selection = .search
        staleRouter.panel = .searchFilters
        staleRouter.openAO3Link(workURL)
        #expect(!staleRouter.isPresentingLinkedWork)
        staleRouter.panel = .none
        staleRouter.panelDidDismiss()
        #expect(staleRouter.isPresentingLinkedWork)
        #expect(staleRouter.pendingWorkLink?.id == 12345)
    }
}
