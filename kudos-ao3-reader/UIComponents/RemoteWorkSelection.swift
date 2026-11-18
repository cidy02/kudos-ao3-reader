import SwiftData
import SwiftUI

/// Snapshot of a revived work's state taken right before `quickAdd` restores it.
/// Undo re-soft-deletes only when the work still matches this baseline (ignoring
/// swipe/download metadata enrichment and the single membership the swipe added).
struct RevivedWorkBaseline: Equatable {
    struct MembershipSnapshot: Equatable {
        let sortOrderInQueue: Int
        let note: String
    }

    struct ReadingStatusSnapshot: Equatable {
        let readingStatusRaw: String
        let statusChangedAt: Date?
        let stoppedAt: Date?
        let stopReasonRaw: String
        let stopTag: String
        let stopNote: String
        let stackThreshold: Int
        let stackBaselineChapterCount: Int
        let statusWasRecorded: Bool

        init(work: SavedWork) {
            readingStatusRaw = work.readingStatusRaw
            statusChangedAt = work.statusChangedAt
            stoppedAt = work.stoppedAt
            stopReasonRaw = work.stopReasonRaw
            stopTag = work.stopTag
            stopNote = work.stopNote
            stackThreshold = work.stackThreshold
            stackBaselineChapterCount = work.stackBaselineChapterCount
            statusWasRecorded = work.statusWasRecorded
        }
    }

    struct ProgressSnapshot: Equatable {
        let lastReadDate: Date?
        let progressModifiedAt: Date?
        let lastSpineIndex: Int
        let lastScrollFraction: Double
        let readiumLocator: String
        let legacyReaderProgress: Double?

        init(work: SavedWork) {
            lastReadDate = work.lastReadDate
            progressModifiedAt = work.progressModifiedAt
            lastSpineIndex = work.lastSpineIndex
            lastScrollFraction = work.lastScrollFraction
            readiumLocator = work.readiumLocator
            legacyReaderProgress = work.legacyReaderProgress
        }
    }

    struct AnnotationSnapshot: Equatable {
        let lastModifiedAt: Date
        let note: String
        let colorRaw: String
        let locatorString: String
        let selectedText: String
        let kindRaw: String
        let isPendingDeletion: Bool

        init(annotation: ReadingAnnotation) {
            lastModifiedAt = annotation.lastModifiedAt
            note = annotation.note
            colorRaw = annotation.colorRaw
            locatorString = annotation.locatorString
            selectedText = annotation.selectedText
            kindRaw = annotation.kindRaw
            isPendingDeletion = annotation.isPendingDeletion
        }
    }

    struct SessionSnapshot: Equatable {
        let lastModifiedAt: Date
        let endedAt: Date
        let durationSeconds: Double
        let activeSeconds: Double?
        let didFinish: Bool

        init(session: ReadingSession) {
            lastModifiedAt = session.lastModifiedAt
            endedAt = session.endedAt
            durationSeconds = session.durationSeconds
            activeSeconds = session.activeSeconds
            didFinish = session.didFinish
        }
    }

    let preexistingMembershipIDs: Set<UUID>
    let preexistingActiveMembershipIDs: Set<UUID>
    let preexistingMemberships: [UUID: MembershipSnapshot]
    let isSaved: Bool
    let isFavorite: Bool
    let isFinished: Bool
    let hasGivenKudos: Bool
    let keepInProgressOverride: Bool
    let hiddenFromHistoryAt: Date?
    let downloadedAt: Date?
    let title: String
    let author: String
    let summary: String
    let collectionIDs: Set<UUID>
    let activeCollectionIDs: Set<UUID>
    let userTagNames: Set<String>
    let readingStatus: ReadingStatusSnapshot
    let progress: ProgressSnapshot
    let annotations: [UUID: AnnotationSnapshot]
    let sessions: [UUID: SessionSnapshot]

    @MainActor
    static func capture(_ work: SavedWork, in context: ModelContext) -> Self {
        let memberships = Dictionary(
            work.queueMemberships.map {
                ($0.id, MembershipSnapshot(sortOrderInQueue: $0.sortOrderInQueue, note: $0.note))
            },
            uniquingKeysWith: { first, _ in first }
        )
        return Self(
            preexistingMembershipIDs: Set(work.queueMemberships.map(\.id)),
            preexistingActiveMembershipIDs: Set(work.activeQueueMemberships.map(\.id)),
            preexistingMemberships: memberships,
            isSaved: work.isSaved,
            isFavorite: work.isFavorite,
            isFinished: work.isFinished,
            hasGivenKudos: work.hasGivenKudos,
            keepInProgressOverride: work.keepInProgressOverride,
            hiddenFromHistoryAt: work.hiddenFromHistoryAt,
            downloadedAt: work.downloadedAt,
            title: work.title,
            author: work.author,
            summary: work.summary,
            collectionIDs: Set(work.collections.map(\.id)),
            activeCollectionIDs: Set(work.activeCollections.map(\.id)),
            userTagNames: Set(work.tags.map(\.name)),
            readingStatus: ReadingStatusSnapshot(work: work),
            progress: ProgressSnapshot(work: work),
            annotations: annotationSnapshots(for: work.id, in: context),
            sessions: sessionSnapshots(for: work.id, in: context)
        )
    }

    @MainActor
    func hasChanges(on work: SavedWork, in context: ModelContext) -> Bool {
        hasMembershipOrContainerChanges(on: work)
            || hasUserStateChanges(on: work)
            || hasProgressOrSessionChanges(on: work, in: context)
            || Self.annotationSnapshots(for: work.id, in: context) != annotations
    }

    @MainActor
    private func hasMembershipOrContainerChanges(on work: SavedWork) -> Bool {
        if Set(work.queueMemberships.map(\.id)) != preexistingMembershipIDs { return true }
        if !Set(work.activeQueueMemberships.map(\.id)).isSubset(of: preexistingActiveMembershipIDs) {
            return true
        }
        let currentMemberships = Dictionary(
            work.queueMemberships.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (id, snapshot) in preexistingMemberships {
            guard let membership = currentMemberships[id],
                  membership.sortOrderInQueue == snapshot.sortOrderInQueue,
                  membership.note == snapshot.note else { return true }
        }
        if Set(work.collections.map(\.id)) != collectionIDs { return true }
        if !Set(work.activeCollections.map(\.id)).isSubset(of: activeCollectionIDs) { return true }
        return Set(work.tags.map(\.name)) != userTagNames
    }

    @MainActor
    private func hasUserStateChanges(on work: SavedWork) -> Bool {
        if work.isSaved != isSaved
            || work.isFavorite != isFavorite
            || work.isFinished != isFinished
            || work.hasGivenKudos != hasGivenKudos
            || work.keepInProgressOverride != keepInProgressOverride
            || work.hiddenFromHistoryAt != hiddenFromHistoryAt {
            return true
        }
        if ReadingStatusSnapshot(work: work) != readingStatus { return true }
        if (!title.isEmpty && work.title != title)
            || (!author.isEmpty && work.author != author)
            || (!summary.isEmpty && work.summary != summary) {
            return true
        }
        if let downloadedAt {
            if work.downloadedAt != downloadedAt { return true }
        } else if work.downloadedAt != nil, !work.hasEPUB {
            // `importEPUB` sets `downloadedAt` only alongside `hasEPUB = true`;
            // a date appearing without an EPUB came from a user edit or sync.
            return true
        }
        return false
    }

    @MainActor
    private func hasProgressOrSessionChanges(on work: SavedWork, in context: ModelContext) -> Bool {
        if ProgressSnapshot(work: work) != progress { return true }
        if ReadingLogService.hasOpenSession(for: work.id) { return true }
        return Self.sessionSnapshots(for: work.id, in: context) != sessions
    }

    @MainActor
    private static func annotationSnapshots(
        for workID: UUID,
        in context: ModelContext
    ) -> [UUID: AnnotationSnapshot] {
        let marks = (try? context.fetch(FetchDescriptor<ReadingAnnotation>()))?
            .filter { $0.work?.id == workID } ?? []
        return Dictionary(
            marks.map { ($0.id, AnnotationSnapshot(annotation: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @MainActor
    private static func sessionSnapshots(
        for workID: UUID,
        in context: ModelContext
    ) -> [UUID: SessionSnapshot] {
        let descriptor = FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.workID == workID })
        let rows = (try? context.fetch(descriptor)) ?? []
        return Dictionary(
            rows.map { ($0.id, SessionSnapshot(session: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
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
        /// Pre-swipe state for a `.revived` work. Undo re-soft-deletes only when
        /// the work still matches this baseline (ignoring the swipe's own add and
        /// metadata/EPUB enrichment), else leaves it live.
        let revivedBaseline: RevivedWorkBaseline?
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
        guard target.work.modelContext != nil,
              target.work.queueMemberships.contains(where: { $0.id == target.membershipID }) else { return }
        switch target.priorWorkState {
        case .inserted:
            ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(
                target.work, from: target.queue, in: target.context
            )
        case let .revived(deletedAt, scheduledAt):
            undoRevived(target, deletedAt: deletedAt, scheduledAt: scheduledAt)
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
        scheduledAt: Date?
    ) {
        guard let baseline = target.revivedBaseline else { return }
        let swipeAddedMembership = !baseline.preexistingMembershipIDs.contains(target.membershipID)
        if swipeAddedMembership {
            ReadingQueueService.removeFromQueue(target.work, from: target.queue, in: target.context)
        }
        guard !baseline.hasChanges(on: target.work, in: target.context),
              !target.work.isPendingDeletion else { return }
        PreservedWorkService.softDelete(
            target.work,
            priorDates: (deletedAt, Self.revivedUndoSchedule(scheduledAt)),
            in: target.context
        )
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
            let carriedRevival = existingWork.flatMap { inFlightToast(for: $0) }.flatMap { toast -> ToastTarget? in
                guard isRevived(toast.priorWorkState) else { return nil }
                return toast
            }
            let prior: PriorWorkState
            let baseline: RevivedWorkBaseline?
            if let carriedRevival {
                prior = carriedRevival.priorWorkState
                baseline = carriedRevival.revivedBaseline
            } else if let existingWork, existingWork.isPendingDeletion {
                prior = .revived(
                    deletedAt: existingWork.deletedAt,
                    scheduledAt: existingWork.permanentDeletionScheduledAt
                )
                baseline = RevivedWorkBaseline.capture(existingWork, in: context)
            } else if existingWork != nil {
                prior = .existing
                baseline = nil
            } else {
                prior = .inserted
                baseline = nil
            }
            let work = try ReadingQueueService.ensureLocalMetadata(for: summary, in: context)
            if let membership = work.queueMemberships.first(where: { $0.queue?.id == queue.id }) {
                if inFlightToast(for: work) != nil || !isRevived(prior) {
                    AccessibilityNotification.Announcement("Already in \(queue.displayName)").post()
                    return
                }
                defaults.set(queue.id.uuidString, forKey: "lastAddedReadingQueueID")
                present(ToastTarget(
                    work: work, queue: queue, membershipID: membership.id,
                    priorWorkState: prior, revivedBaseline: baseline, context: context
                ), enqueueDownload: false, enqueue: enqueue)
                return
            }

            let membership = ReadingQueueService.add(work, to: queue, in: context)
            try context.save()
            defaults.set(queue.id.uuidString, forKey: "lastAddedReadingQueueID")
            present(ToastTarget(
                work: work, queue: queue, membershipID: membership.id,
                priorWorkState: prior, revivedBaseline: baseline, context: context
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

    private func present(
        _ target: ToastTarget,
        enqueueDownload: Bool,
        enqueue: (SavedWork, ReadingQueue, ModelContext) -> Void
    ) {
        toastTarget = target
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, toastTarget?.id == target.id else { return }
            toastTarget = nil
        }
        AccessibilityNotification.Announcement("Added to \(target.queue.displayName)").post()
        if enqueueDownload {
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
