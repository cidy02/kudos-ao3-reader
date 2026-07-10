import SwiftData
import SwiftUI

/// The full, vertically scrolling list behind a Home section's header ("See all").
/// Reuses the Library's privacy-aware `SensitiveWorkRow`; rows open works the same
/// way the dashboard cards do (straight into the reader).
struct HomeSectionListView: View {
    let kind: HomeSectionKind

    @Environment(\.modelContext) private var context
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    /// Persisted per section, matching WorkCarouselSection's collapse-state convention.
    @AppStorage private var displayMode: WorkListDisplayMode

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var works: [SavedWork]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var expandAll = false
    /// Tracks the in-flight refresh so it can be cancelled if the user switches tabs
    /// (see `cancelRefreshOnTabChange`) — this section can list a large number of works.
    @State private var refreshTask: Task<Void, Never>?
    /// Filters scoped to this one section, applied live to the works on the page.
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    @State private var isSelecting: Bool
    @State private var selection: Set<UUID>

    /// Seeded from the dashboard's own selection so tapping a carousel's "see all"
    /// chevron mid-selection doesn't strand the works you'd already picked — without
    /// this, the expanded list always opened with a fresh, empty selection.
    init(kind: HomeSectionKind, initialSelecting: Bool = false, initialSelection: Set<UUID> = []) {
        self.kind = kind
        _displayMode = AppStorage(wrappedValue: .detailed, "home.\(kind.rawValue).displayMode")
        _isSelecting = State(initialValue: initialSelecting)
        _selection = State(initialValue: initialSelection)
    }

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private var items: [SavedWork] {
        kind.works(from: works, visible: passesPrivacy)
    }

    /// This section's works after the active filters. With no filter set, the section's
    /// own ordering is kept rather than re-sorted by the filter's default sort.
    private var visibleItems: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: items) : items
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
        Group {
            if items.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "books.vertical")
            } else {
                Group {
                    if displayMode == .detailed {
                        detailedList
                    } else {
                        compactGrid
                    }
                }
                .refreshable {
                    let task = Task { _ = await WorkMetadataRefresh.refresh(visibleItems, in: context) }
                    refreshTask = task
                    await task.value
                }
                .cancelRefreshOnTabChange($refreshTask)
                .overlay {
                    // Section has works, but the active filters hid them all.
                    if visibleItems.isEmpty {
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
                } else {
                    // One item holding a tight HStack — separate ToolbarItems get the
                    // system's wide spacing, which reads as inconsistent between the
                    // privacy toggle and the expand/filter cluster. Matches the pattern
                    // already established in LibraryView.swift's dashboard toolbar.
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 2) {
                            if PrivacyGate.hasVisibleMatureWorks(in: visibleItems, hideMature: hideMature) {
                                MatureRevealToggle()
                            }
                            if !items.isEmpty {
                                FilterButton(filtersActive: filters.hasActiveFilters,
                                             showingFilters: $showingFilters,
                                             filterHelp: "Filter the works in this section",
                                             onClearFilters: { filters = LibraryFilters() })
                                WorkListMoreMenu {
                                    Button {
                                        isSelecting = true
                                    } label: {
                                        Label("Select", systemImage: "checklist")
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
            }
        #if os(iOS)
            // Select mode owns the bottom edge with its bulk-action bar; the
            // floating tab/search glass hides meanwhile, matching HomeView's
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
    }

    private var detailedList: some View {
        List {
            ForEach(visibleItems) { work in
                SensitiveWorkRow(
                    work: work,
                    expandAll: expandAll,
                    openMode: .reader,
                    onSelect: isSelecting ? nil : { isSelecting = true; selection = [work.id] },
                    isSelecting: isSelecting,
                    isSelected: selection.contains(work.id),
                    onToggleSelection: { toggleSelection(work) }
                )
                .cardRow(isSelected: isSelecting && selection.contains(work.id))
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
                        .localWorkContextMenu(work: work, onSelect: { isSelecting = true; selection = [work.id] })
                    }
                }
            }
            .padding(16)
        }
    }
}
