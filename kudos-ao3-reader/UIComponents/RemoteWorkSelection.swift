import SwiftData
import SwiftUI

/// Work ids whose in-flight queue download is allowed to move `lastModifiedAt`
/// during a revived-swipe toast. `importEPUB` notes the stamp; Undo still
/// re-soft-deletes when that stamp is the latest write. Anything else that
/// moves the date (sync, restore, an edit) is not this swipe's import.
enum RevivedSwipeImport {
    private static var armed: Set<UUID> = []
    private static var importedModifiedAt: [UUID: Date] = [:]

    static func arm(_ id: UUID) {
        armed.insert(id)
    }

    static func disarm(_ id: UUID) {
        armed.remove(id)
        importedModifiedAt[id] = nil
    }

    static func noteIfArmed(_ work: SavedWork) {
        guard armed.contains(work.id) else { return }
        importedModifiedAt[work.id] = work.lastModifiedAt
    }

    static func lastWriteWasOwnImport(_ work: SavedWork, armedAt: Date) -> Bool {
        guard work.lastModifiedAt > armedAt else { return false }
        return importedModifiedAt[work.id] == work.lastModifiedAt
    }
}

/// Selection state + bulk actions shared by every remote-work list surface —
/// Browse's `FandomWorksView`/`TagWorksView`, `AuthorProfileView`'s works tab,
/// and Search results. Each host view owns one controller in `@State`, shows
/// `RemoteWorkSelectionToolbar` while selecting, and applies
/// `.remoteWorkSelectionChrome(_:)` once for the sheets/alert/cancel plumbing.
///
/// The chrome (and the batch task itself) deliberately belongs to the host, not
/// the selecting toolbar: an in-flight batch, its failure alert, and a presented
/// Add-to sheet all survive leaving selection mode, exactly as they did when
/// each view carried this state itself. Rows, pagination, and the non-selecting
/// toolbar stay per-surface — they genuinely differ.
@MainActor
@Observable
final class RemoteWorkSelectionController {
    enum PriorWorkState: Equatable {
        case inserted
        case revived(deletedAt: Date?, scheduledAt: Date?)
        case existing
    }

    struct ToastTarget: Identifiable {
        let id = UUID()
        let work: SavedWork
        let queue: ReadingQueue
        let membershipID: UUID
        let priorWorkState: PriorWorkState
        /// Memberships that already existed before this swipe. A queue attached
        /// while the toast is up is not in the set, so Undo leaves the work live.
        let preexistingMembershipIDs: Set<UUID>
        let wasSaved: Bool
        let wasFavorite: Bool
        let collectionIDs: Set<UUID>
        /// `lastModifiedAt` when this toast was armed. A later toast for the same
        /// revived work keeps the earlier stamp when something other than this
        /// swipe's add or its own import moved the work.
        let armedModifiedAt: Date
        let context: ModelContext
    }
    var isSelecting = false
    var selection: Set<Int> = []
    private(set) var isProcessingBatch = false
    fileprivate var batchTask: Task<Void, Never>?
    fileprivate var resolvedQueueWorks: [SavedWork] = []
    fileprivate var showingAddToQueue = false
    fileprivate var resolvedCollectionWorks: [SavedWork] = []
    fileprivate var showingAddToCollection = false
    fileprivate var batchActionError: String?
    var sourceQueueID: UUID?
    var toastTarget: ToastTarget?
    var changeTarget: ToastTarget?
    private var toastDismissTask: Task<Void, Never>?

    func changeQueue() {
        guard let toastTarget else { return }
        toastDismissTask?.cancel()
        changeTarget = toastTarget
        self.toastTarget = nil
    }

    func undo() {
        guard let target = toastTarget else { return }
        toastDismissTask?.cancel()
        toastTarget = nil
        let ownImportIsLastWrite = RevivedSwipeImport.lastWriteWasOwnImport(
            target.work, armedAt: target.armedModifiedAt
        )
        RevivedSwipeImport.disarm(target.work.id)
        guard target.work.modelContext != nil,
              target.work.queueMemberships.contains(where: { $0.id == target.membershipID }) else { return }
        switch target.priorWorkState {
        case .inserted:
            ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(
                target.work, from: target.queue, in: target.context
            )
        case let .revived(deletedAt, scheduledAt):
            undoRevived(
                target, deletedAt: deletedAt, scheduledAt: scheduledAt,
                ownImportIsLastWrite: ownImportIsLastWrite
            )
        case .existing:
            ReadingQueueService.removeFromQueue(target.work, from: target.queue, in: target.context)
        }
    }

    /// Nil stays nil: `sweepExpired` treats a missing date as not due
    /// (`scheduledAt.map { $0 <= now } ?? false`), so a legacy row is never purged.
    /// A date that is already due is lifted to now + 7 days; a later date is kept.
    private static func revivedUndoSchedule(_ prior: Date?, now: Date = Date()) -> Date? {
        guard let prior else { return nil }
        return max(prior, now.addingTimeInterval(7 * 86_400))
    }

    private func undoRevived(
        _ target: ToastTarget,
        deletedAt: Date?,
        scheduledAt: Date?,
        ownImportIsLastWrite: Bool
    ) {
        let moved = target.work.lastModifiedAt > target.armedModifiedAt
        let swipeAddedMembership = !target.preexistingMembershipIDs.contains(target.membershipID)
        if swipeAddedMembership {
            ReadingQueueService.removeFromQueue(target.work, from: target.queue, in: target.context)
        }
        if gainedWant(target) || (moved && !ownImportIsLastWrite) { return }
        let remaining = Set(target.work.activeQueueMemberships.map(\.id))
        guard remaining.isSubset(of: target.preexistingMembershipIDs),
              !target.work.isPendingDeletion else { return }
        PreservedWorkService.softDelete(
            target.work,
            priorDates: (deletedAt, Self.revivedUndoSchedule(scheduledAt)),
            in: target.context
        )
    }

    private func gainedWant(_ target: ToastTarget) -> Bool {
        if target.work.isSaved && !target.wasSaved { return true }
        if target.work.isFavorite && !target.wasFavorite { return true }
        return target.work.collections.contains { !target.collectionIDs.contains($0.id) }
    }

    static func currentQueue(in queues: [ReadingQueue], sourceID: UUID?, storedID: String?) -> ReadingQueue? {
        let active = queues.filter { !$0.isPendingDeletion }
        if let sourceID, let queue = active.first(where: { $0.id == sourceID }) { return queue }
        if let storedID, let id = UUID(uuidString: storedID),
           let queue = active.first(where: { $0.id == id }) { return queue }
        return active.first { $0.kind == .savedForLater }
    }

    func quickAdd(
        _ summary: AO3WorkSummary,
        in context: ModelContext,
        defaults: UserDefaults = .standard,
        enqueue: (SavedWork, ReadingQueue, ModelContext) -> Void
    ) {
        guard !isSelecting else { return }
        let queues = (try? context.fetch(FetchDescriptor<ReadingQueue>())) ?? []
        let queue = Self.currentQueue(
            in: queues, sourceID: sourceQueueID,
            storedID: defaults.string(forKey: "lastAddedReadingQueueID")
        ) ?? ReadingQueueService.ensureSavedForLaterQueue(in: context)
        do {
            let existingWork = ReadingQueueService.existingWork(for: summary, in: context)
            let freshPrior: PriorWorkState = existingWork.map {
                $0.isPendingDeletion
                    ? .revived(deletedAt: $0.deletedAt, scheduledAt: $0.permanentDeletionScheduledAt)
                    : .existing
            } ?? .inserted
            // Sampled before `ensureLocalMetadata`, which always `markModified`s.
            // A later swipe must not treat that write, or its own `add`, as sync.
            let modifiedBeforeSwipe = existingWork?.lastModifiedAt
            let ownImportBeforeSwipe: Bool = {
                guard let existingWork,
                      let carried = inFlightToast(for: existingWork),
                      isRevived(carried.priorWorkState) else { return false }
                return RevivedSwipeImport.lastWriteWasOwnImport(
                    existingWork, armedAt: carried.armedModifiedAt
                )
            }()
            let work = try ReadingQueueService.ensureLocalMetadata(for: summary, in: context)
            if let membership = work.queueMemberships.first(where: { $0.queue?.id == queue.id }) {
                if inFlightToast(for: work) != nil || !isRevived(freshPrior) {
                    AccessibilityNotification.Announcement("Already in \(queue.displayName)").post()
                    return
                }
                defaults.set(queue.id.uuidString, forKey: "lastAddedReadingQueueID")
                present(toast(
                    work: work, queue: queue, membershipID: membership.id, prior: freshPrior,
                    preexistingMembershipIDs: Set(work.queueMemberships.map(\.id)),
                    wasSaved: work.isSaved, wasFavorite: work.isFavorite,
                    collectionIDs: Set(work.collections.map(\.id)),
                    armedModifiedAt: work.lastModifiedAt, context: context
                ), enqueueDownload: false, enqueue: enqueue)
                return
            }

            let carriedRevival = inFlightToast(for: work).flatMap { toast -> ToastTarget? in
                guard isRevived(toast.priorWorkState) else { return nil }
                return toast
            }
            let prior = carriedRevival?.priorWorkState ?? freshPrior
            let preexisting = carriedRevival?.preexistingMembershipIDs
                ?? Set(work.queueMemberships.map(\.id))
            let wasSaved = carriedRevival?.wasSaved ?? work.isSaved
            let wasFavorite = carriedRevival?.wasFavorite ?? work.isFavorite
            let collectionIDs = carriedRevival?.collectionIDs ?? Set(work.collections.map(\.id))
            let membership = ReadingQueueService.add(work, to: queue, in: context)
            try context.save()
            defaults.set(queue.id.uuidString, forKey: "lastAddedReadingQueueID")
            let armedModifiedAt: Date
            if let carriedRevival, let modifiedBeforeSwipe,
               modifiedBeforeSwipe > carriedRevival.armedModifiedAt, !ownImportBeforeSwipe {
                armedModifiedAt = carriedRevival.armedModifiedAt
            } else {
                armedModifiedAt = work.lastModifiedAt
            }
            present(toast(
                work: work, queue: queue, membershipID: membership.id, prior: prior,
                preexistingMembershipIDs: preexisting, wasSaved: wasSaved, wasFavorite: wasFavorite,
                collectionIDs: collectionIDs, armedModifiedAt: armedModifiedAt, context: context
            ), enqueueDownload: true, enqueue: enqueue)
        } catch {
            context.rollback()
            batchActionError = error.localizedDescription
        }
    }

    private func isRevived(_ state: PriorWorkState) -> Bool {
        if case .revived = state { return true }
        return false
    }

    private func inFlightToast(for work: SavedWork) -> ToastTarget? {
        if let toastTarget, toastTarget.work.id == work.id { return toastTarget }
        if let changeTarget, changeTarget.work.id == work.id { return changeTarget }
        return nil
    }

    private func toast(
        work: SavedWork,
        queue: ReadingQueue,
        membershipID: UUID,
        prior: PriorWorkState,
        preexistingMembershipIDs: Set<UUID>,
        wasSaved: Bool,
        wasFavorite: Bool,
        collectionIDs: Set<UUID>,
        armedModifiedAt: Date,
        context: ModelContext
    ) -> ToastTarget {
        ToastTarget(
            work: work, queue: queue, membershipID: membershipID, priorWorkState: prior,
            preexistingMembershipIDs: preexistingMembershipIDs, wasSaved: wasSaved,
            wasFavorite: wasFavorite, collectionIDs: collectionIDs,
            armedModifiedAt: armedModifiedAt, context: context
        )
    }

    private func present(
        _ target: ToastTarget,
        enqueueDownload: Bool,
        enqueue: (SavedWork, ReadingQueue, ModelContext) -> Void
    ) {
        if let previous = toastTarget, previous.work.id != target.work.id {
            RevivedSwipeImport.disarm(previous.work.id)
        }
        toastTarget = target
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, toastTarget?.id == target.id else { return }
            RevivedSwipeImport.disarm(target.work.id)
            toastTarget = nil
        }
        AccessibilityNotification.Announcement("Added to \(target.queue.displayName)").post()
        if enqueueDownload {
            RevivedSwipeImport.arm(target.work.id)
            enqueue(target.work, target.queue, target.context)
        }
    }

    /// The selected summaries, in the host's current display order.
    func selected(in results: [AO3WorkSummary]) -> [AO3WorkSummary] {
        results.filter { selection.contains($0.id) }
    }

    func toggle(_ work: AO3WorkSummary) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    func allSelected(in results: [AO3WorkSummary]) -> Bool {
        !results.isEmpty && results.allSatisfy { selection.contains($0.id) }
    }

    /// Select All, or Deselect All once everything in `results` is chosen.
    /// Only ever touches `results`' ids.
    func toggleSelectAll(in results: [AO3WorkSummary]) {
        let ids = results.map(\.id)
        if allSelected(in: results) {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    func exitSelectMode() {
        isSelecting = false
        selection = []
    }

    // MARK: Bulk actions

    // Each resolves the selected remote summaries to local works one at a time —
    // never bursting concurrent AO3 requests (see RemoteWorkBulkActions.swift).

    fileprivate func bulkSave(_ selected: [AO3WorkSummary], in context: ModelContext) async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        // "Download" fetches each EPUB (owner, 2026-09-28), not just the flag.
        batchActionError = await resolveSelectedRemoteWorks(selected, in: context, mode: .withEPUB) { works in
            for work in works {
                WorkLifecycle.setSaved(work, true, in: context)
            }
        }
    }

    fileprivate func bulkSaveForLater(_ selected: [AO3WorkSummary], in context: ModelContext) async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await bulkSaveForLaterRemote(selected, in: context)
    }

    fileprivate func bulkAddToCollection(_ selected: [AO3WorkSummary], in context: ModelContext) async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selected, in: context) { works in
            resolvedCollectionWorks = works
            showingAddToCollection = true
        }
    }

    fileprivate func bulkAddToQueue(_ selected: [AO3WorkSummary], in context: ModelContext) async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selected, in: context) { works in
            resolvedQueueWorks = works
            showingAddToQueue = true
        }
    }
}

/// The selecting-mode toolbar: "Done" plus the bulk-action menu in the top bar
/// (Board 15 — no floating bottom bar over the list's pagination footer on iOS;
/// primary action on macOS).
struct RemoteWorkSelectionToolbar: ToolbarContent {
    static let usesBottomBar = false

    let controller: RemoteWorkSelectionController
    /// The works Select All covers (the loaded results). Nil leaves Select All to the caller.
    var selectable: (() -> [AO3WorkSummary])?
    /// Evaluated when a bulk button's task runs, so it acts on the live selection.
    let selectedSummaries: () -> [AO3WorkSummary]

    var body: some ToolbarContent {
        // Spec 1af / board 15: select mode takes the title bar for a count, as Library's does.
        ToolbarItem(placement: .principal) {
            Text(WorkSelectionTitle.text(selectedCount: controller.selection.count))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .contentTransition(.numericText())
        }
        if let selectable {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) { selectAllButton(selectable) }
            #else
            ToolbarItem(placement: .primaryAction) { selectAllButton(selectable) }
            #endif
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .topBarTrailing) {
            if controller.isProcessingBatch {
                ProgressView()
                    .controlSize(.small)
                    .accentFill()
            } else {
                Menu {
                    RemoteWorkBulkActionBar(controller: controller, selectedSummaries: selectedSummaries)
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .disabled(controller.selection.isEmpty)
            }
            Button { controller.exitSelectMode() } label: {
                Image(systemName: "checkmark")
            }
            .accessibilityLabel("Done")
        }
        #else
        ToolbarItem(placement: .confirmationAction) {
            Button { controller.exitSelectMode() } label: {
                Image(systemName: "checkmark")
            }
            .accessibilityLabel("Done")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            RemoteWorkBulkActionBar(controller: controller, selectedSummaries: selectedSummaries)
        }
        #endif
    }

    private func selectAllButton(_ selectable: @escaping () -> [AO3WorkSummary]) -> some View {
        SelectAllButton(allSelected: controller.allSelected(in: selectable())) {
            controller.toggleSelectAll(in: selectable())
        }
        .disabled(selectable().isEmpty)
    }
}

/// The four shared bulk actions over the current selection, mirroring
/// `LibraryView`'s local `WorkBulkActionBar`. Buttons stay disabled while a
/// batch runs; the trailing spinner reports progress.
struct RemoteWorkBulkActionBar: View {
    let controller: RemoteWorkSelectionController
    let selectedSummaries: () -> [AO3WorkSummary]

    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            run { await controller.bulkSave(selectedSummaries(), in: context) }
        } label: {
            Label(
                WorkActionLabels.saved(isSaved: false).title,
                systemImage: WorkActionLabels.saved(isSaved: false).systemImage
            )
        }
        .disabled(controller.selection.isEmpty || controller.isProcessingBatch)

        Button {
            run { await controller.bulkSaveForLater(selectedSummaries(), in: context) }
        } label: {
            Label(
                WorkActionLabels.savedForLater(isQueued: false).title,
                systemImage: WorkActionLabels.savedForLater(isQueued: false).systemImage
            )
        }
        .disabled(controller.selection.isEmpty || controller.isProcessingBatch)

        Button {
            run { await controller.bulkAddToCollection(selectedSummaries(), in: context) }
        } label: {
            Label("Add to Collection", systemImage: "square.stack")
        }
        .disabled(controller.selection.isEmpty || controller.isProcessingBatch)

        Button {
            run { await controller.bulkAddToQueue(selectedSummaries(), in: context) }
        } label: {
            Label("Add to Queue", systemImage: "list.bullet.rectangle")
        }
        .disabled(controller.selection.isEmpty || controller.isProcessingBatch)

        if controller.isProcessingBatch {
            ProgressView()
                .controlSize(.small)
                .accentFill()
        }
    }

    private func run(_ operation: @escaping @MainActor () async -> Void) {
        controller.batchTask = Task { await operation() }
    }
}

/// One remote work row that flips between navigation (normal) and
/// tap-to-toggle-selection (selecting), with the shared selection accessibility
/// treatment. Used by Browse's fandom/tag works and Search results;
/// `AuthorProfileView` keeps its own rows (a different row component).
struct SelectableAO3WorkRow: View {
    let work: AO3WorkSummary
    let expandAll: Bool
    let controller: RemoteWorkSelectionController
    var presentation: AO3WorkRow.Presentation = .standard
    /// Search's computed-sort figure for this work, when the reader shows it.
    var signal: String?
    var qualitySignal: WorkSignal? = nil
    var rankedContext: RankedWork? = nil
    var badgeTitle: String? = nil
    var showsSummary = true
    var badgeCount = 0
    var wide = false
    var showsSeparator = true

    @Environment(\.modelContext) private var context
    @Environment(DownloadQueue.self) private var downloadQueue

    var body: some View {
        SensitiveWorkRow(
            work: work,
            expandAll: expandAll,
            isSelecting: controller.isSelecting,
            isSelected: controller.selection.contains(work.id),
            onToggleSelection: { controller.toggle(work) },
            presentation: presentation,
            signal: signal,
            qualitySignal: qualitySignal,
            rankedContext: rankedContext,
            badgeTitle: badgeTitle,
            quickQueue: { controller.quickAdd(work, in: context) { saved, queue, context in
                guard KeepOffline.queueKeeps(queue.keepsWorksOffline) else { return }
                downloadQueue.enqueue(
                    KeepOffline.downloadItems(for: [saved]).map { item in
                        var item = item
                        item.requiresOfflineQueue = true
                        return item
                    }, into: context
                )
            } },
            showsSummary: showsSummary,
            badgeCount: badgeCount,
            wide: wide,
            showsSeparator: showsSeparator
        )
    }
}

extension View {
    /// Host-side plumbing for a `RemoteWorkSelectionController`: the Add to
    /// Queue/Collection sheets, the batch failure alert, and cancelling the
    /// in-flight batch when the surface goes away. Applied to the host view
    /// (not the selecting toolbar) so all three outlive selection mode.
    /// Unstructured batch tasks outlive the view unless explicitly cancelled;
    /// the bulk loops bail out cleanly on CancellationError.
    func remoteWorkSelectionChrome(_ controller: RemoteWorkSelectionController) -> some View {
        @Bindable var controller = controller
        return self
            .sheet(isPresented: $controller.showingAddToQueue) {
                AddToQueueView(works: controller.resolvedQueueWorks)
            }
            .sheet(item: $controller.changeTarget) { target in
                AddToQueueView(work: target.work, movingFrom: target.queue)
            }
            .sheet(isPresented: $controller.showingAddToCollection) {
                AddToCollectionView(works: controller.resolvedCollectionWorks)
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { controller.batchActionError != nil },
                    set: { if !$0 { controller.batchActionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { controller.batchActionError = nil }
            } message: {
                Text(controller.batchActionError ?? "")
            }
            #if os(iOS)
            .toolbar(controller.isSelecting ? .hidden : .automatic, for: .tabBar)
            #endif
            .onDisappear { controller.batchTask?.cancel() }
            .safeAreaInset(edge: .bottom) {
                if let target = controller.toastTarget {
                    QueueAddedToast(queue: target.queue, change: {
                        controller.changeQueue()
                    }, undo: { controller.undo() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            // A tick per row ticked, but not for the clear when selection mode ends.
            .sensoryFeedback(.selection, trigger: controller.selection.count) { _, _ in controller.isSelecting }
    }
}
