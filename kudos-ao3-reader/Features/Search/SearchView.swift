import SwiftData
import SwiftUI

// Lint: this existing screen coordinates local and remote search state.
/// Native AO3 work search. A search field with an adjacent filter button, results
/// paged like AO3 (numbered pages + first/prev/next/last), and a filter sidebar
/// for fandom, rating, sort, and completion.
struct SearchView: View { // swiftlint:disable:this type_body_length
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    // Local-first search sources (Global Search, Phase 2): matched on-device, live.
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var savedWorks: [SavedWork]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query(
        filter: #Predicate<WorkCollection> { !$0.isPendingDeletion },
        sort: \WorkCollection.dateAdded, order: .reverse
    )
    private var collections: [WorkCollection]
    @Query(sort: \SavedSearch.dateAdded, order: .reverse) private var savedSearches: [SavedSearch]

    @State private var filters = AO3SearchFilters()
    /// Name-entry alert for saving the current search.
    @State private var showingSaveDialog = false
    @State private var saveName = ""
    @State private var results: [AO3WorkSummary] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var phase: Phase = .idle
    @State private var path = NavigationPath()
    /// Drives the toolbar "expand/collapse all" toggle for the result cards.
    @State private var expandAllCards = false
    /// Bumped on every search load and when backing out to Browse; a load whose
    /// token is stale (superseded by a newer search, or by returning to Browse
    /// before it finished) discards its result instead of re-showing results.
    @State private var loadToken = 0
    /// One entry per tag-tap drill-down (tag A → tag B → …), so Back can restore the
    /// previous filter level instead of losing it to applyTagSearch's overwrite.
    /// Manual typed searches don't push here — only the tag-tap chain does.
    @State private var filterHistory: [FilterHistoryEntry] = []
    /// The debounced on-device match snapshot the local results list renders from.
    /// Computed once per settled query by `refreshLocalMatches()` — previously five
    /// computed properties re-scanned the library and the whole cached AO3 fandom
    /// catalog twice per keystroke render, which is what made typing hang.
    @State private var localMatches = LocalMatches()

    /// On-device matches for the current query — works (via `WorkSearchIndex`),
    /// library fandoms, cached AO3 fandoms, user tags, and collections. Arrays are
    /// already capped to what the list shows.
    private struct LocalMatches {
        var works: [SavedWork] = []
        var libraryFandoms: [String] = []
        var ao3Fandoms: [AO3Fandom] = []
        var tags: [Tag] = []
        var collections: [WorkCollection] = []
    }

    /// Everything the debounced local-match compute depends on. A change to any
    /// field restarts the `.task(id:)`: the query as the user types; record counts
    /// so an addition/deletion refreshes a visible result list (and a deleted
    /// model drops out of the snapshot); and the catalog revision so AO3 fandom
    /// matches appear once the disk cache finishes loading mid-typing.
    private struct LocalMatchKey: Equatable {
        let query: String
        let workCount: Int
        let tagCount: Int
        let collectionCount: Int
        let catalogRevision: Int
    }

    private var localMatchKey: LocalMatchKey {
        LocalMatchKey(
            query: localQuery,
            workCount: savedWorks.count,
            tagCount: allTags.count,
            collectionCount: collections.count,
            catalogRevision: FandomCatalog.shared.revision
        )
    }

    private struct FilterHistoryEntry {
        let filters: AO3SearchFilters
        let page: Int
        /// The results (and paging) that were on screen at this level, captured when
        /// we drilled deeper. Restored verbatim on Back so returning to a level never
        /// re-hits AO3 — a re-fetch would occasionally come back empty or rate-limited
        /// and strand the user on a blank "no results" page for a level that had works.
        let results: [AO3WorkSummary]
        let totalPages: Int
    }

    // Multi-select / bulk actions over AO3 search results — the same shared
    // selection shell as Browse's FandomWorksView/TagWorksView.
    @State private var bulkSelection = RemoteWorkSelectionController()

    private enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .task { await FandomCatalog.shared.warmCache() }
                .task(id: localMatchKey) { await refreshLocalMatches() }
                // A tapped tag chip elsewhere (work detail / search results) routes here to
                // run an AO3 search for that tag. `initial` catches a request that arrived
                // before this view existed (first visit to Search).
                .onChange(of: router.pendingTagSearch, initial: true) { _, request in
                    guard let request else { return }
                    applyTagSearch(request)
                    router.pendingTagSearch = nil
                    // A new tag search always replaces the visible results at Search's
                    // root — collapse any pushed work/author screen so the request
                    // (from a chip tapped on a work already pushed inside Search's own
                    // stack, or from another tab entirely) is never silently applied
                    // behind a still-visible, unrelated screen.
                    path = NavigationPath()
                }
                .navigationTitle("Search")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .navigationDestination(for: AO3WorkSummary.self) { work in
                    WorkDetailView(remote: work)
                }
                .navigationDestination(for: SavedWork.self) { work in
                    WorkDetailView(work: work)
                }
                .navigationDestination(for: LocalWorkDestination.self) { destination in
                    LocalWorkDestinationView(destination: destination)
                }
                .navigationDestination(for: WorkCollection.self) { collection in
                    CollectionDetailView(collection: collection)
                }
                .ao3AuthorNavigation(path: $path, tab: .search)
                .toolbar {
                    if bulkSelection.isSelecting {
                        RemoteWorkSelectionToolbar(controller: bulkSelection) {
                            bulkSelection.selected(in: results)
                        }
                    } else {
                        #if os(iOS)
                        // Search is a focused, full-screen mode. Results replace the
                        // Browse-by-fandom view in place (no navigation push), so Back steps
                        // back through that: results → Browse, then Browse → previous tab —
                        // landing on the page the user actually came from, not skipping it.
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: goBack) {
                                Image(systemName: "chevron.backward")
                            }
                            .accessibilityLabel("Back")
                        }
                        #endif
                        ToolbarItem(placement: .principal) { searchField }
                        // Filter sits directly visible, right after the search field —
                        // everything else (Select, Expand/Collapse) lives behind "...".
                        ActionToolbar {
                            FilterButton(filtersActive: filters.hasActiveFilters,
                                         showingFilters: router.isShowing(.searchFilters),
                                         onClearFilters: clearAllFilters)
                            if phase == .loaded, !results.isEmpty {
                                WorkListMoreMenu {
                                    Button { bulkSelection.isSelecting = true } label: {
                                        Label("Select", systemImage: "checklist")
                                    }
                                    ExpandAllMenuItem(expandAll: $expandAllCards)
                                }
                            }
                        }
                    }
                }
            #if os(iOS)
                .toolbar(.hidden, for: .tabBar)
                // Focused Search has a custom Back button (results → Browse → previous
                // tab, not a navigation pop), so mirror it with a left-edge swipe.
                // Only at the root — pushed detail pages use the normal swipe-to-pop.
                .edgeSwipeToGoBack(isActive: path.isEmpty) { goBack() }
            #endif
                .inspector(isPresented: router.isShowing(.searchFilters)) {
                    filterPanel
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                    // On iPhone the inspector collapses into a bottom sheet; show the
                    // standard grabber so it reads as swipe-to-dismiss.
                    #if os(iOS)
                        .presentationDragIndicator(.visible)
                    #endif
                }
                .alert("Save Search", isPresented: $showingSaveDialog) {
                    TextField("Name", text: $saveName)
                    Button("Save") { commitSavedSearch() }
                        .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel", role: .cancel) { saveName = "" }
                } message: {
                    Text("Save the current search and its filters to re-run later.")
                }
                .remoteWorkSelectionChrome(bulkSelection)
        }
    }

    /// Local-first Global Search: with no query, the Media Browser fills the idle
    /// state; as the user types, on-device matches (works, fandoms, tags,
    /// collections) appear live plus an explicit "Search AO3" action; once an AO3
    /// search runs, the results list (with its loading / empty / error overlay)
    /// takes over.
    @ViewBuilder
    private var content: some View {
        if phase == .idle {
            if localQuery.isEmpty {
                idleScreen
            } else {
                localResultsList
            }
        } else if phase == .loading, results.isEmpty {
            // First load of an AO3 search: show the shape of the incoming results.
            AO3WorkRowSkeletonList(count: 7)
        } else {
            ScrollViewReader { proxy in
                List {
                    if showPagination {
                        Section { paginationRow.id(paginationTopID) }
                    }

                    Section {
                        ForEach(results) { work in
                            SelectableAO3WorkRow(work: work, expandAll: expandAllCards, controller: bulkSelection)
                                .cardRow(isSelected: bulkSelection.isSelecting && bulkSelection.selection.contains(work.id))
                        }
                    }

                    if showPagination {
                        Section { paginationRow }
                    }
                }
                // Card-based list: each result is a fully-rounded card with ~12pt
                // spacing, over the themed backdrop (replaces the grouped style).
                .cardList()
                .refreshable { await refreshCurrentResults() }
                .overlay { statusOverlay }
                .onChange(of: currentPage) { _, _ in
                    withAnimation {
                        proxy.scrollTo(paginationTopID, anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: Local-first results

    /// The empty-query idle state: the user's Saved Searches when they have any,
    /// otherwise the plain prompt. Fandom/category exploration lives in Browse.
    @ViewBuilder
    private var idleScreen: some View {
        if savedSearches.isEmpty {
            searchPrompt
        } else {
            List {
                Section {
                    ForEach(savedSearches) { saved in
                        Button { runSaved(saved) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.name).foregroundStyle(.primary)
                                if let subtitle = savedSearchSubtitle(saved.filters) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteSavedSearches)
                    .cardRow()
                } header: {
                    Text("Saved Searches")
                } footer: {
                    Text("Search your library or AO3 above. Browse fandoms in the Browse tab.")
                }
            }
            .cardList()
        }
    }

    /// Shown when nothing's typed yet and there are no saved searches.
    private var searchPrompt: some View {
        ContentUnavailableView {
            Label("Search Kudos", systemImage: "magnifyingglass")
        } description: {
            Text("Find works in your library, or search AO3 by title, author, or tag. "
                + "Browse fandoms and categories in the Browse tab.")
        }
    }

    /// A one-line description of a saved search's filters (the query, then the most
    /// salient facets) so the row is recognizable beyond its name.
    private func savedSearchSubtitle(_ savedFilters: AO3SearchFilters) -> String? {
        var parts: [String] = []
        let query = savedFilters.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { parts.append("“\(query)”") }
        let fandom = savedFilters.fandom.trimmingCharacters(in: .whitespaces)
        if !fandom.isEmpty { parts.append(fandom) }
        if savedFilters.rating != .any { parts.append(savedFilters.rating.title) }
        if savedFilters.completion != .any { parts.append(savedFilters.completion.title) }
        if savedFilters.sort != .relevance { parts.append(savedFilters.sort.title) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var localQuery: String {
        filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Debounced local-match refresh: coalesces a burst of keystrokes so the match
    /// scan (library index + fandom catalog) runs once per pause, not once per
    /// letter. An emptied query clears instantly — the idle screen must not lag.
    private func refreshLocalMatches() async {
        if localQuery.isEmpty {
            localMatches = LocalMatches()
            return
        }
        // Sleep throws when a newer keystroke restarts the task — just stop.
        guard (try? await Task.sleep(for: .milliseconds(150))) != nil else { return }
        localMatches = computeLocalMatches()
    }

    /// One pass over the local sources for the current query, every list stopping
    /// at its display cap. Work matching runs on the precomputed
    /// `WorkSearchIndex` text — case- and diacritic-insensitive over title,
    /// author, series, user tags, AO3 tags, rating, language, and summary — with
    /// AND-across-terms, so multi-word queries can span fields; results keep the
    /// library query's newest-first order. Fandom/tag/collection name matching
    /// shares the same normalization.
    private func computeLocalMatches() -> LocalMatches {
        var matches = LocalMatches()
        let query = localQuery
        guard !query.isEmpty else { return matches }
        let terms = WorkSearchIndex.terms(from: query)
        let normalizedQuery = WorkSearchIndex.normalize(query)

        matches.works = Array(
            savedWorks.lazy.filter { WorkSearchIndex.matches($0, terms: terms) }.prefix(20)
        )

        var seenFandoms = Set<String>()
        outer: for work in savedWorks {
            for fandom in work.workFandoms {
                let key = WorkSearchIndex.normalize(fandom)
                guard key.contains(normalizedQuery), seenFandoms.insert(key).inserted else { continue }
                matches.libraryFandoms.append(fandom)
                if matches.libraryFandoms.count >= 12 { break outer }
            }
        }

        // Cached AO3 fandoms (from the on-disk catalog), minus any already shown
        // under the user's own library fandoms. Instant, no scraping; tapping one
        // runs the real AO3 search, which corrects any stale cached counts.
        matches.ao3Fandoms = FandomCatalog.shared.cachedFandoms(matching: query)
            .filter { !seenFandoms.contains(WorkSearchIndex.normalize($0.name)) }

        matches.tags = Array(
            allTags.lazy.filter { WorkSearchIndex.normalize($0.name).contains(normalizedQuery) }.prefix(12)
        )
        matches.collections = Array(
            collections.lazy.filter { WorkSearchIndex.normalize($0.name).contains(normalizedQuery) }.prefix(12)
        )
        return matches
    }

    /// On-device matches shown live as the user types (from the debounced
    /// `localMatches` snapshot), plus an explicit AO3 search action (no AO3
    /// request fires until the user taps it or submits).
    private var localResultsList: some View {
        // A deletion re-keys the compute task via the record counts, but a render
        // can land in the gap before the debounce fires — drop invalidated models
        // rather than touching them (SwiftData asserts on invalidated access).
        let works = localMatches.works.filter { $0.modelContext != nil }
        let tags = localMatches.tags.filter { $0.modelContext != nil }
        let matchedCollections = localMatches.collections.filter { $0.modelContext != nil }
        return List {
            Section {
                Button(action: runSearch) {
                    Label("Search AO3 for “\(localQuery)”", systemImage: "magnifyingglass")
                }
            } header: {
                Text("Archive of Our Own")
            }

            if !works.isEmpty {
                Section("In Your Library") {
                    ForEach(works) { work in
                        WorkRow(work: work).cardNavigation(to: work)
                    }
                    .cardRow()
                }
            }
            if !localMatches.libraryFandoms.isEmpty {
                Section("Fandoms in Your Library") {
                    ForEach(localMatches.libraryFandoms, id: \.self) { fandom in
                        Button { router.filterLibrary(.fandom, fandom) } label: {
                            Label(fandom, systemImage: "books.vertical")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !localMatches.ao3Fandoms.isEmpty {
                Section("Fandoms on AO3") {
                    ForEach(localMatches.ao3Fandoms, id: \.id) { fandom in
                        Button {
                            setIncludedFandom(fandom.name)
                            runSearch()
                        } label: {
                            HStack {
                                Label(fandom.name, systemImage: "books.vertical")
                                Spacer()
                                if let count = fandom.workCount {
                                    Text(count.formatted(.number.notation(.compactName)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !tags.isEmpty {
                Section("Your Tags") {
                    ForEach(tags) { tag in
                        Button { router.filterLibrary(.userTag, tag.name) } label: {
                            Label(tag.name, systemImage: "tag")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !matchedCollections.isEmpty {
                Section("Collections") {
                    ForEach(matchedCollections) { collection in
                        NavigationLink(value: collection) {
                            Label(collection.name, systemImage: "square.stack")
                        }
                    }
                }
            }
        }
        .cardList()
    }

    private var showPagination: Bool {
        totalPages > 1 && !results.isEmpty
    }

    private let paginationTopID = "pagination-top"

    private var paginationRow: some View {
        SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
            loadPage(page)
        }
        .cardRow()
    }

    // MARK: Search bar + filter button

    private var searchField: some View {
        GlassFieldBar(text: $filters.query, placeholder: "Search your library and AO3", onSubmit: runSearch) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
        } trailing: {
            if !filters.query.isEmpty {
                Button(action: clearQuery) {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Clears the query, falling back to the Media Browser if nothing's left to search.
    private func clearQuery() {
        filters.query = ""
        if !filters.hasActiveFilters {
            filterHistory.removeAll()
            results = []
            phase = .idle
        }
    }

    /// Resets every filter (keeping the query) and refreshes — shared by the
    /// long-press confirmation and mirroring the sidebar's "Reset Filters".
    private func clearAllFilters() {
        filterHistory.removeAll()
        filters = AO3SearchFilters(query: filters.query)
        if filters.isSearchable {
            runSearch()
        } else {
            results = []
            phase = .idle
            router.panel = .none
        }
    }

    // MARK: Results states

    @ViewBuilder
    private var statusOverlay: some View {
        // First-load (loading + empty) is handled upstream by the skeleton list, so it
        // never reaches this overlay; only the empty/failed result states do.
        switch phase {
        case .loaded where results.isEmpty:
            ContentUnavailableView.search(text: filters.query)
        case let .failed(message):
            ContentUnavailableView {
                Label("Search failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: runSearch)
            }
        default:
            EmptyView()
        }
    }

    // MARK: Filter sidebar

    private var filterPanel: some View {
        AO3FilterPanel(
            filters: $filters,
            canReset: filters.hasActiveFilters,
            onApply: runSearch,
            onSave: presentSaveDialog,
            onReset: {
                filterHistory.removeAll()
                filters = AO3SearchFilters(query: filters.query)
                // Nothing left to search → return to the Media Browser.
                if !filters.isSearchable {
                    results = []
                    phase = .idle
                    router.panel = .none
                }
            }
        )
    }

    // MARK: Navigation

    /// Back action for the focused Search tab. A tag-tap drill-down (tag A → tag B)
    /// pops one filter level at a time before falling through to the real history:
    /// results → Browse, then (already on Browse) → the previous tab.
    private func goBack() {
        if let previous = filterHistory.popLast() {
            // Restore the level's captured results instead of re-fetching — the
            // bump discards any load still in flight from the level we're leaving so
            // it can't overwrite what we just restored. Selection is cleared because
            // the works (and their IDs) change wholesale, mirroring loadPage.
            loadToken += 1
            bulkSelection.selection.removeAll()
            filters = previous.filters
            results = previous.results
            currentPage = previous.page
            totalPages = previous.totalPages
            phase = .loaded
        } else if phase == .idle {
            router.exitSearch()
        } else {
            returnToBrowse()
        }
    }

    /// Restores the Browse-by-fandom idle state, clearing the search the results
    /// came from (a typed query or a tapped fandom chip) so Browse shows fresh.
    private func returnToBrowse() {
        loadToken += 1 // discard any in-flight load so it can't re-show results
        filterHistory.removeAll()
        filters = AO3SearchFilters()
        results = []
        currentPage = 1
        totalPages = 1
        expandAllCards = false
        phase = .idle
    }

    // MARK: Searching

    private func setIncludedFandom(_ name: String) {
        filters.fandom = name
        filters.excludedFandoms = filters.excludedFandoms.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.caseInsensitiveCompare(name) != .orderedSame }
            .joined(separator: ", ")
    }

    private func runSearch() {
        guard filters.isSearchable else { return }
        phase = .loading
        results = []
        currentPage = 1
        totalPages = 1
        load(page: 1)
    }

    /// Runs a fresh AO3 search for a single tag (from a tapped chip), placing it in the
    /// matching filter field so AO3 returns works with that tag.
    private func applyTagSearch(_ request: AO3TagSearch) {
        var newFilters = AO3SearchFilters()
        switch request.field {
        case .fandom: newFilters.fandom = request.value
        case .character: newFilters.characters = request.value
        case .relationship: newFilters.relationships = request.value
        case .freeform: newFilters.additionalTags = request.value
        case .warning:
            // Map the warning's display text to AO3's structured warning filter.
            if let warning = AO3SearchFilters.Warning.allCases.first(where: { $0.title == request.value }) {
                newFilters.warnings = [warning]
            } else {
                newFilters.additionalTags = request.value
            }
        }
        pushFilters(newFilters, isFreshTabJump: request.isFreshTabJump)
    }

    /// Pushes the current filters onto the history stack before overwriting them —
    /// the "overwrite" → "push" change that makes each tag-tap drill-down reversible
    /// one step at a time via `goBack()`. Skipped when the current filters aren't
    /// searchable (the very first tag tap into a fresh Search, e.g. from Browse) —
    /// there's no real prior search to return to, and pushing that empty state
    /// anyway just forced an extra Back tap through a blank results screen before
    /// `goBack()`'s own idle/Browse fallback ever got a chance to run.
    ///
    /// `isFreshTabJump` marks a request that switched the user into Search from a
    /// different tab: whatever filters/history Search still had from an earlier,
    /// unrelated session must not be kept — otherwise the first `goBack()` after this
    /// new search restores that stale, unrelated prior search instead of returning to
    /// wherever the user actually came from.
    private func pushFilters(_ new: AO3SearchFilters, isFreshTabJump: Bool) {
        if isFreshTabJump {
            filterHistory.removeAll()
        } else if filters.isSearchable {
            filterHistory.append(FilterHistoryEntry(
                filters: filters,
                page: currentPage,
                results: results,
                totalPages: totalPages
            ))
        }
        filters = new
        runSearch()
    }

    // MARK: Saved searches

    /// Opens the name-entry alert for saving the current filter set, seeding a sensible
    /// default name. Invoked from the filter panel's "Save Search…" action.
    private func presentSaveDialog() {
        saveName = defaultSavedSearchName
        showingSaveDialog = true
    }

    /// A default name for the current search: its query, else its fandom, else a label.
    private var defaultSavedSearchName: String {
        let query = filters.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { return query }
        let fandom = filters.fandom.trimmingCharacters(in: .whitespaces)
        if !fandom.isEmpty {
            return fandom
                .split(separator: ",")
                .first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? fandom
        }
        return "Saved Search"
    }

    /// Persists the current filter set under the entered name.
    private func commitSavedSearch() {
        let name = saveName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, filters.isSearchable else { return }
        context.insert(SavedSearch(name: name, filters: filters))
        try? context.save()
        saveName = ""
    }

    /// Loads a saved search's filters and runs it.
    private func runSaved(_ saved: SavedSearch) {
        filterHistory.removeAll()
        filters = saved.filters
        router.panel = .none
        runSearch()
    }

    private func deleteSavedSearches(at offsets: IndexSet) {
        for index in offsets {
            context.delete(savedSearches[index])
        }
        try? context.save()
    }

    /// Navigates to a specific page, replacing the visible results (AO3-style
    /// paging rather than infinite scroll). Keeps the old page on screen while
    /// the new one loads so the pagination bar doesn't flicker away.
    private func loadPage(_ page: Int) {
        guard page >= 1, page <= totalPages, page != currentPage else { return }
        // A different page replaces `results` with different works entirely — a
        // stale selection would otherwise reference IDs that no longer exist.
        bulkSelection.selection.removeAll()
        load(page: page)
    }

    private func load(page: Int) {
        loadToken += 1
        let token = loadToken
        let current = filters
        Task {
            do {
                let result = try await AO3Client.shared.search(filters: current, page: page)
                // Backed out to Browse (or a newer search started) while this was in
                // flight — drop the result so it can't yank the user back to results.
                guard token == loadToken else { return }
                results = result.works
                currentPage = result.currentPage
                totalPages = result.totalPages
                phase = .loaded
            } catch let error as AO3Error {
                guard token == loadToken else { return }
                phase = .failed(error.errorDescription ?? "Something went wrong.")
            } catch {
                guard token == loadToken else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func refreshCurrentResults() async {
        guard filters.isSearchable, phase != .idle else { return }
        loadToken += 1
        let token = loadToken
        let current = filters
        let page = currentPage
        if results.isEmpty { phase = .loading }
        do {
            let result = try await AO3Client.shared.search(filters: current, page: page)
            guard token == loadToken else { return }
            results = result.works
            currentPage = result.currentPage
            totalPages = result.totalPages
            phase = .loaded
        } catch let error as AO3Error {
            guard token == loadToken else { return }
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            guard token == loadToken else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
