import SwiftUI
import SwiftData

/// Native AO3 work search. A search field with an adjacent filter button, results
/// paged like AO3 (numbered pages + first/prev/next/last), and a filter sidebar
/// for fandom, rating, sort, and completion.
struct SearchView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    // Local-first search sources (Global Search, Phase 2): matched on-device, live.
    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var savedWorks: [SavedWork]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query(sort: \WorkCollection.dateAdded, order: .reverse) private var collections: [WorkCollection]
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

    private enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
            .task { await FandomCatalog.shared.warmCache() }
            // A tapped tag chip elsewhere (work detail / search results) routes here to
            // run an AO3 search for that tag. `initial` catches a request that arrived
            // before this view existed (first visit to Search).
            .onChange(of: router.pendingTagSearch, initial: true) { _, request in
                guard let request else { return }
                applyTagSearch(request)
                router.pendingTagSearch = nil
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
            .toolbar {
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
                if phase == .loaded && !results.isEmpty {
                    ToolbarItem(placement: .primaryAction) { expandAllButton }
                }
                ToolbarItem(placement: .primaryAction) { filterButton }
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
        } else if phase == .loading && results.isEmpty {
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
                            AO3WorkRow(work: work, expandAll: expandAllCards)
                                .cardNavigation(to: work)
                        }
                        .cardRow()
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
    private func savedSearchSubtitle(_ f: AO3SearchFilters) -> String? {
        var parts: [String] = []
        let q = f.query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { parts.append("“\(q)”") }
        let fandom = f.fandom.trimmingCharacters(in: .whitespaces)
        if !fandom.isEmpty { parts.append(fandom) }
        if f.rating != .any { parts.append(f.rating.title) }
        if f.completion != .any { parts.append(f.completion.title) }
        if f.sort != .relevance { parts.append(f.sort.title) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var localQuery: String { filters.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matchingWorks: [SavedWork] {
        let q = localQuery.lowercased()
        return savedWorks.filter {
            $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q)
        }
    }

    private var matchingFandoms: [String] {
        let q = localQuery.lowercased()
        var seen = Set<String>()
        var out: [String] = []
        for work in savedWorks {
            for fandom in work.workFandoms where fandom.lowercased().contains(q) {
                if seen.insert(fandom.lowercased()).inserted { out.append(fandom) }
            }
        }
        return out
    }

    private var matchingTags: [Tag] {
        allTags.filter { $0.name.lowercased().contains(localQuery.lowercased()) }
    }

    private var matchingCollections: [WorkCollection] {
        collections.filter { $0.name.lowercased().contains(localQuery.lowercased()) }
    }

    /// Cached AO3 fandoms matching the query (from the on-disk fandom catalog), minus
    /// any already shown under the user's own library fandoms. Instant, no scraping;
    /// tapping one runs the real AO3 search, which corrects any stale cached counts.
    private var cachedAO3Fandoms: [AO3Fandom] {
        let inLibrary = Set(matchingFandoms.map { $0.lowercased() })
        return FandomCatalog.shared.cachedFandoms(matching: localQuery)
            .filter { !inLibrary.contains($0.name.lowercased()) }
    }

    /// On-device matches shown live as the user types, plus an explicit AO3 search
    /// action (no AO3 request fires until the user taps it or submits).
    private var localResultsList: some View {
        List {
            Section {
                Button(action: runSearch) {
                    Label("Search AO3 for “\(localQuery)”", systemImage: "magnifyingglass")
                }
            } header: {
                Text("Archive of Our Own")
            }

            if !matchingWorks.isEmpty {
                Section("In Your Library") {
                    ForEach(matchingWorks.prefix(20)) { work in
                        WorkRow(work: work).cardNavigation(to: work)
                    }
                    .cardRow()
                }
            }
            if !matchingFandoms.isEmpty {
                Section("Fandoms in Your Library") {
                    ForEach(matchingFandoms.prefix(12), id: \.self) { fandom in
                        Button { router.filterLibrary(.fandom, fandom) } label: {
                            Label(fandom, systemImage: "books.vertical")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !cachedAO3Fandoms.isEmpty {
                Section("Fandoms on AO3") {
                    ForEach(cachedAO3Fandoms, id: \.id) { fandom in
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
            if !matchingTags.isEmpty {
                Section("Your Tags") {
                    ForEach(matchingTags.prefix(12)) { tag in
                        Button { router.filterLibrary(.userTag, tag.name) } label: {
                            Label(tag.name, systemImage: "tag")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !matchingCollections.isEmpty {
                Section("Collections") {
                    ForEach(matchingCollections.prefix(12)) { collection in
                        NavigationLink(value: collection) {
                            Label(collection.name, systemImage: "square.stack")
                        }
                    }
                }
            }
        }
        .cardList()
    }

    private var showPagination: Bool { totalPages > 1 && !results.isEmpty }

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
            results = []
            phase = .idle
        }
    }

    /// Expands or collapses every result card at once (each card can still be
    /// toggled individually afterwards). Shown only while results are visible.
    private var expandAllButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expandAllCards.toggle() }
        } label: {
            Image(systemName: expandAllCards
                ? "rectangle.compress.vertical"
                : "rectangle.expand.vertical")
        }
        .help(expandAllCards ? "Collapse all cards" : "Expand all cards")
        .accessibilityLabel(expandAllCards ? "Collapse all cards" : "Expand all cards")
    }

    private var filterButton: some View {
        Button {
            router.toggle(.searchFilters)
        } label: {
            Image(systemName: filters.hasActiveFilters
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .help("Filters")
        // Long-press the Filters button to quickly clear every active filter
        // without opening the sidebar. A context menu is the reliable long-press
        // affordance for toolbar buttons; the destructive item confirms the action.
        .contextMenu {
            if filters.hasActiveFilters {
                Button(role: .destructive, action: clearAllFilters) {
                    Label("Clear All Filters", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    /// Resets every filter (keeping the query) and refreshes — shared by the
    /// long-press confirmation and mirroring the sidebar's "Reset Filters".
    private func clearAllFilters() {
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
        case .failed(let message):
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

    /// Back action for the focused Search tab. Because search results replace the
    /// Browse-by-fandom view in place rather than pushing a page, a plain "leave the
    /// tab" Back would skip past Browse. So step back through the real history:
    /// results → Browse, then (already on Browse) → the previous tab.
    private func goBack() {
        if phase == .idle {
            router.exitSearch()
        } else {
            returnToBrowse()
        }
    }

    /// Restores the Browse-by-fandom idle state, clearing the search the results
    /// came from (a typed query or a tapped fandom chip) so Browse shows fresh.
    private func returnToBrowse() {
        loadToken += 1   // discard any in-flight load so it can't re-show results
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
        filters = newFilters
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
        let q = filters.query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return q }
        let fandom = filters.fandom.trimmingCharacters(in: .whitespaces)
        if !fandom.isEmpty {
            return fandom.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? fandom
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
        filters = saved.filters
        router.panel = .none
        runSearch()
    }

    private func deleteSavedSearches(at offsets: IndexSet) {
        for index in offsets { context.delete(savedSearches[index]) }
        try? context.save()
    }

    /// Navigates to a specific page, replacing the visible results (AO3-style
    /// paging rather than infinite scroll). Keeps the old page on screen while
    /// the new one loads so the pagination bar doesn't flicker away.
    private func loadPage(_ page: Int) {
        guard page >= 1, page <= totalPages, page != currentPage else { return }
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
