import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Single Reading Queue screen: Safari-style queue switcher + the full manage
/// surface (filters, reorder, select, display mode, rename/delete) for the
/// active queue. There is no separate "Manage Queue" page — that used to live
/// in `ReadingQueueDetailView`, which is now a thin redirect here.
struct ReadingQueueBrowserView: View {
    /// Which queue to land on. `nil` falls back to the last-selected queue, or the
    /// first queue (Saved for Later) if there's no prior selection.
    var initialQueueID: UUID?
    /// The tab this was opened from, for the kicker: Home's stack passes "Home",
    /// the way `LibrarySectionRoute` carries its origin.
    var originKicker = "Library"

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ThemeManager.self) var themeManager
    @Environment(AO3AuthService.self) private var auth
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var allQueues: [ReadingQueue]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    /// Persists the last-open queue across visits to this screen, independent of
    /// which queue a Library carousel tap pre-selected this time.
    @AppStorage("library.readingQueueBrowser.lastSelectedID") private var lastSelectedIDRaw = ""
    @State private var selectedQueueID: UUID?
    @State var showingSwitcher = false
    @State var showingNewQueue = false
    @State var newQueueName = ""
    /// 1j's colour swatch for the queue being created. `nil` keeps the
    /// name-derived hue.
    @State var newQueueHue: Double?

    // MARK: Manage-surface state (formerly ReadingQueueDetailView)

    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    /// Pushes artboard 1h's "Queue details" screen — a restyle of what this
    /// screen's own overflow menu already does (rename, delete, see what's
    /// preserved), not a new destination's worth of new data.
    @State private var showingQueueDetails = false
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    /// 1h's All · Unread · Offline · WIP, applied before `filters`.
    @State private var quickFilter: QueueQuickFilter = .all
    @State private var showingQueueTags = false
    /// 1h's "+": the Library picker (`AddLibraryWorksSheet`).
    @State private var showingAddWorks = false
    /// Cover grid stays the default. 1h's In line switch sets it per queue;
    /// `ReadingQueue` has no field for it, so it lives in UserDefaults under
    /// the queue's id (`displayModeKey`), loaded when the selected queue changes.
    @State private var displayMode: WorkListDisplayMode = .compact

    /// Which row the chosen mode draws. Ledger, Compact and Detailed are three
    /// separate presentations and a screen shows one of them — this used to pass
    /// `.ledger` unconditionally, so "Detailed" drew ledger rows.
    private var rowPresentation: WorkRow.Presentation {
        displayMode == .ledger ? .ledger : .standard
    }
    @State private var isReordering = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var draggedWorkID: UUID?
    @State private var pendingCompactOrder: [UUID]?
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    var cardSize = ScaledCarouselCardSize()

    /// Saved for Later first, then customs by `sortOrder`.
    var orderedQueues: [ReadingQueue] {
        allQueues.sorted {
            if $0.kind != $1.kind { return $0.kind == .savedForLater }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.displayName < $1.displayName
        }
    }

    /// Falls through to `initialQueueID` before `orderedQueues.first`: `selectedQueueID`
    /// itself isn't written until `resolveInitialSelection()` runs on `.onAppear`, which
    /// is after the first body evaluation. Without this fallback, a push straight into a
    /// specific queue (e.g. tapping a queue card on Home) rendered "Saved for Later" (or
    /// whatever sorts first) for the view's first frame, then swapped to the real target
    /// a beat later — a full ContentUnavailableView/grid + title structural change lands
    /// mid-push-transition, competing with the tab bar's own hide animation for the main
    /// thread. That's what was surfacing as the tab bar lingering after the switcher pill
    /// had already settled, independent of how the switcher pill itself is positioned.
    var selectedQueue: ReadingQueue? {
        let targetID = selectedQueueID ?? initialQueueID
        guard let targetID else { return orderedQueues.first }
        return orderedQueues.first { $0.id == targetID } ?? orderedQueues.first
    }

    private var works: [SavedWork] {
        selectedQueue.map(ReadingQueueService.orderedWorks(in:)) ?? []
    }

    private var visibleWorks: [SavedWork] {
        let quick = quickFilter.apply(to: works, preservedIDs: Set(preservedWorks.map(\.id)))
        return filters.hasActiveFilters ? filters.apply(to: quick) : quick
    }

    /// Reorder needs the whole queue in order, so any narrowing blocks it.
    private var isNarrowed: Bool {
        filters.hasActiveFilters || quickFilter != .all
    }

    /// 1bg: selecting keeps the drag handle live, so select and reorder are
    /// no longer exclusive states. See `ReadingQueueFacts.isDragLive`.
    private var isDragLive: Bool {
        ReadingQueueFacts.isDragLive(isReordering: isReordering, isSelecting: isSelecting, isNarrowed: isNarrowed)
    }

    /// While reordering, filters step aside — move/drag need index-stable unfiltered order.
    private var displayedWorks: [SavedWork] {
        isReordering ? works : visibleWorks
    }

    private var compactDisplayedWorks: [SavedWork] {
        guard let pendingCompactOrder else { return displayedWorks }
        let byID = Dictionary(works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pendingCompactOrder.compactMap { byID[$0] }
    }

    private var compactGridColumns: [GridItem] {
        CarouselCardMetrics.adaptiveCardColumns(minimum: cardSize.width)
    }

    private var selectedWorks: [SavedWork] {
        works.filter { selection.contains($0.id) }
    }

    private var allSelected: Bool {
        let ids = Set(works.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    // MARK: - Subject language (artboard 1h)

    /// A queue's identity colour, matching `queueGlyph`'s dot and
    /// `ReadingQueueCard`'s carousel tint: `ReadingQueue` has no stored colour
    /// field, so the app already derives one consistently from the name via
    /// `CoverArt.hue` — that derived hue *is* this queue's "stored colour" for
    /// every purpose the app has one today, and is what artboard 1h's palette
    /// comes from.
    private var subjectPalette: SubjectPalette {
        guard let selectedQueue else { return themeManager.scopePalette }
        return themeManager.appTheme.subjectPalette(hue: selectedQueue.displayHue)
    }

    private var preservedWorks: [SavedWork] {
        works.filter { $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private var preservedByteCount: Int64 {
        preservedWorks.reduce(0) { $0 + queueWorkFileSize($1.fileURL) }
    }

    /// The header block's own tally line — spec 1h: "12 works · 9 kept offline
    /// · 24.1 MB".
    private var queueSubtitle: String {
        let count = works.count
        let base = "\(count) work\(count == 1 ? "" : "s")"
        guard count > 0 else { return base }
        let offline = preservedWorks.count == count
            ? "all kept offline"
            : "\(preservedWorks.count) kept offline"
        return "\(base) · \(offline) · \(queueByteCountString(preservedByteCount))"
    }

    /// The Library's active-filter labels, drawn only while `LibraryFilters` is
    /// narrowing the queue — 1h's own quick filters (`QueueQuickFilter`) are
    /// the everyday rail, and the toolbar's Filter button opens the panel.
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
                    palette: subjectPalette
                )
            }
        }
    }

    private var subjectHeader: some View {
        SubjectHeaderBlock(
            kicker: ReadingQueueFacts.kicker(origin: originKicker),
            title: selectedQueue?.displayName ?? "Reading Queues",
            subtitle: queueSubtitle,
            palette: subjectPalette
        )
    }

    /// Spec 1h splits a queue into "Up next" and "In line" (everything else,
    /// in the queue's own `sortOrderInQueue` order). Up next is Home's card
    /// face too: `ReadingQueueFacts.upNext`, the first work not yet finished.
    /// Both use `visibleWorks` (filters applied) rather than `displayedWorks`,
    /// since that split only ever renders while `!isReordering`.
    private var upNextSplit: (upNext: SavedWork?, inLine: [SavedWork]) {
        ReadingQueueFacts.upNext(in: visibleWorks)
    }

    private var upNextWork: SavedWork? { upNextSplit.upNext }

    private var inLineWorks: [SavedWork] { upNextSplit.inLine }

    /// 1h's numbered In line rows: the work's place in the whole queue, so a
    /// filter narrows the list without renumbering it.
    private func queuePosition(of work: SavedWork) -> Int? {
        works.firstIndex { $0.id == work.id }.map { $0 + 1 }
    }

    private func ledgerRow(_ work: SavedWork) -> some View {
        SensitiveWorkRow(
            work: work,
            openMode: .reader,
            isSelecting: isSelecting,
            isSelected: selection.contains(work.id),
            onToggleSelection: { toggleSelection(work) },
            presentation: rowPresentation
        )
        .swipeActions(edge: .trailing) {
            if !isSelecting {
                Button(role: .destructive) {
                    if let queue = selectedQueue {
                        ReadingQueueService.removeFromQueue(work, from: queue, in: context)
                    }
                } label: {
                    Label("Remove from Queue", systemImage: "minus.circle")
                }
            }
        }
        .cardRow(
            isSelected: isSelecting && selection.contains(work.id),
            tintHue: CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
        )
    }

    /// 1bg: "The title bar takes the count" while selecting. Otherwise empty on
    /// iOS, where `.subjectScreenWash` hides the title and `SubjectHeaderBlock`
    /// names the page; macOS has no wash and needs a real title for its window.
    private var screenTitle: String {
        if isSelecting { return "\(selection.count) selected" }
        #if os(macOS)
        return horizontalSizeClass == .regular ? "Reading Queues" : (selectedQueue?.displayName ?? "Reading Queues")
        #else
        return ""
        #endif
    }

    private static func displayModeKey(_ queueID: UUID) -> String {
        "library.readingQueueBrowser.displayMode.\(queueID.uuidString)"
    }

    // MARK: - Body

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle(screenTitle)
            .onAppear(perform: resolveInitialSelection)
            // Per-queue layout (1h): load the queue's own choice when the queue
            // changes, store it when the reader changes it. No stored choice
            // keeps the default grid.
            .onChange(of: selectedQueue?.id, initial: true) { _, id in
                guard let id else { return }
                let raw = UserDefaults.standard.string(forKey: Self.displayModeKey(id)) ?? ""
                displayMode = WorkListDisplayMode(rawValue: raw) ?? .compact
            }
            .onChange(of: displayMode) { _, mode in
                guard let id = selectedQueue?.id else { return }
                UserDefaults.standard.set(mode.rawValue, forKey: Self.displayModeKey(id))
            }
            .sheet(isPresented: $showingNewQueue) { newQueueSheet }
            .sheet(isPresented: $showingQueueTags) {
                if let selectedQueue { QueueTagSheet(queue: selectedQueue) }
            }
            .sheet(isPresented: $showingAddWorks) { addWorksSheet }
            .navigationDestination(isPresented: $showingQueueDetails) {
                if let selectedQueue {
                    ReadingQueueSettingsView(queue: selectedQueue, originKicker: originKicker)
                }
            }
            .inspector(isPresented: $showingFilters) {
                LibraryFilterPanel(
                    filters: $filters,
                    works: works,
                    userTagNames: allTags.map(\.name)
                )
                .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                #if os(iOS)
                    .presentationDragIndicator(.visible)
                #endif
            }
            .toolbar { manageToolbar }
            .alert("Rename Queue", isPresented: $showingRename) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    guard let queue = selectedQueue else { return }
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        queue.name = trimmed
                        queue.markModified()
                        context.saveBestEffort(reason: "Saving queue rename failed")
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete “\(selectedQueue?.displayName ?? "Queue")”?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteSelectedQueue() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The queue moves to Recently Deleted for 90 days, with everything in it "
                        + "intact. Works stay in Kudos either way."
                )
            }
    }

    // MARK: - Compact (iPhone)

    private var compactLayout: some View {
        pageContent
            #if os(iOS)
            .toolbar(.hidden, for: .tabBar)
            #endif
    }

    // MARK: - Regular (iPad/Mac)

    private var regularLayout: some View {
        HStack(spacing: 0) {
            List {
                ForEach(orderedQueues) { queue in
                    queueRow(queue)
                }
                .appThemedRows()
                Button {
                    newQueueName = ""
                    showingNewQueue = true
                } label: {
                    Label("New Queue", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .appThemedRows()
            }
            .listStyle(.sidebar)
            .appThemedScroll()
            .frame(width: 240)
            .disabled(isSelecting || isReordering)

            Divider()

            // No separate plain-text title row here any more: `pageContent`'s own
            // `SubjectHeaderBlock` (kicker, 32pt name, tallies) is the page's name
            // now, on iPad/Mac exactly as on iPhone, so the split view doesn't show
            // the queue's name twice.
            pageContent
        }
        #if os(iOS)
        // This screen always owns the bottom chrome (switcher and/or select
        // bulk bar in compactLayout; regularLayout has no phone-style tab bar
        // to begin with, but stays consistent with compactLayout regardless).
        .toolbar(.hidden, for: .tabBar)
        #endif
    }
}

// Split from the struct above purely to keep each declaration's own body under
// this repo's type-body-length gate — SwiftLint measures a `struct`/`extension`
// block's length individually, so this line is otherwise inert: every member
// below still reads and writes the same `@State`/`@Query` properties declared
// above, exactly as if this were one uninterrupted body.
extension ReadingQueueBrowserView {
    // MARK: - Active queue content

    @ViewBuilder
    private var pageContent: some View {
        if let selectedQueue, works.isEmpty {
            ContentUnavailableView {
                Label(
                    selectedQueue.displayName,
                    systemImage: selectedQueue.kind == .savedForLater
                        ? WorkActionLabels.savedForLaterEmptySymbol
                        : "list.bullet.rectangle"
                )
            } description: {
                Text("Works you add to this queue will keep a local EPUB for offline reading.")
            } actions: {
                Button {
                    showingAddWorks = true
                } label: {
                    Label("Add Works", systemImage: "plus")
                }
            }
        } else {
            Group {
                if displayMode != .compact {
                    detailedList
                } else {
                    compactGrid
                }
            }
            .refreshable {
                let task = Task { _ = await WorkMetadataRefresh.refresh(visibleWorks, in: context, auth: auth) }
                refreshTask = task
                await task.value
            }
            .cancelRefreshOnTabChange($refreshTask)
            .overlay {
                if visibleWorks.isEmpty, !works.isEmpty, !isReordering {
                    ContentUnavailableView {
                        Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No works in this queue match the current filters.")
                    } actions: {
                        Button("Clear Filters") {
                            filters = LibraryFilters()
                            quickFilter = .all
                        }
                    }
                }
            }
        }
    }

    private var detailedList: some View {
        List {
            if isReordering || isSelecting {
                // Flat and unsectioned: `.onMove` only reorders within the
                // `ForEach` it is attached to, so a drag that should be able to
                // promote any work into "Up next" needs one `ForEach` over the
                // whole queue, not two split across sections. 1bg: selecting keeps
                // each row's position number and the live handle.
                if isSelecting { subjectHeaderSection }
                ForEach(displayedWorks) { work in
                    ledgerRow(work)
                        .environment(\.ledgerPositionNumber, queuePosition(of: work))
                }
                .onMove(perform: moveAction)
            } else {
                subjectHeaderSection
                if let upNextWork {
                    Section {
                        SectionRuleHeader(title: "Up Next")
                            .pageBodyRow(top: 18, gutter: 0)
                        ledgerRow(upNextWork)
                    }
                }
                if !inLineWorks.isEmpty {
                    Section {
                        inLineHeader
                            .pageBodyRow(top: 18, gutter: 0)
                        ForEach(inLineWorks) { work in
                            ledgerRow(work)
                                .environment(\.ledgerPositionNumber, queuePosition(of: work))
                        }
                    }
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: subjectPalette)
        #if os(iOS)
            .environment(\.editMode, dragEditMode)
        #endif
    }

    /// The header block and `headerDetails` as `detailedList`'s first rows;
    /// `compactGrid` stacks the same two views in its `ScrollView` (a `List` and
    /// a `ScrollView` can't share one parent without one losing what it needs —
    /// swipe actions here, a `LazyVGrid` there).
    private var subjectHeaderSection: some View {
        Section {
            subjectHeader
                .pageBodyRow(top: 20, gutter: 0)
            if isSelecting {
                // Artboard 1bg's select-mode status line replaces the meta line
                // and filter rail — narrowing to one work at a time isn't what
                // selection mode is for, and "N selected" already lives on the
                // toolbar's own "N selected" / Select All pair.
                selectionStatusRow
                    .pageBodyRow(top: 12, gutter: SubjectMetrics.gutter)
            } else {
                headerDetails
                    .pageBodyRow(top: 8, gutter: 0)
            }
        }
    }

    /// One `QueueHeaderDetails` shared by `detailedList` and `compactGrid`.
    private var headerDetails: some View {
        QueueHeaderDetails(
            works: works,
            preservedIDs: Set(preservedWorks.map(\.id)),
            tags: selectedQueue?.tags ?? [],
            palette: subjectPalette,
            quickFilter: $quickFilter,
            onAddTag: { showingQueueTags = true }
        ) {
            if filters.hasActiveFilters { filterChipRail }
        }
    }

    private var inLineHeader: some View {
        QueueInLineHeader(count: inLineWorks.count, mode: $displayMode)
    }

    private var selectionStatusRow: some View {
        QueueSelectionStatusRow(
            queueName: selectedQueue?.displayName ?? "Queue",
            selectedCount: selection.count,
            total: works.count
        )
    }

    /// 1h's grid: "Up next stays a ringed row either way", so the front of the
    /// queue is a standalone ledger row on `WorkLedgerCardBackground` (the
    /// card `.cardRow` paints inside a `List`) and In line is the cover grid.
    /// Reordering drops the split: a drag has to reach every work, Up next too.
    private var compactGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                subjectHeader.padding(.top, 20)
                if isSelecting {
                    selectionStatusRow
                        .padding(.horizontal, SubjectMetrics.gutter)
                } else {
                    headerDetails
                }
                if isReordering || isSelecting {
                    SectionRuleHeader(title: "Works", count: compactDisplayedWorks.count)
                    coverGrid(compactDisplayedWorks)
                } else {
                    if let upNextWork {
                        SectionRuleHeader(title: "Up Next")
                        SensitiveWorkRow(
                            work: upNextWork,
                            openMode: .reader,
                            isSelecting: isSelecting,
                            isSelected: selection.contains(upNextWork.id),
                            onToggleSelection: { toggleSelection(upNextWork) },
                            presentation: .ledger,
                            usesInlineNavigation: true,
                            contentInsets: EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)
                        )
                        .background(WorkLedgerCardBackground(work: upNextWork))
                        .padding(.horizontal, 16)
                    }
                    if !inLineWorks.isEmpty {
                        inLineHeader
                        coverGrid(inLineWorks)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .subjectScreenWash(palette: subjectPalette)
    }

    private func coverGrid(_ gridWorks: [SavedWork]) -> some View {
        LazyVGrid(columns: compactGridColumns, spacing: CarouselCardMetrics.compactGridSpacing) {
            ForEach(gridWorks) { work in
                compactCard(work)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func compactCard(_ work: SavedWork) -> some View {
        if isSelecting || isReordering, let queue = selectedQueue {
            // 1bg: while selecting, the handle stays live beside the selection
            // bubble, which owns the top-trailing corner.
            ZStack(alignment: isSelecting ? .topLeading : .topTrailing) {
                Group {
                    if isSelecting {
                        SensitiveWorkCoverCard(
                            work: work,
                            isSelecting: true,
                            isSelected: selection.contains(work.id),
                            onToggleSelection: { toggleSelection(work) }
                        )
                    } else {
                        SensitiveWorkCoverCard(work: work)
                            .allowsHitTesting(false)
                    }
                }
                .opacity(draggedWorkID == work.id ? 0.4 : 1)
                if isDragLive {
                    dragHandle(for: work)
                }
            }
            .onDrop(of: [.text], delegate: WorkReorderDropDelegate(
                target: work,
                works: works,
                draggedWorkID: $draggedWorkID,
                pendingOrder: $pendingCompactOrder,
                queue: queue,
                context: context
            ))
            .accessibilityActions {
                if isDragLive {
                    Button("Move Up") { moveWork(work, toIndex: currentIndex(of: work) - 1) }
                    Button("Move Down") { moveWork(work, toIndex: currentIndex(of: work) + 1) }
                    Button("Move to Top") { moveWork(work, toIndex: 0) }
                    Button("Move to Bottom") { moveWork(work, toIndex: works.count - 1) }
                }
            }
        } else {
            NavigationLink(value: LocalWorkDestination.reader(work)) {
                SensitiveWorkCoverCard(work: work)
            }
            .buttonStyle(.plain)
            .localWorkContextMenu(work: work)
        }
    }

    private func dragHandle(for work: SavedWork) -> some View {
        ReorderHandleView()
            .padding(6)
            .onDrag {
                draggedWorkID = work.id
                return NSItemProvider(object: work.id.uuidString as NSString)
            }
            .minimumHitTarget(28)
    }

    // MARK: - Toolbar (manage surface)

    @ToolbarContentBuilder
    private var manageToolbar: some ToolbarContent {
        if !works.isEmpty {
            if isReordering {
                ToolbarItem(placement: .primaryAction) {
                    Button { setReordering(false) } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                }
            } else if isSelecting {
                ToolbarItem(placement: .confirmationAction) {
                    SelectAllButton(allSelected: allSelected, action: toggleSelectAll)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .bottomBar) { bulkActionBar }
                #else
                ToolbarItemGroup(placement: .primaryAction) { bulkActionBar }
                #endif
            } else {
                ActionToolbar(items: [
                    AnyView(addWorksButton),
                    AnyView(FilterButton(
                        filtersActive: filters.hasActiveFilters,
                        showingFilters: $showingFilters,
                        filterHelp: "Filter the works in this queue",
                        onClearFilters: { filters = LibraryFilters() }
                    )),
                    AnyView(WorkListMoreMenu {
                        Button {
                            setReordering(true)
                        } label: {
                            Label("Reorder", systemImage: "arrow.up.arrow.down")
                        }
                        .disabled(isNarrowed)
                        .help(isNarrowed
                            ? "Clear filters to reorder"
                            : "Reorder works in this queue")
                        Button {
                            isSelecting = true
                        } label: {
                            Label("Select", systemImage: "checklist")
                        }
                        DisplayModeMenuPicker(mode: $displayMode)
                        Divider()
                        queueMenuItems
                    })
                ])
            }
        } else if selectedQueue != nil {
            // Empty queue: still allow adding works, seeing its details, and
            // (custom only) renaming/deleting it, from the toolbar.
            ActionToolbar(items: [
                AnyView(addWorksButton),
                AnyView(WorkListMoreMenu { queueMenuItems })
            ])
        }

        // Not nested in the branches above: the switcher must stay reachable even
        // from an empty queue (it's how you get to a *different* queue). regularLayout
        // (iPad/Mac) never renders this — it has its own sidebar list instead.
        #if os(iOS)
        if horizontalSizeClass != .regular, !isSelecting, !isReordering {
            ToolbarItemGroup(placement: .bottomBar) {
                switcherBarContent
            }
        }
        #endif
    }

    @ViewBuilder
    private var addWorksSheet: some View {
        if let queue = selectedQueue {
            AddLibraryWorksSheet(
                destinationName: queue.displayName,
                scopeName: "queue",
                candidates: { ReadingQueueService.appendCandidates(from: $0, notIn: queue) },
                onAdd: { ReadingQueueService.append($0, to: queue, in: context) }
            )
        }
    }

    /// 1h: "an accent-filled + for adding works" in the page's glass chrome.
    private var addWorksButton: some View {
        Button {
            showingAddWorks = true
        } label: {
            Label("Add Works", systemImage: "plus")
        }
        .buttonStyle(.glassProminent)
        .tint(subjectPalette.accent)
        .help("Add works from your library")
    }

    private var bulkActionBar: some View {
        ScopedRemovalBulkActionBar(
            selectedWorks: selectedWorks,
            removeLabel: "Remove from Queue",
            scopeName: "queue",
            onRemove: bulkRemove,
            onDone: exitSelectMode,
            showsQueueActions: true
        )
    }

    /// Queue Details, and Rename / Delete for a custom queue — the same items
    /// whether or not the queue has works.
    @ViewBuilder
    private var queueMenuItems: some View {
        Button {
            showingQueueDetails = true
        } label: {
            Label("Queue Details", systemImage: "info.circle")
        }
        if let queue = selectedQueue, queue.kind == .custom {
            Button {
                renameText = queue.name
                showingRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Queue", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func resolveInitialSelection() {
        ReadingQueueService.ensureSavedForLaterQueue(in: context)
        guard selectedQueueID == nil else { return }
        if let initialQueueID {
            selectedQueueID = initialQueueID
            lastSelectedIDRaw = initialQueueID.uuidString
        } else if let saved = UUID(uuidString: lastSelectedIDRaw),
                  orderedQueues.contains(where: { $0.id == saved }) {
            selectedQueueID = saved
        } else {
            selectedQueueID = orderedQueues.first?.id
        }
    }

    func select(_ queue: ReadingQueue) {
        // Leaving mid-select/reorder on another queue would leave dangling state.
        exitSelectMode()
        setReordering(false)
        filters = LibraryFilters()
        quickFilter = .all
        selectedQueueID = queue.id
        lastSelectedIDRaw = queue.id.uuidString
        showingSwitcher = false
    }

    func createQueue(_ options: NewQueueOptions) {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hue = newQueueHue
        newQueueName = ""
        newQueueHue = nil
        showingNewQueue = false
        let queue = ReadingQueueService.createQueue(
            named: trimmed,
            hue: hue,
            keepsWorksOffline: options.keepsWorksOffline,
            seededFrom: options.seed,
            tagNames: options.tagNames,
            in: context
        )
        select(queue)
    }

    private func setReordering(_ active: Bool) {
        isReordering = active
        draggedWorkID = nil
        pendingCompactOrder = nil
    }

    /// Nil while no drag is live, so the list offers no handles.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard isDragLive else { return nil }
        return { moveWorks(from: $0, to: $1) }
    }

    #if os(iOS)
    /// Derived, not stored: edit mode is exactly "a drag is live", which
    /// select mode now turns on too (1bg).
    private var dragEditMode: Binding<EditMode> {
        .constant(isDragLive ? .active : .inactive)
    }
    #endif

    private func moveWorks(from source: IndexSet, to destination: Int) {
        guard isDragLive, let queue = selectedQueue else { return }
        var ids = works.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        ReadingQueueService.reorder(ids, in: queue, context: context)
    }

    private func currentIndex(of work: SavedWork) -> Int {
        works.firstIndex(where: { $0.id == work.id }) ?? 0
    }

    private func moveWork(_ work: SavedWork, toIndex newIndex: Int) {
        guard isDragLive,
              let queue = selectedQueue,
              let (from, to) = ReadingQueueService.moveOffsets(
                  currentIndex: currentIndex(of: work),
                  requestedIndex: newIndex,
                  count: works.count
              )
        else { return }
        var ids = works.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        ReadingQueueService.reorder(ids, in: queue, context: context)
    }

    private func deleteSelectedQueue() {
        guard let queue = selectedQueue else { return }
        PreservedWorkService.softDelete(queue, in: context)
        exitSelectMode()
        setReordering(false)
        // Prefer staying on the browser if other queues remain.
        if let next = orderedQueues.first(where: { $0.id != queue.id }) {
            select(next)
        } else {
            dismiss()
        }
    }

    private func toggleSelectAll() {
        selection = allSelected ? [] : Set(works.map(\.id))
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
        draggedWorkID = nil
        pendingCompactOrder = nil
    }

    private func bulkRemove() {
        guard let queue = selectedQueue else { return }
        for work in selectedWorks {
            ReadingQueueService.removeFromQueue(work, from: queue, in: context)
        }
    }
}

// MARK: - Shared byte helpers (artboards 1h, 1i)

/// One work's EPUB size on disk, 0 if the file is missing. `ReadingQueueStorageView`
/// (`ReadingQueues.swift`) has its own private copy of this same lookup scoped to
/// every queued work across every queue; this one is scoped to a single queue
/// (here) or every queue's own row (the 1i organizer), so it stays a free function
/// rather than a method either screen would have to reach across files for.
func queueWorkFileSize(_ url: URL) -> Int64 {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values?.fileSize ?? 0)
}

func queueByteCountString(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
