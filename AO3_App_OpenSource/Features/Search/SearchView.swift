import SwiftUI
import SwiftData

/// Native AO3 work search. A search field with an adjacent filter button, results
/// paged like AO3 (numbered pages + first/prev/next/last), and a filter sidebar
/// for fandom, rating, sort, and completion.
struct SearchView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    @State private var filters = AO3SearchFilters()
    @State private var results: [AO3WorkSummary] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var phase: Phase = .idle
    @State private var path = NavigationPath()

    private enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: AO3WorkSummary.self) { work in
                AO3WorkDetailView(work: work, path: $path)
            }
            .navigationDestination(for: SavedWork.self) { work in
                ReaderView(work: work)
            }
            .navigationDestination(for: AO3MediaCategory.self) { category in
                FandomListView(category: category, onSelect: searchFandomFromBrowse)
            }
            .toolbar {
                #if os(iOS)
                // Search is a focused, full-screen mode: a Back button leaves it and
                // returns to the previous tab (the tab bar is hidden below).
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: router.exitSearch) {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                }
                #endif
                ToolbarItem(placement: .principal) { searchField }
                ToolbarItem(placement: .primaryAction) { filterButton }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .tabBar)
            // Focused Search has a custom Back button (it leaves to the previous
            // tab, not a navigation pop), so mirror it with a left-edge swipe.
            // Only at the root — pushed detail pages use the normal swipe-to-pop.
            .edgeSwipeToGoBack(isActive: path.isEmpty) { router.exitSearch() }
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

    /// The Media Browser fills the idle state; once a search runs, the results list
    /// (with its loading / empty / error overlay) takes over.
    @ViewBuilder
    private var content: some View {
        if phase == .idle {
            MediaBrowserView(onSelectFandom: selectFandom)
        } else {
            ScrollViewReader { proxy in
                List {
                    if showPagination {
                        Section { paginationRow.id(paginationTopID) }
                    }

                    Section {
                        ForEach(results) { work in
                            NavigationLink(value: work) { AO3WorkRow(work: work) }
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

    private var showPagination: Bool { totalPages > 1 && !results.isEmpty }

    private let paginationTopID = "pagination-top"

    private var paginationRow: some View {
        SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
            loadPage(page)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .listRowBackground(Color.clear)
    }

    // MARK: Search bar + filter button

    private var searchField: some View {
        GlassFieldBar(text: $filters.query, placeholder: "Search AO3 works", onSubmit: runSearch) {
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
        switch phase {
        case .loading where results.isEmpty:
            ProgressView("Searching…")
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
                    ForEach(AO3SearchFilters.Rating.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Warnings") {
                ForEach(AO3SearchFilters.Warning.allCases) { warning in
                    selectableRow(warning.title, isSelected: filters.warnings.contains(warning)) {
                        warningBinding(warning).wrappedValue.toggle()
                    }
                }
            }

            Section("Categories") {
                ForEach(AO3SearchFilters.Category.allCases) { category in
                    selectableRow(category.title, isSelected: filters.categories.contains(category)) {
                        categoryBinding(category).wrappedValue.toggle()
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
                #if os(iOS)
                TagSelectField(title: "Fandoms", kind: .fandom, value: $filters.fandom)
                TagSelectField(title: "Characters", kind: .character, value: $filters.characters,
                               fandomContext: selectedFandoms)
                TagSelectField(title: "Relationships", kind: .relationship, value: $filters.relationships,
                               fandomContext: selectedFandoms)
                TagSelectField(title: "Additional Tags", kind: .freeform, value: $filters.additionalTags,
                               fandomContext: selectedFandoms)
                TagSelectField(title: "Exclude Tags", kind: .tag, value: $filters.excludeTags,
                               fandomContext: selectedFandoms)
                #else
                tagField("Fandoms", text: $filters.fandom)
                tagField("Characters", text: $filters.characters)
                tagField("Relationships", text: $filters.relationships)
                tagField("Additional tags", text: $filters.additionalTags)
                tagField("Exclude tags", text: $filters.excludeTags)
                #endif
            } header: {
                Text("Tags")
            } footer: {
                #if os(iOS)
                Text("Search AO3 and tap to select tags. Exclude Tags filters them out.")
                #else
                Text("Separate multiple tags with commas.")
                #endif
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

    #if os(iOS)
    /// The fandoms currently chosen in the filters, used to seed the other tag
    /// pickers with that fandom's popular tags.
    private var selectedFandoms: [String] {
        filters.fandom.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    #else
    private func tagField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .onSubmit(runSearch)
    }
    #endif

    /// A tappable filter row with a trailing checkmark when selected — matching the
    /// tag pickers, so Warnings/Categories use the same selection style as tags.
    private func selectableRow(_ title: String, isSelected: Bool,
                               toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func warningBinding(_ warning: AO3SearchFilters.Warning) -> Binding<Bool> {
        Binding(
            get: { filters.warnings.contains(warning) },
            set: { on in
                if on { filters.warnings.insert(warning) } else { filters.warnings.remove(warning) }
            }
        )
    }

    private func categoryBinding(_ category: AO3SearchFilters.Category) -> Binding<Bool> {
        Binding(
            get: { filters.categories.contains(category) },
            set: { on in
                if on { filters.categories.insert(category) } else { filters.categories.remove(category) }
            }
        )
    }

    // MARK: Searching

    /// Runs a search for the tapped fandom from the Media Browser (macOS inline path).
    private func selectFandom(_ name: String) {
        filters.fandom = name
        runSearch()
    }

    /// Same, but pops the pushed fandom detail page so the results become visible
    /// (the iOS Browse-by-fandom path navigates into a detail page first).
    private func searchFandomFromBrowse(_ name: String) {
        filters.fandom = name
        runSearch()
        path = NavigationPath()
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
        let current = filters
        Task {
            do {
                let result = try await AO3Client.shared.search(filters: current, page: page)
                results = result.works
                currentPage = result.currentPage
                totalPages = result.totalPages
                phase = .loaded
            } catch let error as AO3Error {
                phase = .failed(error.errorDescription ?? "Something went wrong.")
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
