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

    // MARK: Manage-surface state (formerly ReadingQueueDetailView)

    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    /// Pushes artboard 1h's "Queue details" screen — a restyle of what this
    /// screen's own overflow menu already does (rename, delete, see what's
    /// preserved), not a new destination's worth of new data.
    @State private var showingQueueDetails = false
    @State private var expandAll = false
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    /// Cover grid matches the prior browser default; switch to detailed via the menu.
    @State private var displayMode: WorkListDisplayMode = .compact
    #if os(iOS)
    @State private var reorderEditMode: EditMode = .inactive
    #else
    @State private var isReorderingMac = false
    #endif
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
        filters.hasActiveFilters ? filters.apply(to: works) : works
    }

    private var isReordering: Bool {
        #if os(iOS)
        reorderEditMode.isEditing
        #else
        isReorderingMac
        #endif
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
        let hue = selectedQueue.map { CoverArt.hue(for: $0.displayName) } ?? themeManager.scopeHue
        return themeManager.appTheme.subjectPalette(hue: hue)
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

    /// The finer breakdown under the header — spec 1h: "2 finished · 1 in
    /// progress · 9 unread · 9 of 12 kept offline". `SavedWork.readingState` is
    /// the app's one canonical reading-lifecycle partition (see its own doc
    /// comment), so this reads it rather than re-deriving finished/unread from
    /// `isFinished`/`hasEPUB` a second time.
    private var queueMetaLine: String? {
        guard !works.isEmpty else { return nil }
        let finished = works.filter { $0.readingState == .finished }.count
        let inProgress = works.filter { $0.readingState == .inProgress }.count
        let unread = works.filter { $0.readingState == .unread }.count
        let offline = preservedWorks.count == works.count
            ? "all \(works.count) kept offline"
            : "\(preservedWorks.count) of \(works.count) kept offline"
        return "\(finished) finished · \(inProgress) in progress · \(unread) unread · \(offline)"
    }

    /// The active-filters rail under the header (spec 1h's own dashed "+ Tag"
    /// chip is a queue-tag affordance this app has no data for — see the
    /// `ReadingQueueSettingsView` file note — so this reuses the Library's own
    /// filter rail/chip vocabulary instead of inventing a second, parallel
    /// quick-filter scheme next to the `LibraryFilters` this screen already has.
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
            kicker: "Library › Queues",
            title: selectedQueue?.displayName ?? "Reading Queues",
            subtitle: queueSubtitle,
            palette: subjectPalette
        )
    }

    /// Spec 1h splits a queue into "Up next" (the front of the queue) and "In
    /// line" (everything behind it) — real content, since `orderedWorks`
    /// already reflects the queue's own manual order (`sortOrderInQueue`).
    /// Both use `visibleWorks` (filters applied) rather than `displayedWorks`,
    /// since that split only ever renders while `!isReordering`.
    private var upNextWork: SavedWork? { visibleWorks.first }

    private var inLineWorks: [SavedWork] { Array(visibleWorks.dropFirst()) }

    private func ledgerRow(_ work: SavedWork) -> some View {
        SensitiveWorkRow(
            work: work,
            expandAll: expandAll,
            openMode: .reader,
            isSelecting: isSelecting,
            isSelected: selection.contains(work.id),
            onToggleSelection: { toggleSelection(work) },
            presentation: .ledger
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
        // `.subjectScreenWash` (applied inside `detailedList`/`compactGrid`) already
        // empties the navigation title and its background on iOS — the page states
        // its own name via `SubjectHeaderBlock` instead. macOS has no such wash
        // (`hidesNavigationBarChrome` is a no-op there) and still needs a real title
        // for its sidebar-detail window chrome.
        #if os(macOS)
            .navigationTitle(
                horizontalSizeClass == .regular
                    ? "Reading Queues"
                    : (selectedQueue?.displayName ?? "Reading Queues")
            )
        #endif
            .onAppear(perform: resolveInitialSelection)
            .sheet(isPresented: $showingNewQueue) { newQueueSheet }
            .navigationDestination(isPresented: $showingQueueDetails) {
                if let selectedQueue {
                    ReadingQueueSettingsView(queue: selectedQueue)
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
                        Button("Clear Filters") { filters = LibraryFilters() }
                    }
                }
            }
        }
    }

    private var detailedList: some View {
        List {
            if isReordering {
                // Flat and unsectioned, exactly as before the redesign: `.onMove`
                // only reorders within the `ForEach` it is attached to, so a drag
                // that should be able to promote any work into "Up next" needs one
                // `ForEach` over the whole queue, not two split across sections.
                ForEach(displayedWorks) { work in
                    SensitiveWorkRow(
                        work: work,
                        expandAll: expandAll,
                        openMode: .reader,
                        presentation: .ledger
                    )
                    .swipeActions(edge: .trailing) {
                        if let queue = selectedQueue {
                            Button(role: .destructive) {
                                ReadingQueueService.removeFromQueue(work, from: queue, in: context)
                            } label: {
                                Label("Remove from Queue", systemImage: "minus.circle")
                            }
                        }
                    }
                    .moveDisabled(!isReordering)
                }
                .onMove(perform: moveWorks)
                .cardRow()
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
                        SectionRuleHeader(title: "In Line", count: inLineWorks.count)
                            .pageBodyRow(top: 18, gutter: 0)
                        ForEach(inLineWorks) { work in
                            ledgerRow(work)
                        }
                    }
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: subjectPalette)
        #if os(iOS)
            .environment(\.editMode, $reorderEditMode)
        #endif
    }

    /// The header block, its finer tally line and the filter rail — the same
    /// three rows in both `detailedList` and `compactGrid`, each its own copy
    /// rather than a shared container, matching `LibrarySectionListView`'s own
    /// `subjectHeaderSection`/`compactGrid` split (a `List` and a `ScrollView`
    /// can't share one parent view without one of them losing what it needs —
    /// swipe actions here, a `LazyVGrid` there).
    private var subjectHeaderSection: some View {
        Section {
            subjectHeader
                .pageBodyRow(top: 20, gutter: 0)
            if let queueMetaLine {
                Text(queueMetaLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .pageBodyRow(top: 2, gutter: SubjectMetrics.gutter)
            }
            filterChipRail
                .pageBodyRow(top: 8, gutter: 0)
        }
    }

    // Kept as ONE grid rather than splitting an "Up next" row out above it the
    // way `detailedList` does: spec 1h's grid variant draws that row in the
    // full-width ledger shape, and that shape (`WorkLedgerRow`) only paints its
    // own card when told to draw standalone — `WorkRow(.ledger)` always says no,
    // because every other caller sits inside a `List` row whose own `.cardRow`
    // already paints it (see `WorkRow.ledgerRow`'s doc comment). Building a
    // second, parallel ledger-row assembly just for this one standalone row
    // wasn't worth it for what is otherwise a purely visual distinction — the
    // list variant already gives Up Next/In Line their real split, where
    // `List`'s own row background makes it free.
    private var compactGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                subjectHeader.padding(.top, 20)
                if let queueMetaLine {
                    Text(queueMetaLine)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, SubjectMetrics.headerGutter)
                }
                filterChipRail
                SectionRuleHeader(title: "Works", count: visibleWorks.count)
                LazyVGrid(columns: compactGridColumns, spacing: CarouselCardMetrics.compactGridSpacing) {
                    ForEach(compactDisplayedWorks) { work in
                        compactCard(work)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
        .subjectScreenWash(palette: subjectPalette)
    }

    @ViewBuilder
    private func compactCard(_ work: SavedWork) -> some View {
        if isSelecting {
            SensitiveWorkCoverCard(
                work: work,
                isSelecting: true,
                isSelected: selection.contains(work.id),
                onToggleSelection: { toggleSelection(work) }
            )
        } else if isReordering, let queue = selectedQueue {
            ZStack(alignment: .topTrailing) {
                SensitiveWorkCoverCard(work: work)
                    .opacity(draggedWorkID == work.id ? 0.4 : 1)
                    .allowsHitTesting(false)
                dragHandle(for: work)
            }
            .onDrop(of: [.text], delegate: WorkReorderDropDelegate(
                target: work,
                works: works,
                draggedWorkID: $draggedWorkID,
                pendingOrder: $pendingCompactOrder,
                queue: queue,
                context: context
            ))
            .accessibilityAction(named: "Move Up") { moveWork(work, toIndex: currentIndex(of: work) - 1) }
            .accessibilityAction(named: "Move Down") { moveWork(work, toIndex: currentIndex(of: work) + 1) }
            .accessibilityAction(named: "Move to Top") { moveWork(work, toIndex: 0) }
            .accessibilityAction(named: "Move to Bottom") { moveWork(work, toIndex: works.count - 1) }
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
                ToolbarItemGroup(placement: .bottomBar) {
                    ScopedRemovalBulkActionBar(
                        selectedWorks: selectedWorks,
                        removeLabel: "Remove from Queue",
                        scopeName: "queue",
                        onRemove: bulkRemove,
                        onDone: exitSelectMode
                    )
                }
                #else
                ToolbarItemGroup(placement: .primaryAction) {
                    ScopedRemovalBulkActionBar(
                        selectedWorks: selectedWorks,
                        removeLabel: "Remove from Queue",
                        scopeName: "queue",
                        onRemove: bulkRemove,
                        onDone: exitSelectMode
                    )
                }
                #endif
            } else {
                ActionToolbar(items: [
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
                        .disabled(filters.hasActiveFilters)
                        .help(filters.hasActiveFilters
                            ? "Clear filters to reorder"
                            : "Reorder works in this queue")
                        Button {
                            isSelecting = true
                        } label: {
                            Label("Select", systemImage: "checklist")
                        }
                        DisplayModeMenuPicker(mode: $displayMode)
                        if displayMode == .detailed {
                            ExpandAllMenuItem(expandAll: $expandAll)
                        }
                        Divider()
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
                    })
                ])
            }
        } else if let queue = selectedQueue {
            // Empty queue: still allow seeing its details, and (custom only)
            // renaming/deleting it, from the toolbar.
            ToolbarItem(placement: .primaryAction) {
                WorkListMoreMenu {
                    Button {
                        showingQueueDetails = true
                    } label: {
                        Label("Queue Details", systemImage: "info.circle")
                    }
                    if queue.kind == .custom {
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
            }
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
        selectedQueueID = queue.id
        lastSelectedIDRaw = queue.id.uuidString
        showingSwitcher = false
    }

    func createQueue() {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newQueueName = ""
        showingNewQueue = false
        let queue = ReadingQueueService.createQueue(named: trimmed, in: context)
        select(queue)
    }

    private func setReordering(_ active: Bool) {
        #if os(iOS)
        reorderEditMode = active ? .active : .inactive
        #else
        isReorderingMac = active
        #endif
        draggedWorkID = nil
        pendingCompactOrder = nil
    }

    private func moveWorks(from source: IndexSet, to destination: Int) {
        guard isReordering, let queue = selectedQueue else { return }
        var ids = works.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        ReadingQueueService.reorder(ids, in: queue, context: context)
    }

    private func currentIndex(of work: SavedWork) -> Int {
        works.firstIndex(where: { $0.id == work.id }) ?? 0
    }

    private func moveWork(_ work: SavedWork, toIndex newIndex: Int) {
        guard isReordering,
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
