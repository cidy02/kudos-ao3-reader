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
    @Environment(AO3AuthService.self) private var auth
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
    /// Mirrors the scaled width `SensitiveWorkCoverCard`/`WorkCoverCard` actually
    /// render at (see `ScaledCarouselCardSize`), so `compactGrid`'s column count
    /// tracks a card that's grown wider with Dynamic Type instead of assuming the
    /// static base width. Not `private` — see `LibraryEntityGridView.cardSize`.
    var cardSize = ScaledCarouselCardSize()

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

    /// This page is scoped to a Home section, not to one work, so its wash comes
    /// from the app accent rather than from any fandom — spec 1m: "the header
    /// wash is the user's app accent colour ... not a fixed value". The red in
    /// artboards 1ad/1af is the default AO3 red seen through that rule.
    private var scopePalette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: themeManager.scopeHue)
    }

    /// The line under the hero: how many works, and what order they are in.
    private var headerTallyLine: String {
        let workCount = visibleItems.count
        let noun = workCount == 1 ? "work" : "works"
        return "\(workCount) \(noun) · \(kind.orderDescription)"
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
                    let task = Task { _ = await WorkMetadataRefresh.refresh(visibleItems, in: context, auth: auth) }
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
                    let hasMature = PrivacyGate.hasVisibleMatureWorks(in: visibleItems, hideMature: hideMature)
                    // Gated as a whole, not just its inner pieces — an empty HStack
                    // still reserves an (empty-looking) toolbar slot when the section
                    // has no works and no mature works to reveal.
                    //
                    // Matches the pattern already established in LibraryView.swift's
                    // dashboard toolbar. WorkListMoreMenu's own gate widened to
                    // `!items.isEmpty || hasMature` (was `!items.isEmpty` alone) —
                    // Privacy now lives inside it, so it needs a home even when the
                    // section itself is empty but has mature works to reveal.
                    if !items.isEmpty || hasMature {
                        ActionToolbar(items: [
                            !items.isEmpty
                                ? AnyView(FilterButton(filtersActive: filters.hasActiveFilters,
                                                        showingFilters: $showingFilters,
                                                        filterHelp: "Filter the works in this section",
                                                        onClearFilters: { filters = LibraryFilters() }))
                                : nil,
                            AnyView(WorkListMoreMenu {
                                if hasMature {
                                    MatureRevealToggle()
                                }
                                if !items.isEmpty {
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
                            })
                        ].compactMap { $0 })
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
            subjectHeaderSection

            Section {
                ForEach(visibleItems) { work in
                    SensitiveWorkRow(
                        work: work,
                        expandAll: expandAll,
                        openMode: .reader,
                        onSelect: isSelecting ? nil : { isSelecting = true; selection = [work.id] },
                        isSelecting: isSelecting,
                        isSelected: selection.contains(work.id),
                        onToggleSelection: { toggleSelection(work) },
                        presentation: .ledger
                    )
                    // The row's wash is painted here, at the card's true outer
                    // edge, rather than inside `WorkLedgerRow` — see its
                    // `drawsBackground` note.
                    .cardRow(
                        isSelected: isSelecting && selection.contains(work.id),
                        tintHue: CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
                    )
                }
            } header: {
                SectionRuleHeader(title: kind.title, count: visibleItems.count)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets())
                    .padding(.bottom, 10)
            }
        }
        .cardList()
        .subjectScreenWash(palette: scopePalette)
    }

    /// The kicker / rule / 32pt hero, as the list's first row rather than as a
    /// navigation title: spec 1ad scrolls it away under the floating chrome, and
    /// a `navigationTitle` cannot do that.
    private var subjectHeader: some View {
        SubjectHeaderBlock(
            kicker: "Home",
            title: kind.title,
            subtitle: headerTallyLine,
            palette: scopePalette
        )
    }

    private var subjectHeaderSection: some View {
        Section {
            subjectHeader
            .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            filterChipRail
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// What is currently filtering this page, as chips, with the way to change
    /// them pinned at the trailing edge (spec 1ad, 1k).
    ///
    /// The count on the dashed chip excludes sort: sort is always set to
    /// something, so counting it would mean the button never reads as "no
    /// filters" even on a page showing everything.
    private var filterChipRail: some View {
        SubjectFilterRail(
            onOpenFilters: { showingFilters = true },
            activeFilterCount: filters.summaryLabels(includesSort: false).count
        ) {
            ForEach(filters.summaryLabels(), id: \.self) { label in
                SubjectChip(
                    text: label.text,
                    style: .tinted,
                    systemImage: label.symbol,
                    palette: scopePalette
                )
            }
        }
    }

    /// Column count tracks the actual scaled card width at every Dynamic Type step
    /// (not just an accessibility-size on/off gate — see
    /// `CarouselCardMetrics.adaptiveCardColumns`), so two columns of scaled-wide
    /// cards never overlap on screen. Two-up on iPhone at normal text sizes, wider
    /// on iPad/macOS, fewer as the cards grow, one at accessibility sizes.
    private var compactGridColumns: [GridItem] {
        CarouselCardMetrics.adaptiveCardColumns(minimum: cardSize.width)
    }

    /// Apple Books-style grid — the same cover cards every carousel already uses,
    /// wrapping down the page instead of scrolling horizontally.
    private var compactGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                subjectHeader.padding(.top, 20)
                filterChipRail
                SectionRuleHeader(title: kind.title, count: visibleItems.count)
                workGrid
            }
        }
        .subjectScreenWash(palette: scopePalette)
    }

    private var workGrid: some View {
        LazyVGrid(columns: compactGridColumns, spacing: CarouselCardMetrics.compactGridSpacing) {
            ForEach(visibleItems) { work in
                if isSelecting {
                    SensitiveWorkCoverCard(
                        work: work,
                        footer: updateFooter(for: work),
                        isSelecting: true,
                        isSelected: selection.contains(work.id),
                        onToggleSelection: { toggleSelection(work) }
                    )
                    .localWorkContextMenu(work: work)
                } else {
                    NavigationLink(value: LocalWorkDestination.reader(work)) {
                        SensitiveWorkCoverCard(work: work, footer: updateFooter(for: work))
                    }
                    .buttonStyle(.plain)
                    .localWorkContextMenu(
                        work: work,
                        onSelect: { isSelecting = true; selection = [work.id] }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
    private func updateFooter(for work: SavedWork) -> String? {
        guard kind == .recentlyUpdated else { return nil }
        return "+\(work.postedChapterCount - work.knownChapterCount) new"
    }

}
