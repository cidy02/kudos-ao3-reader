import Foundation
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Navigation route for the Reading Queues carousel's "See all" destination.
struct AllReadingQueuesDestination: Hashable {}

// MARK: - Cards

struct ReadingQueueCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let queue: ReadingQueue

    // Memberships of a soft-deleted work survive (so restoring it re-joins its
    // queues), but the work itself belongs to Recently Deleted, not this card.
    private var works: [SavedWork] {
        queue.memberships.compactMap(\.work).filter { !$0.isPendingDeletion }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            tile
                .frame(width: CarouselCardMetrics.width, height: CarouselCardMetrics.height)
            Text(queue.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("\(works.count) work\(works.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: CarouselCardMetrics.width, alignment: .leading)
    }

    private var tile: some View {
        let hue = CoverArt.hue(for: queue.displayName)
        return RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                    .fill(themeManager.appTheme.carouselQueueTint(hue: hue))
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: queue.kind == .savedForLater ? "bookmark.fill" : "list.bullet.rectangle")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tint)
                    Spacer()
                    Text(queue.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
    }
}

struct NewReadingQueueCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(width: CarouselCardMetrics.width, height: CarouselCardMetrics.height)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            Text("New Queue")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("Tap to create")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: CarouselCardMetrics.width, alignment: .leading)
    }
}

// MARK: - Queue detail

struct ReadingQueueDetailView: View {
    let queue: ReadingQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var expandAll = false
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    @State private var displayMode: WorkListDisplayMode = .detailed
    // EditMode is iOS-only (matches LibraryView's own selection state), so it drives
    // the native List reorder grip in detailed mode there; macOS falls back to a
    // plain Bool. `isReordering`/`setReordering(_:)` are the single cross-platform
    // source of truth both layouts read.
    #if os(iOS)
    @State private var reorderEditMode: EditMode = .inactive
    #else
    @State private var isReorderingMac = false
    #endif
    /// Tracks the in-flight refresh so it can be cancelled if the user switches tabs
    /// (see `cancelRefreshOnTabChange`) — a queue can hold a large number of works.
    @State private var refreshTask: Task<Void, Never>?
    /// Which card is currently mid-drag in the compact grid — read by
    /// `WorkReorderDropDelegate` rather than decoding the drag payload asynchronously.
    @State private var draggedWorkID: UUID?
    /// The compact grid's live drag-preview order, written by
    /// `WorkReorderDropDelegate.dropEntered` and committed to `ReadingQueueService`
    /// only in `performDrop` — see that type's doc comment for why (A6-F1).
    @State private var pendingCompactOrder: [UUID]?

    private var isReordering: Bool {
        #if os(iOS)
        reorderEditMode.isEditing
        #else
        isReorderingMac
        #endif
    }

    private func setReordering(_ active: Bool) {
        #if os(iOS)
        reorderEditMode = active ? .active : .inactive
        #else
        isReorderingMac = active
        #endif
        // A drag abandoned mid-gesture (e.g. tapping Done before releasing) only
        // clears draggedWorkID/pendingCompactOrder on a completed drop — reset both
        // here too so neither a stale id nor a discarded preview leaks into the next
        // reorder-mode entry.
        draggedWorkID = nil
        pendingCompactOrder = nil
    }

    // Soft-deleted works keep their membership rows (restore re-joins them here)
    // but render only in Recently Deleted until then.
    private var works: [SavedWork] {
        ReadingQueueService.orderedWorks(in: queue)
    }

    private var visibleWorks: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: works) : works
    }

    /// While reordering, filters step aside — .onMove and the drag handle both need
    /// index-stability against the same unfiltered array `reorder(_:)` writes back.
    private var displayedWorks: [SavedWork] {
        isReordering ? works : visibleWorks
    }

    /// `compactGrid`'s order: `pendingCompactOrder` while a drag is live, otherwise
    /// the same `displayedWorks` the detailed list also reads. See
    /// `WorkReorderDropDelegate`'s doc comment for why the live preview is kept in
    /// local state instead of writing straight through to `ReadingQueueService` (A6-F1).
    private var compactDisplayedWorks: [SavedWork] {
        guard let pendingCompactOrder else { return displayedWorks }
        // uniquingKeysWith, not uniqueKeysWithValues: ReadingQueueService.reorder builds
        // this same work-id→membership map defensively for duplicate memberships
        // pointing at the same work; this render-path map shouldn't be less defensive
        // than the service feeding it — uniqueKeysWithValues traps at runtime instead.
        let byID = Dictionary(works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pendingCompactOrder.compactMap { byID[$0] }
    }

    var body: some View {
        Group {
            if works.isEmpty {
                ContentUnavailableView {
                    Label(queue.displayName, systemImage: "bookmark")
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
                    let task = Task { _ = await WorkMetadataRefresh.refresh(visibleWorks, in: context) }
                    refreshTask = task
                    await task.value
                }
                .cancelRefreshOnTabChange($refreshTask)
                .overlay {
                    if visibleWorks.isEmpty, !isReordering {
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
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle(queue.displayName)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .inspector(isPresented: $showingFilters) {
                LibraryFilterPanel(filters: $filters, works: works, userTagNames: allTags.map(\.name))
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                #if os(iOS)
                    .presentationDragIndicator(.visible)
                #endif
            }
            .toolbar {
                if !works.isEmpty {
                    if isReordering {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Done") { setReordering(false) }
                        }
                    } else {
                        ActionToolbar {
                            FilterButton(filtersActive: filters.hasActiveFilters,
                                         showingFilters: $showingFilters,
                                         filterHelp: "Filter the works in this queue",
                                         onClearFilters: { filters = LibraryFilters() })
                            WorkListMoreMenu {
                                Button {
                                    setReordering(true)
                                } label: {
                                    Label("Reorder", systemImage: "arrow.up.arrow.down")
                                }
                                .disabled(filters.hasActiveFilters)
                                .help(filters.hasActiveFilters
                                    ? "Clear filters to reorder"
                                    : "Reorder works in this queue")
                                DisplayModeMenuPicker(mode: $displayMode)
                                // Compact cards don't expand/collapse — only detailed rows do.
                                if displayMode == .detailed {
                                    ExpandAllMenuItem(expandAll: $expandAll)
                                }
                                if queue.kind == .custom {
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
                            }
                        }
                    }
                }
            }
            .alert("Rename Queue", isPresented: $showingRename) {
                TextField("Name", text: $renameText)
                Button("Save") {
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
                "Delete “\(queue.displayName)”?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The queue moves to Recently Deleted for 90 days, with everything in it "
                        + "intact. Works stay in Kudos either way."
                )
            }
    }

    private var detailedList: some View {
        List {
            ForEach(displayedWorks) { work in
                SensitiveWorkRow(work: work, expandAll: expandAll, openMode: .reader)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            ReadingQueueService.removeFromQueue(work, from: queue, in: context)
                        } label: {
                            Label("Remove from Queue", systemImage: "minus.circle")
                        }
                    }
                    // moveDisabled removes the drag affordance itself outside reorder
                    // mode — on macOS, .onMove has no EditMode gate the way iOS does,
                    // so a List with an unconditional .onMove is draggable at all
                    // times regardless of the Reorder toggle otherwise.
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

    /// Apple Books-style two-up grid — the same cover cards every carousel already
    /// uses, wrapping down the page instead of scrolling horizontally.
    private var compactGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(compactDisplayedWorks) { work in
                    compactCard(work)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func compactCard(_ work: SavedWork) -> some View {
        if isReordering {
            // onDrop is attached to the ZStack container, not the card itself — the
            // card's own allowsHitTesting(false) (which suppresses a blurred work's
            // reveal-tap so it can't fire underneath a drag) would otherwise also
            // swallow drop-target hit-testing if onDrop were chained directly onto
            // the disabled view, breaking the whole drag gesture.
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
            // VoiceOver can't perform the drag gesture above, so this is the only way
            // a VoiceOver user can reorder the compact grid (the detailedList's List +
            // EditMode reorder control is natively accessible and needs no equivalent).
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

    /// The compact grid's drag source — split out from `compactCard` since the
    /// combined overlay/onDrag/onDrop expression was too complex for the type
    /// checker to diagnose in one go.
    private func dragHandle(for work: SavedWork) -> some View {
        ReorderHandleView()
            .padding(6)
            .onDrag {
                draggedWorkID = work.id
                return NSItemProvider(object: work.id.uuidString as NSString)
            }
            // Geometrically a no-op today: ReorderHandleView is already 28×28pt and
            // the surrounding .padding(6) already grows the drag source to ~40pt in
            // each dimension (well above this 28pt floor), so this doesn't enlarge
            // anything — it's an explicit, self-documenting minimum kept in case the
            // padding above ever shrinks, plus the corner-coverage .contentShape it
            // adds. The actual UI-3/A9-F2 fix for this handle is the 4
            // .accessibilityAction custom actions on the reordering-mode card below
            // (VoiceOver can't perform the drag this handle starts at all), not this.
            .minimumHitTarget(28)
    }

    /// `.onMove`'s indices are relative to `displayedWorks`, which is the unfiltered
    /// `works` while reordering — the same array `reorder(_:)` writes back to. Guards
    /// on `isReordering` itself (not just the optional `.onMove` above) as defense in
    /// depth against any platform where the drag affordance isn't fully gated.
    private func moveWorks(from source: IndexSet, to destination: Int) {
        guard isReordering else { return }
        var ids = works.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        ReadingQueueService.reorder(ids, in: queue, context: context)
    }

    private func currentIndex(of work: SavedWork) -> Int {
        works.firstIndex(where: { $0.id == work.id }) ?? 0
    }

    /// The compact grid's VoiceOver-accessible alternative to the drag handle above —
    /// same `toOffset` direction convention `WorkReorderDropDelegate.dropEntered`
    /// already uses (`+1` only when moving forward), and the same `reorder(_:)` write
    /// path both existing reorder mechanisms funnel through. Clamping `newIndex` makes
    /// this a safe no-op at either boundary (already first/last), so every accessibility
    /// action can be attached unconditionally.
    private func moveWork(_ work: SavedWork, toIndex newIndex: Int) {
        guard isReordering,
              let (from, to) = ReadingQueueService.moveOffsets(
                  currentIndex: currentIndex(of: work), requestedIndex: newIndex, count: works.count
              )
        else { return }
        var ids = works.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        ReadingQueueService.reorder(ids, in: queue, context: context)
    }

    private func deleteQueue() {
        PreservedWorkService.softDelete(queue, in: context)
        dismiss()
    }
}

/// Live-reorders as the drag crosses into each card's drop target, purely from
/// local state — the drag payload itself is never decoded back, which keeps this
/// synchronous and avoids `NSItemProvider` async-decode pitfalls for what is always
/// a same-app-only reorder. `dropEntered` writes only `pendingOrder` (plain local
/// state); the SwiftData write is deferred to `performDrop`. An earlier version
/// called `ReadingQueueService.reorder(_:)` straight from `dropEntered` on every
/// drag-over. The actual failure wasn't the resulting SwiftUI re-render by itself —
/// this type's ForEach already re-renders on every `pendingOrder` write today, and
/// that's fine, because `SavedWork` identities stay stable across a plain local-array
/// reorder. What broke the drag was that call's `context.saveBestEffort` writing
/// `queue.memberships` — a SwiftData relationship this screen *observes* — which
/// invalidates the owning `@Model` and tore down the OS drag session mid-gesture, not
/// merely rebuilding views under it. That's the reproduced failure behind A6-F1
/// (owner-confirmed broken): the drag visibly starts but never completes, and nothing
/// is ever persisted. A future edit must not reintroduce any observed-model write
/// inside `dropEntered` — only `performDrop`, once the gesture has actually ended, is
/// safe for that.
private struct WorkReorderDropDelegate: DropDelegate {
    let target: SavedWork
    let works: [SavedWork]
    @Binding var draggedWorkID: UUID?
    @Binding var pendingOrder: [UUID]?
    let queue: ReadingQueue
    let context: ModelContext

    /// What this drag is currently reordering relative to: the in-progress preview
    /// if this is a continuation of the same gesture (it already crossed at least
    /// one other card), otherwise the persisted order the drag started from.
    private var baseOrder: [UUID] {
        pendingOrder ?? works.map(\.id)
    }

    func dropEntered(info: DropInfo) {
        guard let draggedWorkID else { return }
        pendingOrder = ReadingQueueService.reorderedIDs(base: baseOrder, moving: draggedWorkID, over: target.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        // Persist only when the drag actually changed the order. `reorderedIDs` is a
        // no-op for a self-hover (which fires at drag start, over the source card's
        // own drop target) and for a cross-and-return, so `pendingOrder` can be
        // non-nil yet equal to the stored order; committing that would rewrite every
        // `sortOrderInQueue`, flip all memberships to `.pending` for sync, and hit
        // disk for a drag that moved nothing. `works` is unmutated during the gesture
        // (the whole point of deferring the write), so it's still the pre-drag order.
        if let pendingOrder, pendingOrder != works.map(\.id) {
            ReadingQueueService.reorder(pendingOrder, in: queue, context: context)
        }
        pendingOrder = nil
        draggedWorkID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Queue storage

struct ReadingQueueStorageView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var works: [SavedWork]
    @State private var pendingQueueRemoval: SavedWork?

    private var queuedWorks: [SavedWork] {
        works.filter(\.isQueuedForLater)
    }

    private var preservedWorks: [SavedWork] {
        queuedWorks.filter { work in
            work.hasEPUB && FileManager.default.fileExists(atPath: work.fileURL.path)
        }
    }

    private var queueOnlyWorks: [SavedWork] {
        queuedWorks.filter(\.isQueueOnlyWork)
    }

    private var preservedByteCount: Int64 {
        preservedWorks.reduce(0) { total, work in
            total + fileSize(for: work.fileURL)
        }
    }

    var body: some View {
        List {
            Group {
                Section("Summary") {
                    LabeledContent("Queued Works", value: queuedWorks.count.formatted())
                    LabeledContent("Queue-only Works", value: queueOnlyWorks.count.formatted())
                    LabeledContent("Preserved EPUBs", value: preservedWorks.count.formatted())
                    LabeledContent("Preserved Storage", value: byteString(preservedByteCount))
                }

                Section {
                    if preservedWorks.isEmpty {
                        Text("No queued EPUBs are currently stored on this device.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(preservedWorks) { work in
                            preservedWorkRow(work)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        pendingQueueRemoval = work
                                    } label: {
                                        Label("Remove from Queues", systemImage: "minus.circle")
                                    }
                                    Button {
                                        WorkLifecycle.setSaved(work, true, in: context)
                                    } label: {
                                        Label("Save to Keep", systemImage: "bookmark")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button {
                                        WorkLifecycle.setSaved(work, true, in: context)
                                    } label: {
                                        Label("Save to Keep", systemImage: "bookmark")
                                    }
                                    Button(role: .destructive) {
                                        pendingQueueRemoval = work
                                    } label: {
                                        Label("Remove from Reading Queues", systemImage: "minus.circle")
                                    }
                                }
                        }
                    }
                } header: {
                    Text("Preserved EPUBs")
                } footer: {
                    Text("Removing a work here only removes queue membership. Saved or favorited works stay "
                        + "in Kudos; queue-only works are removed when no queues remain.")
                }
            }
            .appThemedRows()
        }
        .appThemedScroll()
        .navigationTitle("Queue Storage")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .confirmationDialog(
                "Remove from reading queues?",
                isPresented: Binding(
                    get: { pendingQueueRemoval != nil },
                    set: { if !$0 { pendingQueueRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(queueRemovalButtonTitle, role: .destructive) {
                    if let work = pendingQueueRemoval {
                        removeFromQueues(work)
                    }
                    pendingQueueRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingQueueRemoval = nil
                }
            } message: {
                Text(queueRemovalMessage)
            }
    }

    private func preservedWorkRow(_ work: SavedWork) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: work.isInSavedForLaterQueue ? "bookmark.fill" : "list.bullet.rectangle")
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !work.author.isEmpty {
                    AO3AuthorBylineView(
                        displayText: work.author,
                        identities: work.verifiedAuthorIdentities,
                        includesBy: false,
                        font: .caption,
                        compact: true
                    )
                }
                Text(byteString(fileSize(for: work.fileURL)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if work.isQueueOnlyWork {
                Text("Queue")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var queueRemovalMessage: String {
        guard let work = pendingQueueRemoval else { return "" }
        if work.isSaved || work.isFavorite {
            return "This keeps the work in your Library and only removes its reading queue membership."
        }
        return "This queue-only work will be removed from Kudos if it has no remaining queues."
    }

    private var queueRemovalButtonTitle: String {
        guard let work = pendingQueueRemoval else { return "Remove from Queues" }
        return work.isQueueOnlyWork ? "Remove Queues & Delete" : "Remove from Queues"
    }

    private func removeFromQueues(_ work: SavedWork) {
        ReadingQueueService.removeFromAllQueuesAndDeleteIfQueueOnly(work, in: context)
    }

    private func fileSize(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Add to queue

struct AddToQueueView: View {
    let works: [SavedWork]

    init(work: SavedWork) {
        works = [work]
    }

    init(works: [SavedWork]) {
        self.works = works
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var queues: [ReadingQueue]
    @State private var newName = ""
    @State private var workingQueueIDs: Set<UUID> = []
    @State private var includeSeries = false
    @State private var checkingSeriesPreview = false
    @State private var seriesPrompt: ReadingQueueService.SeriesPreservationPrompt?
    @State private var preservingSeries = false
    @State private var seriesResult: ReadingQueueService.SeriesPreservationResult?
    @State private var seriesTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("New queue", text: $newName)
                            .onSubmit(create)
                        Button("Add", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    ForEach(sortedQueues) { queue in
                        Button {
                            toggle(queue)
                        } label: {
                            HStack {
                                Label(queue.displayName, systemImage: queueSymbol(queue))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if workingQueueIDs.contains(queue.id) {
                                    ProgressView()
                                } else if isMember(queue) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("In this queue")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Queues")
                } footer: {
                    Text("Queue membership keeps a local EPUB available without marking the work as saved.")
                }

                if hasSeries {
                    Section {
                        Toggle("Also add works from this AO3 series", isOn: $includeSeries)

                        if includeSeries {
                            if checkingSeriesPreview {
                                HStack {
                                    ProgressView()
                                    Text("Checking series size…")
                                        .foregroundStyle(.secondary)
                                }
                            } else if let seriesPrompt {
                                Text(seriesPrompt.message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                preserveSelectedSeries()
                            } label: {
                                HStack {
                                    Label("Add Series to Selected Queues", systemImage: "square.stack.3d.up")
                                    Spacer()
                                    if preservingSeries { ProgressView() }
                                }
                            }
                            .disabled(preservingSeries || selectedQueuesForSeries.isEmpty)

                            if preservingSeries {
                                Button(role: .cancel) {
                                    cancelSeriesPreservation()
                                } label: {
                                    Label("Cancel Series Addition", systemImage: "xmark.circle")
                                }
                            }

                            if let seriesResult {
                                Text(seriesCompletionText(seriesResult))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Series")
                    } footer: {
                        Text("Series works are added only after you tap the series action. Requests are paced.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add to Queue")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task {
                    ReadingQueueService.ensureSavedForLaterQueue(in: context)
                }
                .onChange(of: includeSeries) { _, isEnabled in
                    if isEnabled {
                        Task { await loadSeriesPreview() }
                    } else {
                        seriesPrompt = nil
                        seriesResult = nil
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private var sortedQueues: [ReadingQueue] {
        queues.sorted {
            if $0.kind != $1.kind { return $0.kind == .savedForLater }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.displayName < $1.displayName
        }
    }

    private func isMember(_ queue: ReadingQueue) -> Bool {
        works.allSatisfy { work in work.queueMemberships.contains { $0.queue?.id == queue.id } }
    }

    private func queueSymbol(_ queue: ReadingQueue) -> String {
        queue.kind == .savedForLater ? "bookmark" : "list.bullet.rectangle"
    }

    // Series preservation is anchored to a single AO3 series, so it only applies
    // when this sheet is managing one work.
    private var soloWork: SavedWork? {
        works.count == 1 ? works[0] : nil
    }

    private var hasSeries: Bool {
        guard let soloWork else { return false }
        return URL(string: soloWork.seriesURL) != nil && !soloWork.seriesURL.isEmpty
    }

    private var selectedQueuesForSeries: [ReadingQueue] {
        sortedQueues.filter(isMember)
    }

    private func loadSeriesPreview() async {
        guard includeSeries, let soloWork, let url = URL(string: soloWork.seriesURL) else { return }
        checkingSeriesPreview = true
        do {
            let preview = try await AO3Client.shared.seriesPreview(seriesURL: url)
            seriesPrompt = ReadingQueueService.seriesPrompt(for: preview, threshold: 5)
        } catch {
            seriesPrompt = ReadingQueueService.seriesPrompt(for: nil, threshold: 5, previewFailed: true)
        }
        checkingSeriesPreview = false
    }

    private func preserveSelectedSeries() {
        guard !preservingSeries, let soloWork, URL(string: soloWork.seriesURL) != nil else { return }
        let queues = selectedQueuesForSeries
        guard !queues.isEmpty else { return }
        preservingSeries = true
        seriesResult = nil
        seriesTask = Task { @MainActor in
            let result: ReadingQueueService.SeriesPreservationResult = if let seriesPrompt,
                                                                          seriesPrompt.canUsePreviewForPreservation,
                                                                          let summaries = seriesPrompt.preview?.works {
                await ReadingQueueService.preserveSeries(
                    summaries,
                    to: queues,
                    in: context,
                    progress: { seriesResult = $0 }
                )
            } else {
                await ReadingQueueService.preserveSeries(
                    anchoredAt: soloWork,
                    to: queues,
                    in: context,
                    progress: { seriesResult = $0 }
                )
            }
            seriesResult = result
            preservingSeries = false
            seriesTask = nil
        }
    }

    private func cancelSeriesPreservation() {
        seriesTask?.cancel()
        preservingSeries = false
    }

    private func toggle(_ queue: ReadingQueue) {
        if isMember(queue) {
            for work in works {
                ReadingQueueService.removeFromQueue(work, from: queue, in: context)
            }
            return
        }
        let nonMembers = works.filter { work in !work.queueMemberships.contains { $0.queue?.id == queue.id } }
        workingQueueIDs.insert(queue.id)
        Task {
            for work in nonMembers {
                _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
            }
            workingQueueIDs.remove(queue.id)
        }
    }

    private func seriesCompletionText(_ result: ReadingQueueService.SeriesPreservationResult) -> String {
        if preservingSeries, result.total > 0 {
            return "Adding \(result.completed) of \(result.total) series works…"
        }
        if result.cancelled > 0 {
            return "Series preservation cancelled. Added \(result.preserved) work"
                + "\(result.preserved == 1 ? "" : "s")."
        }
        if result.total == 0 { return "No series works were found." }
        let parts = result.summaryParts(verb: "added")
        return parts.isEmpty ? "Series works are already in the selected queues." : parts.joined(separator: ", ") + "."
    }

    private func create() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let queue = ReadingQueueService.createQueue(named: trimmed, in: context)
        newName = ""
        workingQueueIDs.insert(queue.id)
        Task {
            for work in works {
                _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
            }
            workingQueueIDs.remove(queue.id)
        }
    }
}
