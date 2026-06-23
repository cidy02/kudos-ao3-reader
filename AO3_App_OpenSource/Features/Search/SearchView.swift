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

    @State private var filters = AO3SearchFilters()
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
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: AO3WorkSummary.self) { work in
                AO3WorkDetailView(work: work, path: $path)
            }
            .navigationDestination(for: SavedWork.self) { work in
                WorkDetailView(work: work)
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
                searchPrompt
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
                            NavigationLink(value: work) {
                                AO3WorkRow(work: work, expandAll: expandAllCards)
                            }
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

    /// Shown when nothing's typed yet. Fandom/category exploration lives in Browse.
    private var searchPrompt: some View {
        ContentUnavailableView {
            Label("Search Kudos", systemImage: "magnifyingglass")
        } description: {
            Text("Find works in your library, or search AO3 by title, author, or tag. "
                 + "Browse fandoms and categories in the Browse tab.")
        }
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
                        NavigationLink(value: work) { WorkRow(work: work) }
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
        Form {
          // Group so .appThemedRows() reaches every section's rows (it doesn't
          // propagate from the Form container, only from a Group/Section/ForEach).
          Group {
            Section {
                Picker("Sort by", selection: $filters.sort) {
                    ForEach(AO3SearchFilters.Sort.allCases) { Text($0.title).tag($0) }
                }
                Picker("Rating", selection: $filters.rating) {
                    ForEach(AO3SearchFilters.Rating.searchCases) { Text($0.title).tag($0) }
                }
                .onChange(of: filters.rating) { oldValue, newValue in
                    if oldValue == .any, newValue != .any {
                        // A specific rating starts exact and excludes unrated works;
                        // the separate toggle lets the reader opt them back in.
                        filters.ratingMatch = .exact
                        filters.includeNotRated = false
                    } else if newValue == .any {
                        filters.ratingMatch = .exact
                    }
                }
                if filters.rating != .any {
                    Picker("Match", selection: $filters.ratingMatch) {
                        ForEach(AO3SearchFilters.RatingMatch.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                }
                Toggle("Include Not Rated", isOn: $filters.includeNotRated)
            }

            Section("Warnings") {
                ForEach(AO3SearchFilters.Warning.allCases) { warning in
                    cyclingFacetRow(warning.title, state: warningState(warning)) {
                        cycle(warning)
                    }
                }
            }

            Section("Categories") {
                ForEach(AO3SearchFilters.Category.allCases) { category in
                    cyclingFacetRow(category.title, state: categoryState(category)) {
                        cycle(category)
                    }
                }
            }

            Section {
                Picker("Crossovers", selection: $filters.crossover) {
                    ForEach(AO3SearchFilters.Crossover.allCases) { Text($0.title).tag($0) }
                }
                Picker("Completion", selection: $filters.completion) {
                    ForEach(AO3SearchFilters.Completion.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Word count") {
                TextField("From", text: $filters.wordsFrom)
                    #if !os(macOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("To", text: $filters.wordsTo)
                    #if !os(macOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            Section {
                Picker("Updated", selection: $filters.updated) {
                    ForEach(AO3SearchFilters.Updated.allCases) { Text($0.title).tag($0) }
                }
                Picker("Language", selection: $filters.language) {
                    ForEach(AO3SearchFilters.Language.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                TagSelectField(title: "Fandoms", kind: .fandom,
                               included: $filters.fandom, excluded: $filters.excludedFandoms)
                TagSelectField(title: "Characters", kind: .character,
                               included: $filters.characters, excluded: $filters.excludedCharacters,
                               fandomContext: selectedFandoms)
                TagSelectField(title: "Relationships", kind: .relationship,
                               included: $filters.relationships, excluded: $filters.excludedRelationships,
                               fandomContext: selectedFandoms)
                TagSelectField(title: "Additional Tags", kind: .freeform,
                               included: $filters.additionalTags, excluded: $filters.excludedAdditionalTags,
                               fandomContext: selectedFandoms)
            } header: {
                Text("Tags")
            } footer: {
                Text("Tap a tag once to include it, twice to exclude it, and a third time to clear it.")
            }

            Section {
                Button {
                    runSearch()
                } label: {
                    Label("Apply Filters", systemImage: "magnifyingglass")
                }
                .disabled(!filters.isSearchable)

                if filters.hasActiveFilters {
                    Button(role: .destructive) {
                        filters = AO3SearchFilters(query: filters.query)
                        // Nothing left to search → return to the Media Browser.
                        if !filters.isSearchable {
                            results = []
                            phase = .idle
                            router.panel = .none
                        }
                    } label: {
                        Label("Reset Filters", systemImage: "arrow.counterclockwise")
                    }
                }
            }
          }
          .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
    }

    /// The fandoms currently chosen in the filters, used to seed the other tag
    /// pickers with that fandom's popular tags.
    private var selectedFandoms: [String] {
        filters.fandom.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A tappable multi-select facet row matching the tag pickers' three states.
    private func cyclingFacetRow(_ title: String, state: FilterSelectionState,
                                 toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                switch state {
                case .clear:
                    EmptyView()
                case .included:
                    Label("Include", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                case .excluded:
                    Label("Exclude", systemImage: "minus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func warningState(_ warning: AO3SearchFilters.Warning) -> FilterSelectionState {
        if filters.warnings.contains(warning) { return .included }
        if filters.excludedWarnings.contains(warning) { return .excluded }
        return .clear
    }

    private func cycle(_ warning: AO3SearchFilters.Warning) {
        switch warningState(warning).next {
        case .included:
            filters.warnings.insert(warning)
            filters.excludedWarnings.remove(warning)
        case .excluded:
            filters.warnings.remove(warning)
            filters.excludedWarnings.insert(warning)
        case .clear:
            filters.warnings.remove(warning)
            filters.excludedWarnings.remove(warning)
        }
    }

    private func categoryState(_ category: AO3SearchFilters.Category) -> FilterSelectionState {
        if filters.categories.contains(category) { return .included }
        if filters.excludedCategories.contains(category) { return .excluded }
        return .clear
    }

    private func cycle(_ category: AO3SearchFilters.Category) {
        switch categoryState(category).next {
        case .included:
            filters.categories.insert(category)
            filters.excludedCategories.remove(category)
        case .excluded:
            filters.categories.remove(category)
            filters.excludedCategories.insert(category)
        case .clear:
            filters.categories.remove(category)
            filters.excludedCategories.remove(category)
        }
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
}
