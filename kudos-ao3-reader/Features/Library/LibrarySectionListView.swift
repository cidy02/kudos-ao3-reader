import OSLog
import SwiftData
import SwiftUI

/// The full, vertically scrolling list behind a Library section's `>` chevron.
/// Mirrors `HomeSectionListView`, adding the Library's per-row swipe actions.
/// Saved for Later contains only the permanent local queue. AO3 Marked for Later
/// lives in Account. Local rows open the reader; Work Details remains in the
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
    /// Spec 1ah/1ai's Time / State / Fandom / Flat strip. Persisted like
    /// `displayMode`, and only ever shown for History — see `showsGroupingStrip`.
    @AppStorage("library.history.grouping") private var historyGrouping: LibraryHistoryGrouping = .time
    /// Spec 1aj/1ak/1bc/1bd's Works / Authors / Fandoms / Tags strip, and the order
    /// its three aggregate scopes are ranked by. Favorites only.
    @AppStorage("library.favorites.scope") private var favoriteScope: FavoriteScope = .works
    @AppStorage("library.favorites.order") private var favoriteOrder: ReadingAffinities.Order = .recent
    /// Mirrors the scaled width `SensitiveWorkCoverCard`/`AO3WorkCoverCard` actually
    /// render at (see `ScaledCarouselCardSize`), so `compactGrid`'s column count
    /// tracks a card that's grown wider with Dynamic Type instead of assuming the
    /// static base width. Not `private` — see `LibraryEntityGridView.cardSize`.
    var cardSize = ScaledCarouselCardSize()

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

    private var hasAnyContent: Bool { !items.isEmpty }

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
                } else {
                    let hasMature = PrivacyGate.hasVisibleMatureWorks(in: visibleItems, hideMature: hideMature)
                    // Gated as a whole, not just its inner pieces — an empty HStack
                    // still reserves an (empty-looking) toolbar slot when the section
                    // has no works and no mature works to reveal.
                    //
                    // Matches the pattern already established in LibraryView.swift's
                    // dashboard toolbar. WorkListMoreMenu's own gate widened to
                    // `hasAnyContent || hasMature` — Privacy now lives inside it, so
                    // it needs a home even when the section has no other content.
                    if hasAnyContent || hasMature {
                        ActionToolbar(items: [
                            hasAnyContent
                                ? AnyView(FilterButton(filtersActive: filters.hasActiveFilters,
                                                        showingFilters: $showingFilters,
                                                        filterHelp: "Filter the works in this section",
                                                        onClearFilters: { filters = LibraryFilters() },
                                                        badgeCount: filters.summaryLabels(includesSort: false).count))
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
                                }
                                DisplayModeMenuPicker(mode: $displayMode)
                                // Compact cards don't expand/collapse — only detailed rows do.
                                if displayMode == .detailed {
                                    ExpandAllMenuItem(expandAll: $expandAll)
                                }
                            })
                        ].compactMap { $0 })
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
    }

    @ViewBuilder
    private var content: some View {
        if showsAffinityList {
            // Ahead of the empty-shelf branch on purpose: a reader with no starred
            // works still has authors and tags behind what they have read, and
            // `hasAnyContent` only knows about starred works.
            affinityList
        } else if kind.isPlaceholder {
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
        }
    }

    /// Library's sections span every fandom in the library, so this page is
    /// scoped to the tab rather than to one work: its wash comes from the app
    /// accent (spec 1m's rule), while each row keeps its own fandom's hue.
    private var scopePalette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: themeManager.scopeHue)
    }

    private var headerTallyLine: String {
        if filters.hasActiveFilters, visibleItems.isEmpty, !items.isEmpty {
            let count = items.count
            return "\(count) \(count == 1 ? "work" : "works") · none match the current filters"
        }
        let workCount = visibleItems.count
        return "\(workCount) \(workCount == 1 ? "work" : "works")"
    }

    private var filterCollisionCard: some View {
        LibraryFilterCollisionCard(
            sectionTitle: kind.title,
            hiddenCount: items.count,
            filters: $filters,
            works: items,
            palette: scopePalette,
            onEdit: { showingFilters = true }
        )
    }

    /// The kicker / rule / 32pt hero, as the list's first row rather than as a
    /// navigation title — spec 1c scrolls it away under the chrome, which a
    /// `navigationTitle` cannot do.
    private var subjectHeader: some View {
        SubjectHeaderBlock(
            kicker: "Library",
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

    /// Favorites' four scopes. Works keeps the existing work list — with its swipe
    /// actions, select mode and filters — and the other three are aggregates over the
    /// reading log (see `ReadingAffinities`).
    nonisolated enum FavoriteScope: String, CaseIterable, Hashable, Sendable {
        case works
        case authors
        case fandoms
        case tags

        var title: String {
            switch self {
            case .works: "Works"
            case .authors: "Authors"
            case .fandoms: "Fandoms"
            case .tags: "Tags"
            }
        }
    }

    private var showsFavoriteScopes: Bool { kind == .favorites }

    /// True when an aggregate scope is showing, so the work list, its filters and
    /// its select mode all stand down — none of them mean anything over a list of
    /// tag names.
    private var showsAffinityList: Bool {
        showsFavoriteScopes && favoriteScope != .works
    }

    private var favoriteScopeStrip: some View {
        VStack(spacing: 8) {
            SubjectSegmentedControl(
                options: FavoriteScope.allCases,
                title: \.title,
                selection: $favoriteScope
            )
            if showsAffinityList {
                SubjectSegmentedControl(
                    options: ReadingAffinities.Order.allCases,
                    title: \.title,
                    selection: $favoriteOrder
                )
            }
        }
        .padding(.horizontal, SubjectMetrics.gutter)
    }

    /// Every work the reader may see, not just the starred ones: the spec's rows say
    /// "6 works read", which is a fact about everything read, and an Authors list
    /// restricted to starred works would mostly be empty.
    ///
    /// **Filtered through `passesPrivacy`.** A work the mature gate is hiding must
    /// not have its author, fandom or tags named on this page — the row would put
    /// back exactly what the gate took away, one screen over.
    private var affinitySourceWorks: [SavedWork] {
        works.filter { !$0.isQueueOnlyWork && passesPrivacy($0) }
    }

    private var affinityRows: [ReadingAffinities.Row] {
        let source = affinitySourceWorks
        let summaries = ReadingLogService.summaries(in: context)
        switch favoriteScope {
        case .works: return []
        case .authors:
            return ReadingAffinities.authors(works: source, summaries: summaries, order: favoriteOrder)
        case .fandoms:
            return ReadingAffinities.fandoms(works: source, summaries: summaries, order: favoriteOrder)
        case .tags:
            return ReadingAffinities.tags(works: source, summaries: summaries, order: favoriteOrder)
        }
    }

    /// The aggregate scopes as their own list. Deliberately not folded into
    /// `detailedList`: that one is built around works — swipes, selection, the
    /// filter rail — and none of it applies to a row that is a tag name.
    private var affinityList: some View {
        let rows = affinityRows
        return List {
            Section {
                affinityHeader(count: rows.count)
                    .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                favoriteScopeStrip
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if rows.isEmpty {
                Section {
                    affinityEmptyCard.pageBodyRow(top: 14, gutter: SubjectMetrics.gutter)
                }
            } else {
                Section {
                    SectionRuleHeader(title: favoriteScope.title, count: rows.count)
                        .pageBodyRow(top: 18, gutter: 0)
                    ForEach(rows) { row in
                        FavoriteAffinityRow(
                            row: row,
                            palette: scopePalette,
                            usesHashTile: favoriteScope == .tags
                        )
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                    }
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: scopePalette)
    }

    /// The same header block, tallying rows rather than works — on the Tags scope
    /// "34 works" would be a count of something not on screen.
    private func affinityHeader(count: Int) -> some View {
        SubjectHeaderBlock(
            kicker: "Library",
            title: kind.title,
            subtitle: "\(count) \(count == 1 ? singularScopeNoun : favoriteScope.title.lowercased())",
            palette: scopePalette
        )
    }

    private var singularScopeNoun: String {
        switch favoriteScope {
        case .works: "work"
        case .authors: "author"
        case .fandoms: "fandom"
        case .tags: "tag"
        }
    }

    private var affinityEmptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing read yet")
                .font(.system(size: 15, weight: .semibold))
            Text("These are the \(favoriteScope.title.lowercased()) behind the works you have "
                + "actually read, ranked. They fill in as you read — there is nothing to star.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    /// Only History gets the grouping strip. The other six sections are already one
    /// thing by definition — a Downloaded list grouped by state would be one bucket —
    /// and spec 1ah/1ai draw the control on History alone.
    private var showsGroupingStrip: Bool { kind == .history }

    private var groupingStrip: some View {
        SubjectSegmentedControl(
            options: LibraryHistoryGrouping.allCases,
            title: \.title,
            selection: $historyGrouping
        )
        .padding(.horizontal, SubjectMetrics.gutter)
    }

    /// The visible works bucketed by the current grouping, or one unnamed group for
    /// every other section.
    private var groupedItems: [LibraryHistoryGrouping.Bucket] {
        guard showsGroupingStrip else {
            return visibleItems.isEmpty
                ? []
                : [LibraryHistoryGrouping.Bucket(title: kind.title, workIDs: visibleItems.map(\.id))]
        }
        return LibraryHistoryGrouping.groups(
            historyGrouping,
            works: visibleItems,
            isAbandoned: { ReadingLogService.isAbandoned(work: $0) }
        )
    }

    private var detailedList: some View {
        // Both bound once: `groupedItems` buckets the whole list and `summaries`
        // fetches the session table. Reading either through its property inside the
        // builder would repeat that work per section.
        //
        // The session fetch is gated on History. Six of the seven sections never draw
        // the facts strip, and fetching the whole log on every render of Downloaded
        // to throw it away would be the most expensive thing this screen does.
        let groups = groupedItems
        let summaries = showsGroupingStrip
            ? ReadingLogService.summaries(in: context)
            : [:]
        let byID = Dictionary(visibleItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return List {
            subjectHeaderSection

            if showsFavoriteScopes {
                Section {
                    favoriteScopeStrip
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if showsGroupingStrip {
                Section {
                    groupingStrip
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if !visibleItems.isEmpty {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.workIDs, id: \.self) { id in
                            if let work = byID[id] {
                                row(work, summary: summaries[id]).cardRow(
                                    isSelected: isSelecting && selection.contains(work.id),
                                    tintHue: CoverArt.workHue(
                                        fandoms: work.workFandoms, title: work.title
                                    )
                                )
                            }
                        }
                    } header: {
                        SectionRuleHeader(title: group.title, count: group.workIDs.count)
                            .textCase(nil)
                            .listRowInsets(EdgeInsets())
                            .padding(.bottom, 10)
                    }
                }
            } else if filters.hasActiveFilters {
                Section {
                    filterCollisionCard
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: scopePalette)
    }

    /// Column count tracks the actual scaled card width at every Dynamic Type step
    /// (not just an accessibility-size on/off gate — see
    /// `CarouselCardMetrics.adaptiveCardColumns`), so two columns of scaled-wide
    /// cards never overlap on screen.
    private var compactGridColumns: [GridItem] {
        CarouselCardMetrics.adaptiveCardColumns(minimum: cardSize.width)
    }

    /// Apple Books-style two-up grid — the same cover cards every carousel already
    /// uses, wrapping down the page instead of scrolling horizontally.
    private var compactGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                subjectHeader.padding(.top, 20)
                filterChipRail
                SectionRuleHeader(title: kind.title, count: visibleItems.count)
                if visibleItems.isEmpty, filters.hasActiveFilters {
                    filterCollisionCard.padding(.horizontal, 16)
                } else {
                    workGrid
                }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    /// A local work row with the Library's standard swipe actions (save / favorite /
    /// delete). Tapping opens the reader via the root `LocalWorkDestination`. In
    /// selection mode, swipe actions give way to a plain selectable row, matching
    /// LibraryView's own selectList (swipe and selection don't mix well in one row).
    @ViewBuilder
    private func row(_ work: SavedWork, summary: WorkReadingSummary?) -> some View {
        if isSelecting {
            VStack(alignment: .leading, spacing: 8) {
                SensitiveWorkRow(
                    work: work,
                    expandAll: expandAll,
                    openMode: .reader,
                    isSelecting: true,
                    isSelected: selection.contains(work.id),
                    onToggleSelection: { toggleSelection(work) },
                    presentation: .ledger
                )
                factsStrip(work, summary: summary)
            }
        } else {
            swipeableRow(work, summary: summary)
        }
    }

    /// Spec 1ah's per-row log facts — time read, the reread count, what is new since
    /// the last visit. Only on History, and only when the log has something to say:
    /// a row that read "0m · Read ×0" would be three pieces of furniture saying
    /// nothing.
    @ViewBuilder
    private func factsStrip(_ work: SavedWork, summary: WorkReadingSummary?) -> some View {
        if showsGroupingStrip, let summary, summary.visitCount > 0 {
            ReadingHistoryFactsStrip(
                summary: summary,
                postedChapterCount: work.postedChapterCount,
                palette: scopePalette
            )
        }
    }

    private func swipeableRow(_ work: SavedWork, summary: WorkReadingSummary?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SensitiveWorkRow(
                work: work,
                expandAll: expandAll,
                openMode: .reader,
                onSelect: { isSelecting = true; selection = [work.id] },
                presentation: .ledger
            )
            factsStrip(work, summary: summary)
        }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    WorkLifecycle.setSaved(work, !work.isSaved, in: context)
                } label: {
                    Label(
                        WorkActionLabels.saved(isSaved: work.isSaved).title,
                        systemImage: WorkActionLabels.saved(isSaved: work.isSaved).systemImage
                    )
                }
                .tint(.blue)

                Button {
                    work.isFavorite.toggle()
                    work.markModified()
                    try? context.save()
                } label: {
                    let labels = WorkActionLabels.favorite(isFavorite: work.isFavorite)
                    Label(labels.title, systemImage: labels.systemImage)
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

    private func refreshSection() async {
        _ = await WorkMetadataRefresh.refresh(visibleItems, in: context, auth: auth)
    }
}
