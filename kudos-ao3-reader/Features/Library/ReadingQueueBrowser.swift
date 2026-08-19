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
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AO3AuthService.self) private var auth
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var allQueues: [ReadingQueue]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    /// Persists the last-open queue across visits to this screen, independent of
    /// which queue a Library carousel tap pre-selected this time.
    @AppStorage("library.readingQueueBrowser.lastSelectedID") private var lastSelectedIDRaw = ""
    @State private var selectedQueueID: UUID?
    @State private var showingSwitcher = false
    @State private var showingNewQueue = false
    @State private var newQueueName = ""

    // MARK: Manage-surface state (formerly ReadingQueueDetailView)

    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
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
    private var orderedQueues: [ReadingQueue] {
        allQueues.sorted {
            if $0.kind != $1.kind { return $0.kind == .savedForLater }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.displayName < $1.displayName
        }
    }

    private var selectedQueue: ReadingQueue? {
        guard let selectedQueueID else { return orderedQueues.first }
        return orderedQueues.first { $0.id == selectedQueueID } ?? orderedQueues.first
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
        .navigationTitle(
            horizontalSizeClass == .regular
                ? "Reading Queues"
                : (selectedQueue?.displayName ?? "Reading Queues")
        )
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .onAppear(perform: resolveInitialSelection)
            .sheet(isPresented: $showingNewQueue) { newQueueSheet }
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
            #if os(iOS)
            // Always hide the app tab bar: this screen owns bottom chrome (switcher
            // and/or select bulk bar). Select mode also needs the bottomBar free.
            .toolbar(.hidden, for: .tabBar)
            #endif
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
            .safeAreaInset(edge: .bottom) {
                if !isSelecting && !isReordering {
                    switcherBar
                }
            }
    }

    private var switcherBar: some View {
        HStack(spacing: 10) {
            Button { showingSwitcher = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(themeManager.effectiveTint)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("All Queues")
            // A direct .sheet, not .popover + .presentationCompactAdaptation(.sheet):
            // this bar only ever renders in compactLayout (iPhone) — regularLayout
            // (iPad/Mac) is a completely different sidebar List and never shows
            // this switcher at all — so there's no real popover behavior being
            // adapted from. Going through the popover-adaptation path was the
            // likely cause of two earlier attempts' clipped top chrome — see
            // switcherList's own doc comment for the full reasoning and the
            // working reference patterns (this file's newQueueSheet,
            // CommentsView's chapter picker) this now matches.
            .sheet(isPresented: $showingSwitcher) {
                switcherList
            }

            Button { showingSwitcher = true } label: {
                HStack(spacing: 6) {
                    queueGlyph(selectedQueue)
                    Text(selectedQueue?.displayName ?? "Reading Queues")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
            .accessibilityLabel("Switch Reading Queue")
            .accessibilityValue(selectedQueue?.displayName ?? "No queue selected")

            Button {
                newQueueName = ""
                showingNewQueue = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(themeManager.effectiveTint)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("New Queue")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var newQueueSheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $newQueueName)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
            }
            .navigationTitle("New Queue")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newQueueName = ""
                        showingNewQueue = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createQueue() }
                        .disabled(newQueueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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

            VStack(spacing: 0) {
                HStack {
                    Text(selectedQueue?.displayName ?? "Reading Queues")
                        .font(.title3.weight(.semibold))
                    Spacer()
                }
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 8)
                pageContent
            }
        }
    }

    // MARK: - Switcher list

    /// Same shape as this file's own `newQueueSheet` and CommentsView's chapter
    /// picker: a real `NavigationStack` + title, not a bare `List` handed to
    /// `.popover(...).presentationCompactAdaptation(.sheet)`, which is what
    /// clipped the sheet's top chrome in two earlier attempts here.
    ///
    /// Plain rows, not `.cardRow()`/`.cardList()`: the reader's own Contents/
    /// Bookmarks/Highlights sheet (`ReaderContentsSheet.chapterList`) — the
    /// reference this is matching — is a flat `.listStyle(.plain)` list with
    /// default hairline separators, not floating rounded cards.
    ///
    /// No `.appThemedRows()`/`.appThemedScroll()`, and no
    /// `.presentationBackground` override — three straight attempts at the
    /// latter (unset, `.regularMaterial`, `.ultraThinMaterial`) all looked
    /// equally opaque on device, which was the tell: the material was never
    /// the actual variable. `ReaderTheme.appBaseBackground`/
    /// `appElevatedBackground` (`Features/Reader/ReaderStyle.swift`) are `nil`
    /// **only** for `.light` — for Sepia/Dark/OLED they're real opaque
    /// colors, so `.appThemedScroll()`/`.appThemedRows()` were painting a
    /// solid `.background()`/`.listRowBackground()` over the whole list on
    /// this device's Dark/OLED theme, sitting on top of and completely
    /// masking whatever `.presentationBackground` material the sheet
    /// declared — confirmed root cause (root-caused via Gemini after three
    /// failed material-only attempts by hand). The reader sheet never
    /// applies these modifiers either, so dropping them here — Sepia
    /// included — matches the reference exactly rather than approximating
    /// it, and lets the system's own default sheet translucency show through
    /// unobstructed, the same as `readerSheet`.
    private var switcherList: some View {
        NavigationStack {
            List {
                ForEach(orderedQueues) { queue in
                    queueRow(queue)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Reading Queues")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showingSwitcher = false } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func queueRow(_ queue: ReadingQueue) -> some View {
        let workCount = ReadingQueueService.orderedWorks(in: queue).count
        let isSelected = queue.id == selectedQueue?.id
        return Button { select(queue) } label: {
            HStack(spacing: 10) {
                queueGlyph(queue)
                Text(queue.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(workCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue("\(workCount) work\(workCount == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func queueGlyph(_ queue: ReadingQueue?) -> some View {
        if let queue, queue.kind != .savedForLater {
            Circle()
                .fill(themeManager.appTheme.carouselQueueTint(hue: CoverArt.hue(for: queue.displayName)))
                .frame(width: 10, height: 10)
        } else {
            Image(systemName: WorkActionLabels.savedForLaterSymbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

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
            ForEach(displayedWorks) { work in
                SensitiveWorkRow(
                    work: work,
                    expandAll: expandAll,
                    openMode: .reader,
                    isSelecting: isSelecting,
                    isSelected: selection.contains(work.id),
                    onToggleSelection: { toggleSelection(work) }
                )
                .swipeActions(edge: .trailing) {
                    if !isSelecting, let queue = selectedQueue {
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
        }
        .cardList()
        #if os(iOS)
            .environment(\.editMode, $reorderEditMode)
        #endif
    }

    private var compactGrid: some View {
        ScrollView {
            LazyVGrid(columns: compactGridColumns, spacing: CarouselCardMetrics.compactGridSpacing) {
                ForEach(compactDisplayedWorks) { work in
                    compactCard(work)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
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
                        if let queue = selectedQueue, queue.kind == .custom {
                            Divider()
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
        } else if let queue = selectedQueue, queue.kind == .custom {
            // Empty custom queue: still allow rename/delete from the toolbar.
            ToolbarItem(placement: .primaryAction) {
                WorkListMoreMenu {
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

    private func select(_ queue: ReadingQueue) {
        // Leaving mid-select/reorder on another queue would leave dangling state.
        exitSelectMode()
        setReordering(false)
        filters = LibraryFilters()
        selectedQueueID = queue.id
        lastSelectedIDRaw = queue.id.uuidString
        showingSwitcher = false
    }

    private func createQueue() {
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
