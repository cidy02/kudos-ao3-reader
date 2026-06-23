import SwiftUI

/// Native AO3 discovery (Part 6): browse categories → fandoms → works, all in the
/// app's own card/list system. The AO3 website is a secondary "Open AO3 Website"
/// fallback (`AO3WebBrowserView`), not the primary experience. Architecture is kept
/// extensible (Tags / Collections / People can become sibling sections later).
struct BrowseView: View {
    @Environment(AppRouter.self) private var router

    @State private var path = NavigationPath()
    @State private var showingWebsite = false

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
                .navigationDestination(for: AO3WorkSummary.self) { work in
                    AO3WorkDetailView(work: work, path: $path)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingWebsite = true } label: {
                            Label("Open AO3 Website", systemImage: "safari")
                        }
                    }
                }
                .sheet(isPresented: $showingWebsite) { AO3WebBrowserView() }
                // Something asked to open an AO3 URL — surface the website fallback.
                .onChange(of: router.pendingURL, initial: true) { _, url in
                    if url != nil { showingWebsite = true }
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
    @State private var phase: Phase = .loading
    @State private var expandAll = false
    /// The active filters for this fandom's works — seeded to just the fandom, then
    /// refined via the same filter panel the Search tab uses.
    @State private var filters: AO3SearchFilters
    @State private var showingFilters = false

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    init(fandom: String) {
        self.fandom = fandom
        _filters = State(initialValue: Self.baseline(for: fandom))
    }

    /// Filters scoped to just this page's fandom — also the reset baseline.
    private static func baseline(for fandom: String) -> AO3SearchFilters {
        var filters = AO3SearchFilters()
        filters.fandom = fandom
        return filters
    }

    /// True once the reader has set any filter beyond the page's fixed fandom.
    private var hasExtraFilters: Bool { filters != Self.baseline(for: fandom) }

    var body: some View {
        Group {
            if phase == .loading && results.isEmpty {
                // First load of this fandom's works — show the shape of the results.
                AO3WorkRowSkeletonList(count: 6)
            } else {
                List {
                    if showPagination { Section { paginationRow } }
                    Section {
                        ForEach(results) { work in
                            NavigationLink(value: work) {
                                AO3WorkRow(work: work, expandAll: expandAll)
                            }
                        }
                        .cardRow()
                    }
                    if showPagination { Section { paginationRow } }
                }
                .cardList()
                .overlay { statusOverlay }
            }
        }
        .navigationTitle(fandom)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // One item holding a tight HStack so the icons cluster like Library's
            // (separate ToolbarItems get the system's wider spacing). Filters rightmost.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    if phase == .loaded && !results.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { expandAll.toggle() }
                        } label: {
                            Label(expandAll ? "Collapse all cards" : "Expand all cards",
                                  systemImage: expandAll
                                    ? "rectangle.compress.vertical"
                                    : "rectangle.expand.vertical")
                        }
                    }
                    Button { showingFilters = true } label: {
                        Label("Filter", systemImage: hasExtraFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                    .help("Filter works in this fandom")
                }
                .labelStyle(.iconOnly)
            }
        }
        .inspector(isPresented: $showingFilters) {
            AO3FilterPanel(
                filters: $filters,
                showFandomPicker: false,
                canReset: hasExtraFilters,
                onApply: applyFilters,
                onReset: resetFilters
            )
            .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            .navigationTitle("Filter Works")
        }
        .task { await load(page: 1) }
    }

    private var showPagination: Bool { totalPages > 1 && !results.isEmpty }

    private var paginationRow: some View {
        SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
            Task { await load(page: page) }
        }
        .cardRow()
    }

    @ViewBuilder
    private var statusOverlay: some View {
        // First-load (loading + empty) is handled upstream by the skeleton list, so it
        // never reaches this overlay; only the empty/failed result states do.
        switch phase {
        case .loaded where results.isEmpty:
            ContentUnavailableView(
                "No works found",
                systemImage: "books.vertical",
                description: Text("No works for this fandom right now.")
            )
        case .failed(let message):
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

    private func load(page: Int) async {
        if results.isEmpty { phase = .loading }
        do {
            let result = try await AO3Client.shared.search(filters: filters, page: page)
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

    /// Clear the current page (so the first-load skeleton shows) and re-run the fandom
    /// search with whatever filters are now set — the same single request, just newly
    /// parameterised.
    private func reload() {
        phase = .loading
        results = []
        currentPage = 1
        totalPages = 1
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
}
