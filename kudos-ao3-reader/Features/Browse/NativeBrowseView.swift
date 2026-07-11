import SwiftData
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
                .navigationDestination(for: AO3TagWorksRequest.self) { request in
                    TagWorksView(request: request)
                }
                .navigationDestination(for: AO3WorkSummary.self) { work in
                    WorkDetailView(remote: work)
                }
                .ao3AuthorNavigation(path: $path, tab: .browse)
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
    @State private var phase: Phase = .loading
    @State private var expandAll = false
    /// The active filters for this fandom's works — seeded to just the fandom, then
    /// refined via the same filter panel the Search tab uses.
    @State private var filters: AO3SearchFilters
    @State private var showingFilters = false

    @Environment(\.modelContext) private var context
    @State private var isSelecting = false
    @State private var selection: Set<Int> = []
    @State private var isProcessingBatch = false
    @State private var batchTask: Task<Void, Never>?
    @State private var resolvedQueueWorks: [SavedWork] = []
    @State private var showingAddToQueue = false
    @State private var resolvedCollectionWorks: [SavedWork] = []
    @State private var showingAddToCollection = false
    @State private var batchActionError: String?

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
    private var hasExtraFilters: Bool {
        filters != Self.baseline(for: fandom)
    }

    private var selectedSummaries: [AO3WorkSummary] {
        results.filter { selection.contains($0.id) }
    }

    var body: some View {
        Group {
            if phase == .loading, results.isEmpty {
                // First load of this fandom's works — show the shape of the results.
                AO3WorkRowSkeletonList(count: 6)
            } else {
                List {
                    if showPagination { Section { paginationRow } }
                    Section {
                        ForEach(results) { work in
                            workRow(for: work)
                                .cardRow(isSelected: isSelecting && selection.contains(work.id))
                        }
                    }
                    if showPagination { Section { paginationRow } }
                }
                .cardList()
                .refreshable { await load(page: currentPage) }
                .overlay { statusOverlay }
            }
        }
        .navigationTitle(fandom)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            .toolbar { toolbarContent }
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
            .sheet(isPresented: $showingAddToQueue) {
                AddToQueueView(works: resolvedQueueWorks)
            }
            .sheet(isPresented: $showingAddToCollection) {
                AddToCollectionView(works: resolvedCollectionWorks)
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { batchActionError != nil },
                    set: { if !$0 { batchActionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { batchActionError = nil }
            } message: {
                Text(batchActionError ?? "")
            }
            .task { await load(page: 1) }
            // Unstructured batch tasks outlive the view unless explicitly cancelled;
            // the bulk loops bail out cleanly on CancellationError.
            .onDisappear { batchTask?.cancel() }
    }

    @ViewBuilder
    private func workRow(for work: AO3WorkSummary) -> some View {
        let row = AO3WorkRow(
            work: work,
            expandAll: expandAll,
            isSelecting: isSelecting,
            isSelected: selection.contains(work.id)
        )
        if isSelecting {
            Button { toggleSelection(work) } label: { row }
                .buttonStyle(.plain)
                .accessibilityLabel(work.title)
                .accessibilityValue(selection.contains(work.id) ? "Selected" : "Not selected")
                .accessibilityHint("Double-tap to \(selection.contains(work.id) ? "deselect" : "select") this work.")
                .accessibilityAddTraits(selection.contains(work.id) ? .isSelected : [])
        } else {
            row.cardNavigation(to: work)
        }
    }

    private func toggleSelection(_ work: AO3WorkSummary) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private var showPagination: Bool {
        totalPages > 1 && !results.isEmpty
    }

    private var paginationRow: some View {
        SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
            // A different page replaces `results` with different works entirely —
            // a stale selection would otherwise reference IDs that no longer exist.
            selection.removeAll()
            Task { await load(page: page) }
        }
        .cardRow()
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

    // MARK: Multi-select / bulk actions

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { exitSelectMode() }
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) { bulkActionBar }
            #else
            ToolbarItemGroup(placement: .primaryAction) { bulkActionBar }
            #endif
        } else if phase == .loaded, !results.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    FilterButton(filtersActive: hasExtraFilters,
                                 showingFilters: $showingFilters,
                                 filterHelp: "Filter works in this fandom",
                                 onClearFilters: resetFilters)
                    WorkListMoreMenu {
                        Button { isSelecting = true } label: {
                            Label("Select", systemImage: "checklist")
                        }
                        ExpandAllMenuItem(expandAll: $expandAll)
                    }
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    /// The bulk-action controls shown while selecting (bottom bar on iOS), mirroring
    /// `LibraryView`'s bulk-action bar. Each resolves selected remote summaries to
    /// local works one at a time — never bursting concurrent AO3 requests.
    @ViewBuilder
    private var bulkActionBar: some View {
        Button {
            batchTask = Task { await bulkSave() }
        } label: {
            Label("Save", systemImage: "bookmark")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        Spacer()

        Button {
            batchTask = Task { await bulkSaveForLater() }
        } label: {
            Label("Save for Later", systemImage: "clock.arrow.circlepath")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        Spacer()

        Button {
            batchTask = Task { await bulkAddToCollection() }
        } label: {
            Label("Add to Collection", systemImage: "square.stack")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        Spacer()

        Button {
            batchTask = Task { await bulkAddToQueue() }
        } label: {
            Label("Add to Queue", systemImage: "list.bullet.rectangle")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        if isProcessingBatch {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func exitSelectMode() {
        isSelecting = false
        selection = []
    }

    private func bulkSave() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selectedSummaries, in: context) { works in
            for work in works {
                WorkLifecycle.setSaved(work, true, in: context)
            }
        }
    }

    private func bulkSaveForLater() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await bulkSaveForLaterRemote(selectedSummaries, in: context)
    }

    private func bulkAddToCollection() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selectedSummaries, in: context) { works in
            resolvedCollectionWorks = works
            showingAddToCollection = true
        }
    }

    private func bulkAddToQueue() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selectedSummaries, in: context) { works in
            resolvedQueueWorks = works
            showingAddToQueue = true
        }
    }
}

/// A tag's works, loaded natively from an AO3 `/tags/<name>/works` URL (e.g. a tag
/// link tapped in a work's preface). Reuses the search result row, pagination, and
/// first-load skeleton; read-only (no filter panel).
struct TagWorksView: View {
    let request: AO3TagWorksRequest

    @State private var results: [AO3WorkSummary] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var phase: Phase = .loading
    @State private var expandAll = false
    /// Client-side refine of this tag's loaded works — narrows what's on screen in
    /// place, contextual to the page (the tag itself stays fixed).
    @State private var filters = AO3SearchFilters()
    @State private var showingFilters = false

    @Environment(\.modelContext) private var context
    @State private var isSelecting = false
    @State private var selection: Set<Int> = []
    @State private var isProcessingBatch = false
    @State private var batchTask: Task<Void, Never>?
    @State private var resolvedQueueWorks: [SavedWork] = []
    @State private var showingAddToQueue = false
    @State private var resolvedCollectionWorks: [SavedWork] = []
    @State private var showingAddToCollection = false
    @State private var batchActionError: String?

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    /// This page's works narrowed by the active refine filters.
    private var visibleResults: [AO3WorkSummary] {
        filters.apply(to: results)
    }

    private var selectedSummaries: [AO3WorkSummary] {
        visibleResults.filter { selection.contains($0.id) }
    }

    var body: some View {
        Group {
            if phase == .loading, results.isEmpty {
                AO3WorkRowSkeletonList(count: 6)
            } else {
                List {
                    if showPagination { Section { paginationRow } }
                    Section {
                        ForEach(visibleResults) { work in
                            workRow(for: work)
                                .cardRow(isSelected: isSelecting && selection.contains(work.id))
                        }
                    }
                    if showPagination { Section { paginationRow } }
                }
                .cardList()
                .refreshable { await load(page: currentPage) }
                .overlay { statusOverlay }
            }
        }
        .navigationTitle(request.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            .toolbar { toolbarContent }
            .inspector(isPresented: $showingFilters) {
                AO3FilterPanel(
                    filters: $filters,
                    mode: .refine,
                    canReset: filters.hasActiveFilters,
                    onApply: { showingFilters = false },
                    onReset: { filters = AO3SearchFilters() }
                )
                .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                .navigationTitle("Filter Works")
            }
            .sheet(isPresented: $showingAddToQueue) {
                AddToQueueView(works: resolvedQueueWorks)
            }
            .sheet(isPresented: $showingAddToCollection) {
                AddToCollectionView(works: resolvedCollectionWorks)
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { batchActionError != nil },
                    set: { if !$0 { batchActionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { batchActionError = nil }
            } message: {
                Text(batchActionError ?? "")
            }
            .task { await load(page: 1) }
            .onDisappear { batchTask?.cancel() }
    }

    @ViewBuilder
    private func workRow(for work: AO3WorkSummary) -> some View {
        let row = AO3WorkRow(work: work, expandAll: expandAll, isSelecting: isSelecting, isSelected: selection.contains(work.id))
        if isSelecting {
            Button { toggleSelection(work) } label: { row }
                .buttonStyle(.plain)
                .accessibilityLabel(work.title)
                .accessibilityValue(selection.contains(work.id) ? "Selected" : "Not selected")
                .accessibilityHint("Double-tap to \(selection.contains(work.id) ? "deselect" : "select") this work.")
                .accessibilityAddTraits(selection.contains(work.id) ? .isSelected : [])
        } else {
            row.cardNavigation(to: work)
        }
    }

    private func toggleSelection(_ work: AO3WorkSummary) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { exitSelectMode() }
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) { bulkActionBar }
            #else
            ToolbarItemGroup(placement: .primaryAction) { bulkActionBar }
            #endif
        } else if phase == .loaded, !results.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    FilterButton(filtersActive: filters.hasActiveFilters,
                                 showingFilters: $showingFilters,
                                 onClearFilters: { filters = AO3SearchFilters() })
                    WorkListMoreMenu {
                        Button { isSelecting = true } label: {
                            Label("Select", systemImage: "checklist")
                        }
                        ExpandAllMenuItem(expandAll: $expandAll)
                    }
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    /// Mirrors FandomWorksView's bulk-action bar exactly, sharing the same resolution
    /// helpers so both surfaces behave identically for the same batch actions.
    @ViewBuilder
    private var bulkActionBar: some View {
        Button {
            batchTask = Task { await bulkSave() }
        } label: {
            Label("Save", systemImage: "bookmark")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        Spacer()

        Button {
            batchTask = Task { await bulkSaveForLater() }
        } label: {
            Label("Save for Later", systemImage: "clock.arrow.circlepath")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        Spacer()

        Button {
            batchTask = Task { await bulkAddToCollection() }
        } label: {
            Label("Add to Collection", systemImage: "square.stack")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        Spacer()

        Button {
            batchTask = Task { await bulkAddToQueue() }
        } label: {
            Label("Add to Queue", systemImage: "list.bullet.rectangle")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        if isProcessingBatch {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func exitSelectMode() {
        isSelecting = false
        selection = []
    }

    private func bulkSave() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selectedSummaries, in: context) { works in
            for work in works {
                WorkLifecycle.setSaved(work, true, in: context)
            }
        }
    }

    private func bulkSaveForLater() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await bulkSaveForLaterRemote(selectedSummaries, in: context)
    }

    private func bulkAddToCollection() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selectedSummaries, in: context) { works in
            resolvedCollectionWorks = works
            showingAddToCollection = true
        }
    }

    private func bulkAddToQueue() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selectedSummaries, in: context) { works in
            resolvedQueueWorks = works
            showingAddToQueue = true
        }
    }

    private var showPagination: Bool {
        totalPages > 1 && !results.isEmpty
    }

    private var paginationRow: some View {
        SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
            // A different page replaces `results` with different works entirely —
            // a stale selection would otherwise reference IDs that no longer exist.
            selection.removeAll()
            Task { await load(page: page) }
        }
        .cardRow()
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch phase {
        case .loaded where results.isEmpty:
            ContentUnavailableView(
                "No works found",
                systemImage: "tag",
                description: Text("No works for this tag right now.")
            )
        case .loaded where visibleResults.isEmpty:
            // The page loaded works, but the active refine filters hid them all.
            ContentUnavailableView {
                Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No works on this page match the current filters.")
            } actions: {
                Button("Clear Filters") { filters = AO3SearchFilters() }
            }
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

    private func load(page: Int) async {
        if results.isEmpty { phase = .loading }
        do {
            let result = try await AO3Client.shared.worksPage(at: request.url, page: page)
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
