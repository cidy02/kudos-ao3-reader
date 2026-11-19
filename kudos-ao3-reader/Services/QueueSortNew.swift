import Foundation
import SwiftData

/// T-529 Sort New (board `Queue-Sort`): one decision on one `New` work.
/// Keep moves it to `In line`, Later leaves it in `New`, Drop takes it out of the
/// queue through `ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly`.
nonisolated enum QueueSortAction: String, CaseIterable, Sendable {
    case keep
    case later
    case drop
}

/// A membership's stored fields as they were before a Sort New decision, so Undo
/// can put back exactly that state, place in the order and origin — and, after a
/// Drop, recreate the membership under its own id.
struct QueueSortMembershipSnapshot: Equatable {
    let id: UUID
    let queuedAt: Date
    let sortOrderInQueue: Int
    let note: String
    let stateRaw: String
    let stateWasRecorded: Bool
    let originKindRaw: String?
    let originSearchID: UUID?
    let originLabel: String?

    init(_ membership: ReadingQueueMembership) {
        id = membership.id
        queuedAt = membership.queuedAt
        sortOrderInQueue = membership.sortOrderInQueue
        note = membership.note
        stateRaw = membership.stateRaw
        stateWasRecorded = membership.stateWasRecorded
        originKindRaw = membership.originKindRaw
        originSearchID = membership.originSearchID
        originLabel = membership.originLabel
    }
}

/// One decision of a Sort New session and what it changed.
struct QueueSortRecord: Equatable {
    let membershipID: UUID
    let workID: UUID
    let action: QueueSortAction
    /// Keep and Drop: the membership before the decision. Later changes nothing.
    let before: QueueSortMembershipSnapshot?
    /// Drop only: the drop sent a queue-only work to Recently Deleted.
    let sentWorkToRecentlyDeleted: Bool
    /// Drop only: the work's preservation fields before removal re-derived them.
    let preservationStatusRaw: String?
    let preservedAt: Date?
    /// The membership left the queue some other way (sync, another screen)
    /// before it came up; the cursor stepped over it. Undo steps back over it too.
    var skipped = false

    static func skip(membershipID: UUID) -> QueueSortRecord {
        QueueSortRecord(
            membershipID: membershipID, workID: membershipID, action: .later, before: nil,
            sentWorkToRecentlyDeleted: false, preservationStatusRaw: nil, preservedAt: nil, skipped: true
        )
    }
}

/// The cursor through a queue's `New` works, captured in queue order when the
/// session opens. Pure value: the queue page owns it, `QueueSortNew` applies it.
struct QueueSortSession: Equatable {
    enum Segment: Equatable {
        case sorted
        case current
        case upcoming
    }

    let queueID: UUID
    /// Membership ids of the `New` works, in the queue's order, at the start.
    let membershipIDs: [UUID]
    private(set) var history: [QueueSortRecord] = []

    init(queueID: UUID, membershipIDs: [UUID]) {
        self.queueID = queueID
        var seen = Set<UUID>()
        self.membershipIDs = membershipIDs.filter { seen.insert($0).inserted }
    }

    var total: Int { membershipIDs.count }
    var sortedCount: Int { history.count }
    var isFinished: Bool { history.count >= membershipIDs.count }
    var canUndo: Bool { history.contains { !$0.skipped } }

    var currentMembershipID: UUID? {
        isFinished ? nil : membershipIDs[history.count]
    }

    /// The membership after the current one, for the card peeking behind it.
    var nextMembershipID: UUID? {
        let index = history.count + 1
        return index < membershipIDs.count ? membershipIDs[index] : nil
    }

    /// 1-based place of the work on screen ("3 of 7"); `total` once finished.
    var position: Int { min(history.count + 1, total) }

    /// The board's subtitle, "3 of 7 · Summer Reading".
    func subtitle(queueName: String) -> String {
        "\(position) of \(total) · \(queueName)"
    }

    /// The board's segmented bar: decided works, the one on screen, the rest.
    var segments: [Segment] {
        membershipIDs.indices.map { index in
            if index < history.count { return .sorted }
            if index == history.count { return .current }
            return .upcoming
        }
    }

    func count(of action: QueueSortAction) -> Int {
        history.filter { $0.action == action && !$0.skipped }.count
    }

    /// Spoken by the progress bar: "2 of 7 sorted".
    var progressAccessibilityLabel: String {
        "\(sortedCount) of \(total) sorted"
    }

    /// The board's line under the card: "About 37 min to read · found by Holmes
    /// casefic under 20k". Either half drops out when unknown; nil when both do.
    static func footerLine(minutes: Double?, originLabel: String?) -> String? {
        var parts: [String] = []
        if let minutes, let estimate = ReadingQueueFacts.readingTimeEstimate(minutes: minutes) {
            parts.append(estimate.prefix(1).uppercased() + estimate.dropFirst() + " to read")
        }
        if let label = originLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            parts.append("found by \(label)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    mutating func record(_ record: QueueSortRecord) {
        guard record.membershipID == currentMembershipID else { return }
        history.append(record)
    }

    /// Pops back to, and returns, the last real decision, dropping the skips
    /// recorded after it. Nil (and no change) when there is none.
    mutating func popLast() -> QueueSortRecord? {
        guard let index = history.lastIndex(where: { !$0.skipped }) else { return nil }
        let record = history[index]
        history.removeSubrange(index...)
        return record
    }
}

/// Applies and undoes Sort New decisions. Every write goes through the existing
/// queue service; Undo restores the exact previous membership and, after a Drop
/// of a queue-only work, brings the work back from Recently Deleted.
@MainActor
enum QueueSortNew {
    /// The membership a session id names, while it is still in `queue`.
    static func membership(_ id: UUID, in queue: ReadingQueue) -> ReadingQueueMembership? {
        queue.memberships.first { $0.id == id && !$0.isPendingDeletion }
    }

    /// Applies `action` to the session's current work and records it. Returns
    /// false (and records nothing) when that membership is gone.
    @discardableResult
    static func apply(
        _ action: QueueSortAction,
        session: inout QueueSortSession,
        queue: ReadingQueue,
        context: ModelContext
    ) -> Bool {
        guard queue.id == session.queueID,
              let id = session.currentMembershipID,
              let record = apply(action, membershipID: id, in: queue, context: context)
        else { return false }
        session.record(record)
        return true
    }

    /// Steps the cursor over works that left the queue since the session began.
    static func skipMissing(session: inout QueueSortSession, queue: ReadingQueue) {
        while let id = session.currentMembershipID,
              membership(id, in: queue)?.work.map({ !$0.isPendingDeletion }) != true {
            session.record(.skip(membershipID: id))
        }
    }

    /// Undoes the last decision of the session. Returns the undone record.
    @discardableResult
    static func undo(
        session: inout QueueSortSession,
        queue: ReadingQueue,
        context: ModelContext
    ) -> QueueSortRecord? {
        guard queue.id == session.queueID, let record = session.popLast() else { return nil }
        undo(record, in: queue, context: context)
        return record
    }

    static func apply(
        _ action: QueueSortAction,
        membershipID: UUID,
        in queue: ReadingQueue,
        context: ModelContext
    ) -> QueueSortRecord? {
        guard queue.kind != .smart,
              let membership = membership(membershipID, in: queue),
              let work = membership.work
        else { return nil }
        switch action {
        case .later:
            return QueueSortRecord(
                membershipID: membershipID, workID: work.id, action: .later, before: nil,
                sentWorkToRecentlyDeleted: false, preservationStatusRaw: nil, preservedAt: nil
            )
        case .keep:
            let before = QueueSortMembershipSnapshot(membership)
            ReadingQueueService.sortIntoLine(membership, in: queue, context: context)
            return QueueSortRecord(
                membershipID: membershipID, workID: work.id, action: .keep, before: before,
                sentWorkToRecentlyDeleted: false, preservationStatusRaw: nil, preservedAt: nil
            )
        case .drop:
            let before = QueueSortMembershipSnapshot(membership)
            let wasPendingDeletion = work.isPendingDeletion
            let statusRaw = work.epubPreservationStatusRaw
            let preservedAt = work.preservedAt
            ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(work, from: queue, in: context)
            return QueueSortRecord(
                membershipID: membershipID, workID: work.id, action: .drop, before: before,
                sentWorkToRecentlyDeleted: !wasPendingDeletion && work.isPendingDeletion,
                preservationStatusRaw: statusRaw, preservedAt: preservedAt
            )
        }
    }

    @discardableResult
    static func undo(_ record: QueueSortRecord, in queue: ReadingQueue, context: ModelContext) -> Bool {
        guard queue.kind != .smart else { return false }
        switch record.action {
        case .later:
            return true
        case .keep:
            guard let before = record.before,
                  let membership = membership(record.membershipID, in: queue)
            else { return false }
            restore(before, onto: membership)
            let now = Date()
            membership.markModified(now)
            queue.markMembershipChanged(now)
            FolderSyncService.markDirty()
            return context.saveBestEffort(reason: "Undoing Sort New keep failed")
        case .drop:
            return undoDrop(record, in: queue, context: context)
        }
    }

    private static func undoDrop(_ record: QueueSortRecord, in queue: ReadingQueue, context: ModelContext) -> Bool {
        guard let before = record.before else { return false }
        let workID = record.workID
        var descriptor = FetchDescriptor<SavedWork>(predicate: #Predicate { $0.id == workID })
        descriptor.fetchLimit = 1
        guard let work = try? context.fetch(descriptor).first else { return false }
        if record.sentWorkToRecentlyDeleted, work.isPendingDeletion {
            PreservedWorkService.restore(work, in: context)
        }
        // Re-added some other way since the drop: leave that membership alone.
        guard !work.queueMemberships.contains(where: { $0.queue?.id == queue.id }) else {
            return context.saveBestEffort(reason: "Undoing Sort New drop failed")
        }
        let membership = ReadingQueueMembership(
            id: before.id,
            queue: queue,
            work: work,
            queuedAt: before.queuedAt,
            sortOrderInQueue: before.sortOrderInQueue,
            note: before.note
        )
        restore(before, onto: membership)
        context.insert(membership)
        queue.memberships.append(membership)
        work.queueMemberships.append(membership)
        // The drop tombstoned this membership id; take it back so sync does not
        // delete the restored membership again.
        PreservedWorkService.retractTombstone(recordID: before.id, type: .readingQueueMembership, in: context)
        let now = Date()
        queue.markMembershipChanged(now)
        membership.markModified(now)
        work.markModified(now)
        work.isQueuedForLater = true
        ReadingQueueService.normalize(work)
        if let statusRaw = record.preservationStatusRaw, work.epubPreservationStatusRaw == statusRaw {
            work.preservedAt = record.preservedAt
        }
        FolderSyncService.markDirty()
        return context.saveBestEffort(reason: "Undoing Sort New drop failed")
    }

    /// Writes the raw stored fields back, bypassing the `state` setter (which
    /// would always mark the state as recorded).
    private static func restore(_ snapshot: QueueSortMembershipSnapshot, onto membership: ReadingQueueMembership) {
        membership.stateRaw = snapshot.stateRaw
        membership.stateWasRecorded = snapshot.stateWasRecorded
        membership.sortOrderInQueue = snapshot.sortOrderInQueue
        membership.queuedAt = snapshot.queuedAt
        membership.note = snapshot.note
        membership.originKindRaw = snapshot.originKindRaw
        membership.originSearchID = snapshot.originSearchID
        membership.originLabel = snapshot.originLabel
    }
}
