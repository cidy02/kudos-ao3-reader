import SwiftData
import SwiftUI

/// Native AO3 discovery (Part 6): browse categories → fandoms → works, all in the
/// app's own card/list system. The AO3 website is a secondary "Open AO3 Website"
/// fallback (`AO3WebBrowserView`), not the primary experience. Architecture is kept
/// extensible (Tags / Collections / People can become sibling sections later).
struct BrowseView: View {
    @Environment(AppRouter.self) private var router

    @State private var path = NavigationPath()

    /// A pushed fandom → its native work results.
    private struct FandomRoute: Hashable { let name: String }

    var body: some View {
        NavigationStack(path: $path) {
            MediaBrowserView(onSelectFandom: { path.append(FandomRoute(name: $0)) })
                .navigationTitle("Browse")
            #if os(iOS)
                .toolbarTitleDisplayMode(.inlineLarge)
            #endif
                .navigationDestination(for: AO3MediaCategory.self) { category in
                    FandomListView(category: category) { path.append(FandomRoute(name: $0)) }
                }
                .navigationDestination(for: FandomRoute.self) { route in
                    FandomWorksView(fandom: route.name)
                }
                .navigationDestination(for: AO3TagWorksRequest.self) { request in
                    TagWorksView(request: request)
                }
                .navigationDestination(for: AO3WorkSummary.self) { work in
                    WorkDetailView(remote: work)
                }
                .ao3AuthorNavigation(path: $path, tab: .browse)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        // Root-hosted sheet (ContentView) — stays on Browse when Done.
                        Button { router.openWebsite() } label: {
                            Label("Open AO3 Website", systemImage: "safari")
                        }
                    }
                }
                // A tapped AO3 tag link (e.g. in a work's preface) → native tag works.
                .onChange(of: router.pendingTagWorks, initial: true) { _, request in
                    if let request {
                        path.append(request)
                        router.pendingTagWorks = nil
                    }
                }
        }
    }
}

/// Native AO3 work results for a single fandom (Browse → Category → Fandom → Works).
/// Reuses `AO3WorkRow`, `SearchPaginationBar`, and the polite `AO3Client.search`.
struct FandomWorksView: View {
    let fandom: String

    @State private var results: [AO3WorkSummary] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    /// AO3's own result-count heading for these results, when it sent one.
    @State private var resultSummary: AO3ResultSummary?
    @State private var phase: Phase = .loading
    @State private var expandAll = false
    /// The active filters for this fandom's works — seeded to just the fandom, then
    /// refined via the same filter panel the Search tab uses.
    @State private var filters: AO3SearchFilters
    @State private var showingFilters = false
    @State private var bulkSelection = RemoteWorkSelectionController()

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    init(fandom: String) {
        self.fandom = fandom
        _filters = State(initialValue: Self.baseline(for: fandom))
    }

    /// Filters scoped to just this page's fandom — also the reset baseline.
    private static func baseline(for fandom: String) -> AO3SearchFilters {
        var filters = AO3SearchFilters()
        filters.fandom = fandom
        // Date Updated, not the app-wide `.relevance` default: this screen reads
        // AO3's tag listing, which has no relevance ordering and sorts by
        // `revised_at` unless told otherwise (verified live). Seeding it here means
        // the sort is sent explicitly and the panel shows the order actually in
        // effect, rather than "Best Match" over date-ordered results.
        filters.sort = .dateUpdated
        filters.sortDirection = AO3SearchFilters.Sort.dateUpdated.naturalDirection
        return filters
    }

    /// True once the reader has set any filter beyond the page's fixed fandom.
    private var hasExtraFilters: Bool {
        filters != Self.baseline(for: fandom)
    }

    var body: some View {
        Group {
            if phase == .loading, results.isEmpty {
                // First load of this fandom's works — show the shape of the results.
                AO3WorkRowSkeletonList(count: 6)
            } else {
                List {
                    // Above pagination: the total describes the whole list, not
                    // the page you happen to be on.
                    if let heroSummary {
                        Section {
                            SearchResultsHero(
                                summary: heroSummary,
                                filterLabels: filters.summaryLabels(excluding: heroSummary.subject),
                                subjectField: heroSummary.subjectField(inAnyOf: results),
                                onEditFilters: { showingFilters = true }
                            )
                            .cardRow()
                        }
                    }
                    if showPagination { Section { paginationRow } }
                    Section {
                        ForEach(results) { work in
                            SelectableAO3WorkRow(work: work, expandAll: expandAll, controller: bulkSelection)
                                .cardRow(isSelected: bulkSelection.isSelecting && bulkSelection.selection.contains(work.id))
                        }
                    }
                    if showPagination { Section { paginationRow } }
                }
                .cardList()
                .refreshable {
                    await AO3Client.shared.invalidateCachedResponses()
                    await load(page: currentPage)
                }
                .overlay { statusOverlay }
            }
        }
        .navigationTitle(fandom)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            .toolbar { toolbarContent }
            .filterPanelPresentation(isPresented: $showingFilters) {
                AO3FilterPanel(
                    filters: $filters,
                    allowsRelevanceSort: false,
                    showFandomPicker: false,
                    canReset: hasExtraFilters,
                    onApply: applyFilters,
                    onReset: resetFilters
                )
                .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            }
            .remoteWorkSelectionChrome(bulkSelection)
            .task { await load(page: 1) }
    }

    private var showPagination: Bool {
        totalPages > 1 && !results.isEmpty
    }

    private var paginationRow: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: phase == .loading
        ) { page in
            // A different page replaces `results` with different works entirely —
            // a stale selection would otherwise reference IDs that no longer exist.
            bulkSelection.selection.removeAll()
            Task { await load(page: page) }
        }
        .bareListRow()
    }

    @ViewBuilder
    private var statusOverlay: some View {
        // First-load (loading + empty) is handled upstream by the skeleton list, so it
        // never reaches this overlay; only the empty/failed result states do.
        switch phase {
        case .loaded where results.isEmpty && hasExtraFilters:
            // Over-filtered to nothing — the toolbar's hidden with no results, so offer
            // the reset here (re-runs the fandom search with just the fandom).
            ContentUnavailableView {
                Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No works in this fandom match the current filters.")
            } actions: {
                Button("Clear Filters", action: resetFilters)
            }
        case .loaded where results.isEmpty:
            ContentUnavailableView(
                "No works found",
                systemImage: "books.vertical",
                description: Text("No works for this fandom right now.")
            )
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load works", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load(page: currentPage) } }
            }
        default:
            EmptyView()
        }
    }

    /// `FandomWorksView` runs a `/works/search`, whose heading is a bare count —
    /// but this screen *is* this fandom's works list, so it can name its own
    /// subject and work out which slice of the total is on screen.
    private var heroSummary: AO3ResultSummary? {
        resultSummary?.completing(subject: fandom, page: currentPage, onPageCount: results.count)
    }

    private func load(page: Int) async {
        // Always, not only on a first load: with results already on screen this
        // is what tells the pagination bar a fetch is running. The list itself
        // still shows the results (the skeleton branch is gated on `results`
        // being empty), so nothing flashes — the pager just stops pretending
        // the tap did nothing.
        phase = .loading
        do {
            // Browse reads AO3's tag listing, not /works/search: same works and
            // same filters, but the page states its own "1 - 20 of N Works in
            // <fandom>" heading, so the results card shows AO3's figures rather
            // than ones derived here.
            let result = try await AO3Client.shared.fandomWorksPage(
                fandom: fandom, filters: filters, page: page
            )
            results = result.works
            currentPage = result.currentPage
            totalPages = result.totalPages
            resultSummary = result.summary
            phase = .loaded
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Clear the current page (so the first-load skeleton shows) and re-run the fandom
    /// search with whatever filters are now set — the same single request, just newly
    /// parameterised.
    private func reload() {
        phase = .loading
        results = []
        currentPage = 1
        totalPages = 1
        resultSummary = nil
        Task { await load(page: 1) }
    }

    /// Apply the chosen filters and close the panel.
    private func applyFilters() {
        showingFilters = false
        reload()
    }

    /// Reset back to the page's fandom-only filters (keeping the panel open).
    private func resetFilters() {
        filters = Self.baseline(for: fandom)
        reload()
    }

    // MARK: Multi-select / bulk actions

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if bulkSelection.isSelecting {
            RemoteWorkSelectionToolbar(controller: bulkSelection) {
                bulkSelection.selected(in: results)
            }
        } else if phase == .loaded, !results.isEmpty {
            ActionToolbar(items: [
                AnyView(FilterButton(filtersActive: hasExtraFilters,
                                      showingFilters: $showingFilters,
                                      filterHelp: "Filter works in this fandom",
                                      onClearFilters: resetFilters)),
                AnyView(WorkListMoreMenu {
                    Button { bulkSelection.isSelecting = true } label: {
                        Label("Select", systemImage: "checklist")
                    }
                    ExpandAllMenuItem(expandAll: $expandAll)
                })
            ])
        }
    }
}

/// A tag's works, loaded natively from an AO3 `/tags/<name>/works` URL (e.g. a tag
/// link tapped in a work's preface). Reuses the search result row, pagination, and
/// first-load skeleton, and filters through AO3 exactly as `FandomWorksView` does.
///
/// **This screen used to filter the fetched page in memory**, which is why its
/// panel offered only a third of the controls: you cannot sort 20 works out of
/// 142,000, and a blurb does not say whether a work is a crossover. Worse, the
/// header and pager went on reporting AO3's *unfiltered* totals while the list
/// showed the survivors — "142,362 works, page 1 of 5,000" above three cards.
///
/// AO3 honours every `work_search[...]` parameter on a tag listing (23 of 23
/// measured, `docs/reports/filter-parity-2026-08-07.md`), so the filters are sent
/// with the request instead. The counts are AO3's answer to the actual question,
/// the full panel applies, and sorting works across the whole tag.
struct TagWorksView: View {
    let request: AO3TagWorksRequest

    @State private var results: [AO3WorkSummary] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    /// AO3's own result-count heading for these results, when it sent one.
    @State private var resultSummary: AO3ResultSummary?
    @State private var phase: Phase = .loading
    @State private var expandAll = false
    @State private var filters = Self.baseline
    @State private var showingFilters = false
    @State private var bulkSelection = RemoteWorkSelectionController()

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    /// Date Updated, not the app-wide `.relevance` default — same reasoning as
    /// `FandomWorksView.baseline(for:)`: a tag listing has no relevance ordering
    /// and sorts by `revised_at` unless told otherwise, so seeding it means the
    /// panel names the order actually in effect.
    private static var baseline: AO3SearchFilters {
        var filters = AO3SearchFilters()
        filters.sort = .dateUpdated
        filters.sortDirection = AO3SearchFilters.Sort.dateUpdated.naturalDirection
        return filters
    }

    /// Anything set beyond the baseline. Not `hasActiveFilters`, which counts the
    /// seeded sort and would leave the filter button lit on an untouched screen.
    private var hasExtraFilters: Bool {
        filters != Self.baseline
    }

    var body: some View {
        Group {
            if phase == .loading, results.isEmpty {
                AO3WorkRowSkeletonList(count: 6)
            } else {
                List {
                    // Above pagination: the total describes the whole list, not
                    // the page you happen to be on.
                    if let heroSummary {
                        Section {
                            SearchResultsHero(
                                summary: heroSummary,
                                filterLabels: filters.summaryLabels(excluding: heroSummary.subject),
                                subjectField: heroSummary.subjectField(inAnyOf: results),
                                onEditFilters: { showingFilters = true }
                            )
                            .cardRow()
                        }
                    }
                    if showPagination { Section { paginationRow } }
                    Section {
                        ForEach(results) { work in
                            SelectableAO3WorkRow(work: work, expandAll: expandAll, controller: bulkSelection)
                                .cardRow(isSelected: bulkSelection.isSelecting && bulkSelection.selection.contains(work.id))
                        }
                    }
                    if showPagination { Section { paginationRow } }
                }
                .cardList()
                .refreshable {
                    await AO3Client.shared.invalidateCachedResponses()
                    await load(page: currentPage)
                }
                .overlay { statusOverlay }
            }
        }
        .navigationTitle(request.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            .toolbar { toolbarContent }
            .filterPanelPresentation(isPresented: $showingFilters) {
                AO3FilterPanel(
                    filters: $filters,
                    allowsRelevanceSort: false,
                    canReset: hasExtraFilters,
                    onApply: applyFilters,
                    onReset: resetFilters
                )
                .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            }
            .remoteWorkSelectionChrome(bulkSelection)
            .task { await load(page: 1) }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if bulkSelection.isSelecting {
            RemoteWorkSelectionToolbar(controller: bulkSelection) {
                bulkSelection.selected(in: results)
            }
        } else if phase == .loaded, !results.isEmpty {
            ActionToolbar(items: [
                AnyView(FilterButton(filtersActive: hasExtraFilters,
                                      showingFilters: $showingFilters,
                                      onClearFilters: resetFilters)),
                AnyView(WorkListMoreMenu {
                    Button { bulkSelection.isSelecting = true } label: {
                        Label("Select", systemImage: "checklist")
                    }
                    ExpandAllMenuItem(expandAll: $expandAll)
                })
            ])
        }
    }

    private var showPagination: Bool {
        totalPages > 1 && !results.isEmpty
    }

    private var paginationRow: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: phase == .loading
        ) { page in
            // A different page replaces `results` with different works entirely —
            // a stale selection would otherwise reference IDs that no longer exist.
            bulkSelection.selection.removeAll()
            Task { await load(page: page) }
        }
        .bareListRow()
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch phase {
        case .loaded where results.isEmpty && hasExtraFilters:
            // Over-filtered to nothing. AO3 searched the whole tag and found none,
            // so this is the real answer rather than "none on this page".
            ContentUnavailableView {
                Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No works with this tag match the current filters.")
            } actions: {
                Button("Clear Filters", action: resetFilters)
            }
        case .loaded where results.isEmpty:
            ContentUnavailableView(
                "No works found",
                systemImage: "tag",
                description: Text("No works for this tag right now.")
            )
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load works", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load(page: currentPage) } }
            }
        default:
            EmptyView()
        }
    }

    /// A `/tags/<t>/works` heading already names its tag and its range, so
    /// `completing` normally changes nothing here — it matters when this request
    /// resolves to a URL whose heading is a bare count.
    private var heroSummary: AO3ResultSummary? {
        resultSummary?.completing(
            subject: request.title, page: currentPage, onPageCount: results.count
        )
    }

    /// Apply the chosen filters and close the panel. Back to page 1: page 7 of the
    /// old result set is not page 7 of the new one, and AO3 would answer a page
    /// number past the filtered end with nothing at all.
    private func applyFilters() {
        showingFilters = false
        reload()
    }

    /// Back to the tag's own listing, keeping the panel open.
    private func resetFilters() {
        guard hasExtraFilters else { return }
        filters = Self.baseline
        reload()
    }

    private func reload() {
        phase = .loading
        results = []
        currentPage = 1
        totalPages = 1
        resultSummary = nil
        bulkSelection.selection.removeAll()
        Task { await load(page: 1) }
    }

    private func load(page: Int) async {
        // Always, not only on a first load: with results already on screen this
        // is what tells the pagination bar a fetch is running. The list itself
        // still shows the results (the skeleton branch is gated on `results`
        // being empty), so nothing flashes — the pager just stops pretending
        // the tap did nothing.
        phase = .loading
        do {
            let result = try await AO3Client.shared.worksPage(
                at: request.url, filters: filters, page: page
            )
            results = result.works
            currentPage = result.currentPage
            totalPages = result.totalPages
            resultSummary = result.summary
            phase = .loaded
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
