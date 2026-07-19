import OSLog
import SwiftData
import SwiftUI

/// The full, vertically scrolling list behind a Library section's `>` chevron.
/// Mirrors `HomeSectionListView`, but adds the Library's per-row swipe actions and,
/// for Saved for Later, also surfaces the user's AO3 "Marked for Later" list in a
/// second section. Local rows open the reader; Work Details remains in the
/// long-press menu.
struct LibrarySectionListView: View {
    let kind: LibrarySectionKind

    @Environment(\.modelContext) private var context
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AO3AuthService.self) private var auth
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    /// Persisted per section, matching WorkCarouselSection's collapse-state convention.
    @AppStorage private var displayMode: WorkListDisplayMode

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var works: [SavedWork]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var pendingDelete: SavedWork?
    @State private var markedForLater: [AO3WorkSummary] = []
    @State private var expandAll = false
    /// Tracks the in-flight refresh so it can be cancelled if the user switches tabs
    /// (see `cancelRefreshOnTabChange`) — this section can list a large number of works.
    @State private var refreshTask: Task<Void, Never>?
    /// Filters scoped to this one section — applied live to the works already on the
    /// page, not the app-wide Library filter.
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    @State private var isSelecting: Bool
    @State private var selection: Set<UUID>

    /// Seeded from the dashboard's own selection so tapping a carousel's "see all"
    /// chevron mid-selection doesn't strand the works you'd already picked — without
    /// this, the expanded list always opened with a fresh, empty selection.
    init(kind: LibrarySectionKind, initialSelecting: Bool = false, initialSelection: Set<UUID> = []) {
        self.kind = kind
        _displayMode = AppStorage(wrappedValue: .detailed, "library.\(kind.rawValue).displayMode")
        _isSelecting = State(initialValue: initialSelecting)
        _selection = State(initialValue: initialSelection)
    }

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    /// This section's works (before the filter panel narrows them further).
    private var items: [SavedWork] {
        kind.works(from: works, visible: passesPrivacy)
    }

    /// This section's works after the active filters — what the list renders. When no
    /// filter is set, the section's own ordering (e.g. most-recently-read first) is kept
    /// rather than re-sorted by the filter's default sort.
    private var visibleItems: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: items) : items
    }

    /// The remote Marked-for-Later list with any locally-saved work removed — a work
    /// in both renders once, in the local section above, as its richer local row.
    private var remoteOnlyMarkedForLater: [AO3WorkSummary] {
        CanonicalWorkMerge.remoteOnly(remote: markedForLater, localLibrary: works)
    }

    /// The de-duplicated remote list, narrowed by the active fandom filter (the
    /// other facets need local metadata these summaries don't carry).
    private var visibleMarkedForLater: [AO3WorkSummary] {
        guard !filters.fandoms.isEmpty else { return remoteOnlyMarkedForLater }
        let wanted = Set(filters.fandoms.map { $0.lowercased() })
        return remoteOnlyMarkedForLater.filter { summary in
            summary.fandoms.contains { wanted.contains($0.lowercased()) }
        }
    }

    /// Saved for Later is the one section that merges in a remote (AO3) list.
    private var showsMarkedForLater: Bool {
        kind == .savedForLater && !visibleMarkedForLater.isEmpty
    }

    /// Whether the section has any works at all (pre-filter) — drives the toolbar.
    private var hasAnyContent: Bool {
        !items.isEmpty || (kind == .savedForLater && !remoteOnlyMarkedForLater.isEmpty)
    }

    private var selectedWorks: [SavedWork] {
        visibleItems.filter { selection.contains($0.id) }
    }

    private func toggleSelection(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private func exitSelectMode() {
        isSelecting = false
        selection = []
    }

    private var allVisibleSelected: Bool {
        let ids = Set(visibleItems.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    private func toggleSelectAll() {
        selection = allVisibleSelected ? [] : Set(visibleItems.map(\.id))
    }

    var body: some View {
        content
            .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle(kind.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .confirmationAction) {
                        SelectAllButton(allSelected: allVisibleSelected, action: toggleSelectAll)
                    }
                    #if os(iOS)
                    ToolbarItemGroup(placement: .bottomBar) {
                        WorkBulkActionBar(selectedWorks: selectedWorks, onDeleted: exitSelectMode, onDone: exitSelectMode)
                    }
                    #else
                    ToolbarItemGroup(placement: .primaryAction) {
                        WorkBulkActionBar(selectedWorks: selectedWorks, onDeleted: exitSelectMode, onDone: exitSelectMode)
                    }
                    #endif
                } else if PrivacyGate.hasVisibleMatureWorks(in: visibleItems, hideMature: hideMature) || hasAnyContent {
                    // Gated as a whole, not just its inner pieces — an empty HStack
                    // still reserves an (empty-looking) toolbar slot when the section
                    // has no works and no mature works to reveal.
                    //
                    // One item holding a tight HStack — separate ToolbarItems get the
                    // system's wide spacing, which reads as inconsistent between the
                    // privacy toggle and the expand/filter cluster. Matches the pattern
                    // already established in LibraryView.swift's dashboard toolbar.
                    ActionToolbar {
                        if PrivacyGate.hasVisibleMatureWorks(in: visibleItems, hideMature: hideMature) {
                            MatureRevealToggle()
                        }
                        if hasAnyContent {
                            FilterButton(filtersActive: filters.hasActiveFilters,
                                         showingFilters: $showingFilters,
                                         filterHelp: "Filter the works in this section",
                                         onClearFilters: { filters = LibraryFilters() })
                            WorkListMoreMenu {
                                if !items.isEmpty {
                                    Button {
                                        isSelecting = true
                                    } label: {
                                        Label("Select", systemImage: "checklist")
                                    }
                                }
                                DisplayModeMenuPicker(mode: $displayMode)
                                // Compact cards don't expand/collapse — only detailed rows do.
                                if displayMode == .detailed {
                                    ExpandAllMenuItem(expandAll: $expandAll)
                                }
                            }
                        }
                    }
                }
            }
        #if os(iOS)
            // Select mode owns the bottom edge with its bulk-action bar; the
            // floating tab/search glass hides meanwhile, matching LibraryView's
            // dashboard — this page is reached by pushing past it, and previously
            // kept showing the tab bar underneath/instead of the bulk-action bar.
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        #endif
            .inspector(isPresented: $showingFilters) {
                LibraryFilterPanel(filters: $filters, works: items, userTagNames: allTags.map(\.name))
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                #if os(iOS)
                    .presentationDragIndicator(.visible)
                #endif
            }
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Delete this work?",
                confirmLabel: "Delete",
                message: { PreservedWorkService.deleteConfirmationMessage(for: $0) },
                perform: { PreservedWorkService.softDelete($0, in: context) }
            )
            .task(id: auth.isLoggedIn) {
                if kind == .savedForLater { await loadMarkedForLater() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if kind.isPlaceholder {
            ContentUnavailableView {
                Label(kind.title, systemImage: kind.emptyIcon)
            } description: {
                Text(kind.emptyMessage)
            }
        } else if !hasAnyContent {
            // The section genuinely has no works (independent of any filter).
            ContentUnavailableView {
                Label(kind.title, systemImage: kind.emptyIcon)
            } description: {
                Text(kind.emptyMessage)
            }
        } else {
            Group {
                if displayMode == .detailed {
                    detailedList
                } else {
                    compactGrid
                }
            }
            .refreshable {
                let task = Task { await refreshSection() }
                refreshTask = task
                await task.value
            }
            .cancelRefreshOnTabChange($refreshTask)
            .overlay {
                // Section has works, but the active filters hid them all.
                if visibleItems.isEmpty, !showsMarkedForLater {
                    ContentUnavailableView {
                        Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No works in this section match the current filters.")
                    } actions: {
                        Button("Clear Filters") { filters = LibraryFilters() }
                    }
                }
            }
        }
    }

    private var detailedList: some View {
        List {
            if !visibleItems.isEmpty {
                Section {
                    ForEach(visibleItems) { work in
                        row(work).cardRow(isSelected: isSelecting && selection.contains(work.id))
                    }
                } header: {
                    if showsMarkedForLater { Text("Saved for Later in Kudos") }
                }
            }
            if showsMarkedForLater {
                Section("Marked for Later on AO3") {
                    ForEach(visibleMarkedForLater) { work in
                        AO3WorkRow(work: work, expandAll: expandAll)
                            .cardNavigation(to: work, accessibilityLabel: work.title)
                    }
                    .cardRow()
                }
            }
        }
        .cardList()
    }

    /// Apple Books-style two-up grid — the same cover cards every carousel already
    /// uses, wrapping down the page instead of scrolling horizontally.
    private var compactGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(visibleItems) { work in
                    if isSelecting {
                        SensitiveWorkCoverCard(
                            work: work,
                            isSelecting: true,
                            isSelected: selection.contains(work.id),
                            onToggleSelection: { toggleSelection(work) }
                        )
                        .localWorkContextMenu(work: work)
                    } else {
                        NavigationLink(value: LocalWorkDestination.reader(work)) {
                            SensitiveWorkCoverCard(work: work)
                        }
                        .buttonStyle(.plain)
                        .localWorkContextMenu(
                            work: work,
                            onSelect: { isSelecting = true; selection = [work.id] }
                        )
                    }
                }
                if showsMarkedForLater {
                    ForEach(visibleMarkedForLater) { work in
                        NavigationLink(value: work) {
                            AO3WorkCoverCard(work: work)
                        }
                        .buttonStyle(.plain)
                        .remoteWorkContextMenu(work: work)
                    }
                }
            }
            .padding(16)
        }
    }

    /// A local work row with the Library's standard swipe actions (save / favorite /
    /// delete). Tapping opens the reader via the root `LocalWorkDestination`. In
    /// selection mode, swipe actions give way to a plain selectable row, matching
    /// LibraryView's own selectList (swipe and selection don't mix well in one row).
    @ViewBuilder
    private func row(_ work: SavedWork) -> some View {
        if isSelecting {
            SensitiveWorkRow(
                work: work,
                expandAll: expandAll,
                openMode: .reader,
                isSelecting: true,
                isSelected: selection.contains(work.id),
                onToggleSelection: { toggleSelection(work) }
            )
        } else {
            swipeableRow(work)
        }
    }

    private func swipeableRow(_ work: SavedWork) -> some View {
        SensitiveWorkRow(
            work: work,
            expandAll: expandAll,
            openMode: .reader,
            onSelect: { isSelecting = true; selection = [work.id] }
        )
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    WorkLifecycle.setSaved(work, !work.isSaved, in: context)
                } label: {
                    Label(work.isSaved ? "Unsave" : "Save",
                          systemImage: work.isSaved ? "bookmark.slash" : "bookmark")
                }
                .tint(.blue)

                Button {
                    work.isFavorite.toggle()
                    work.markModified()
                    try? context.save()
                } label: {
                    Label(work.isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: work.isFavorite ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
            .swipeActions(edge: .trailing) {
                if work.isQueueOnlyWork {
                    // Queue-only works keep a preserved EPUB and must never be hard-deleted
                    // by a generic Library swipe. Removing the queue membership is
                    // non-destructive (the record and EPUB survive); explicit deletion of a
                    // preserved copy lives behind confirmation in Queue Storage.
                    Button(role: .destructive) {
                        ReadingQueueService.removeFromAllQueues(work, in: context)
                    } label: {
                        Label("Remove from Queue", systemImage: "minus.circle")
                    }
                } else {
                    Button(role: .destructive) {
                        if confirmBeforeDelete {
                            pendingDelete = work
                        } else {
                            PreservedWorkService.softDelete(work, in: context)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    private func loadMarkedForLater() async {
        do {
            markedForLater = try await auth.accountWorks(
                from: AO3Client.markedForLaterURL, recordAs: .markedForLater
            )
        } catch {
            // A refresh failure (network, rate limit, expired session) must not wipe
            // out a previously successful fetch — keep showing what's already there.
            Log.network.notice(
                "Marked for Later refresh failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func refreshSection() async {
        _ = await WorkMetadataRefresh.refresh(visibleItems, in: context)
        if kind == .savedForLater { await loadMarkedForLater() }
    }
}
