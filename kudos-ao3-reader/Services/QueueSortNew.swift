import CoreGraphics
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

/// Stamp of a `SyncTombstone` created by a Sort New Drop, so Undo only retracts
/// the tombstone this Drop itself wrote and refuses if a newer or foreign-device
/// deletion superseded it.
struct QueueSortTombstoneStamp: Equatable {
    let id: UUID
    let lastModifiedAt: Date
    let deletedOnDeviceID: String
    let signerPublicKey: String
    let signature: String

    init(_ tombstone: SyncTombstone) {
        id = tombstone.id
        lastModifiedAt = tombstone.lastModifiedAt
        deletedOnDeviceID = tombstone.deletedOnDeviceID
        signerPublicKey = tombstone.signerPublicKey
        signature = tombstone.signature
    }

    /// Tolerates the <= 1 ms ISO-8601 fractional-second rounding from round-tripping
    /// our own archive, while rejecting any new local row (`id`) or foreign overwrite
    /// (`deletedOnDeviceID`, `signerPublicKey`, `signature`, or newer timestamp).
    func matches(_ tombstone: SyncTombstone) -> Bool {
        tombstone.id == id
            && tombstone.deletedOnDeviceID == deletedOnDeviceID
            && tombstone.signerPublicKey == signerPublicKey
            && tombstone.signature == signature
            && abs(tombstone.lastModifiedAt.timeIntervalSince(lastModifiedAt)) <= 0.001
    }
}

/// The three fields `ReadingQueueService.sortIntoLine` writes on Keep, captured
/// right after Keep so Undo only reverts them when nothing newer reordered or
/// changed the state, and leaves intervening note/origin/queuedAt edits alone.
struct QueueSortKeepOutcome: Equatable {
    let stateRaw: String
    let stateWasRecorded: Bool
    let sortOrderInQueue: Int
}

/// What a Drop changed, including the exact stamps it set so Undo never mutates
/// or resurrects a work or membership deleted later on this or another device.
struct QueueSortDropOutcome: Equatable {
    let sentWorkToRecentlyDeleted: Bool
    let preservationStatusRaw: String?
    let preservedAt: Date?
    let workDeletedAt: Date?
    let membershipTombstone: QueueSortTombstoneStamp?
    let workTombstone: QueueSortTombstoneStamp?
}

/// Outcome of `QueueSortNew.undo(session:queue:context:isVisible:)`.
enum QueueSortUndoResult: Equatable {
    case undone(QueueSortRecord)
    case blocked(QueueSortRecord)
    case nothingToUndo

    var undoneRecord: QueueSortRecord? {
        if case let .undone(record) = self { return record }
        return nil
    }
}

/// Pure horizontal-swipe classification for the Sort New card so diagonal
/// vertical scrolling never tilts the card or fires Drop/Keep on release.
enum QueueSortSwipe {
    /// Past this horizontal travel, letting go decides (right keeps, left drops).
    static let threshold: CGFloat = 110
    /// Horizontal travel must be at least 1.5× vertical travel to count as a swipe.
    static let horizontalIntentRatio: CGFloat = 1.5

    static func isHorizontalIntent(_ translation: CGSize) -> Bool {
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        return dx > 0 && dx >= dy * horizontalIntentRatio
    }

    static func dragOffset(for translation: CGSize) -> CGFloat {
        isHorizontalIntent(translation) ? translation.width : 0
    }

    static func decision(for translation: CGSize) -> QueueSortAction? {
        guard isHorizontalIntent(translation) else { return nil }
        if translation.width > threshold { return .keep }
        if translation.width < -threshold { return .drop }
        return nil
    }
}

/// One decision of a Sort New session and what it changed.
struct QueueSortRecord: Equatable {
    let membershipID: UUID
    let workID: UUID
    let action: QueueSortAction
    /// Keep and Drop: the membership before the decision. Later changes nothing.
    let before: QueueSortMembershipSnapshot?
    /// Keep only: the fields Sort New wrote, verified unchanged before Undo.
    let keepOutcome: QueueSortKeepOutcome?
    /// Drop only: whether Drop soft-deleted a queue-only work, its preservation
    /// state, and the deletion/tombstone stamps Drop wrote.
    let dropOutcome: QueueSortDropOutcome?
    /// The membership left the queue some other way (sync, another screen)
    /// before it came up; the cursor stepped over it. Undo steps back over it too.
    var skipped = false
    /// Undo was attempted and refused because the record changed or was deleted
    /// elsewhere; kept in history so counts and cursor stay intact without looping.
    var undoBlocked = false

    var sentWorkToRecentlyDeleted: Bool {
        dropOutcome?.sentWorkToRecentlyDeleted ?? false
    }

    var isUndoable: Bool {
        !skipped && !undoBlocked
    }

    static func skip(membershipID: UUID) -> QueueSortRecord {
        QueueSortRecord(
            membershipID: membershipID, workID: membershipID, action: .later, before: nil,
            keepOutcome: nil, dropOutcome: nil, skipped: true
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
    /// Memberships whose Undo was refused because they changed or vanished
    /// elsewhere; stepping forward after a deeper Undo skips them cleanly.
    private(set) var unrevisitableIDs: Set<UUID> = []

    init(queueID: UUID, membershipIDs: [UUID]) {
        self.queueID = queueID
        var seen = Set<UUID>()
        self.membershipIDs = membershipIDs.filter { seen.insert($0).inserted }
    }

    var total: Int { membershipIDs.count }
    var sortedCount: Int { history.count }
    var isFinished: Bool { history.count >= membershipIDs.count }
    var lastUndoableIndex: Int? { history.lastIndex(where: \.isUndoable) }
    var canUndo: Bool { lastUndoableIndex != nil }

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

    /// Pops back to, and returns, the last undoable decision, dropping any skips
    /// or blocked entries recorded after it. Nil (and no change) when there is none.
    mutating func popLast() -> QueueSortRecord? {
        guard let index = lastUndoableIndex else { return nil }
        let record = history[index]
        history.removeSubrange(index...)
        return record
    }

    mutating func popFrom(_ index: Int) {
        guard history.indices.contains(index) else { return }
        history.removeSubrange(index...)
    }

    mutating func markUndoBlocked(at index: Int) {
        guard history.indices.contains(index) else { return }
        history[index].undoBlocked = true
        unrevisitableIDs.insert(history[index].membershipID)
    }
}

/// Applies and undoes Sort New decisions. Every write goes through the existing
/// queue service; Undo restores only what this decision itself changed, and after
/// a Drop of a queue-only work brings the work back from Recently Deleted only
/// when nothing newer happened on this or another device.
@MainActor
enum QueueSortNew {
    /// The live membership a session id names, while both the queue and work
    /// are still live (not deleted or in Recently Deleted).
    static func membership(_ id: UUID, in queue: ReadingQueue) -> ReadingQueueMembership? {
        guard queue.modelContext != nil, !queue.isPendingDeletion else { return nil }
        return queue.memberships.first {
            $0.id == id
                && !$0.isPendingDeletion
                && $0.work.map { $0.modelContext != nil && !$0.isPendingDeletion } == true
        }
    }

    /// Applies `action` to the session's current work and records it. Returns
    /// false (and records nothing) when that membership is gone or no longer
    /// matches `expectedMembershipID`/`expectedWorkID`.
    @discardableResult
    static func apply(
        _ action: QueueSortAction,
        session: inout QueueSortSession,
        queue: ReadingQueue,
        context: ModelContext,
        expectedMembershipID: UUID? = nil,
        expectedWorkID: UUID? = nil
    ) -> Bool {
        guard queue.id == session.queueID,
              let id = session.currentMembershipID,
              expectedMembershipID == nil || expectedMembershipID == id,
              let record = apply(
                  action,
                  membershipID: id,
                  expectedWorkID: expectedWorkID,
                  in: queue,
                  context: context
              )
        else { return false }
        session.record(record)
        return true
    }

    /// Steps the cursor over works that left the queue, entered Recently Deleted,
    /// became hidden by privacy mode, or failed Undo since the session began.
    static func skipMissing(
        session: inout QueueSortSession,
        queue: ReadingQueue,
        isVisible: (SavedWork) -> Bool = { _ in true }
    ) {
        while let id = session.currentMembershipID {
            guard !session.unrevisitableIDs.contains(id),
                  let membership = membership(id, in: queue),
                  let work = membership.work,
                  isVisible(work)
            else {
                session.record(.skip(membershipID: id))
                continue
            }
            break
        }
    }

    /// Undoes the last undoable decision of the session. Only rewinds the cursor
    /// when persistence succeeds; on refusal keeps the session consistent so the
    /// user stays on the next live work instead of stranding on "All sorted".
    @discardableResult
    static func undo(
        session: inout QueueSortSession,
        queue: ReadingQueue,
        context: ModelContext,
        isVisible: (SavedWork) -> Bool = { _ in true }
    ) -> QueueSortUndoResult {
        guard queue.id == session.queueID, let index = session.lastUndoableIndex else {
            return .nothingToUndo
        }
        let record = session.history[index]
        if undo(record, in: queue, context: context, isVisible: isVisible) {
            session.popFrom(index)
            skipMissing(session: &session, queue: queue, isVisible: isVisible)
            return .undone(record)
        }
        session.markUndoBlocked(at: index)
        skipMissing(session: &session, queue: queue, isVisible: isVisible)
        return .blocked(record)
    }

    static func apply(
        _ action: QueueSortAction,
        membershipID: UUID,
        expectedWorkID: UUID? = nil,
        in queue: ReadingQueue,
        context: ModelContext
    ) -> QueueSortRecord? {
        guard queue.kind != .smart,
              let membership = membership(membershipID, in: queue),
              let work = membership.work,
              expectedWorkID == nil || expectedWorkID == work.id
        else { return nil }
        switch action {
        case .later:
            return QueueSortRecord(
                membershipID: membershipID, workID: work.id, action: .later,
                before: nil, keepOutcome: nil, dropOutcome: nil
            )
        case .keep:
            let before = QueueSortMembershipSnapshot(membership)
            ReadingQueueService.sortIntoLine(membership, in: queue, context: context)
            let outcome = QueueSortKeepOutcome(
                stateRaw: membership.stateRaw,
                stateWasRecorded: membership.stateWasRecorded,
                sortOrderInQueue: membership.sortOrderInQueue
            )
            return QueueSortRecord(
                membershipID: membershipID, workID: work.id, action: .keep,
                before: before, keepOutcome: outcome, dropOutcome: nil
            )
        case .drop:
            let before = QueueSortMembershipSnapshot(membership)
            let wasPendingDeletion = work.isPendingDeletion
            let statusRaw = work.epubPreservationStatusRaw
            let preservedAt = work.preservedAt
            let existingTombstoneIDs = Set(
                ((try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? []).map(\.id)
            )
            ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(work, from: queue, in: context)
            FolderSyncService.markDirty()
            let sentToRD = !wasPendingDeletion && work.isPendingDeletion
            let newTombstones = ((try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? [])
                .filter { !existingTombstoneIDs.contains($0.id) }
            let membershipTombstone = newTombstones
                .first { $0.recordType == .readingQueueMembership && $0.recordID == membershipID }
                .map(QueueSortTombstoneStamp.init)
            let workTombstone = sentToRD
                ? newTombstones
                    .first { $0.recordType == .savedWork && $0.recordID == work.id }
                    .map(QueueSortTombstoneStamp.init)
                : nil
            let outcome = QueueSortDropOutcome(
                sentWorkToRecentlyDeleted: sentToRD,
                preservationStatusRaw: statusRaw,
                preservedAt: preservedAt,
                workDeletedAt: sentToRD ? work.deletedAt : nil,
                membershipTombstone: membershipTombstone,
                workTombstone: workTombstone
            )
            return QueueSortRecord(
                membershipID: membershipID, workID: work.id, action: .drop,
                before: before, keepOutcome: nil, dropOutcome: outcome
            )
        }
    }

    @discardableResult
    static func undo(
        _ record: QueueSortRecord,
        in queue: ReadingQueue,
        context: ModelContext,
        isVisible: (SavedWork) -> Bool = { _ in true }
    ) -> Bool {
        guard queue.kind != .smart, queue.modelContext != nil, !queue.isPendingDeletion else {
            return false
        }
        switch record.action {
        case .later:
            guard let work = membership(record.membershipID, in: queue)?.work, isVisible(work) else {
                return false
            }
            return true
        case .keep:
            guard let before = record.before,
                  let expected = record.keepOutcome,
                  let membership = membership(record.membershipID, in: queue),
                  let work = membership.work,
                  isVisible(work),
                  membership.stateRaw == expected.stateRaw,
                  membership.stateWasRecorded == expected.stateWasRecorded,
                  membership.sortOrderInQueue == expected.sortOrderInQueue
            else { return false }
            // Only revert the three fields Sort New changed; keep intervening
            // edits to note, origin, and queuedAt intact.
            membership.stateRaw = before.stateRaw
            membership.stateWasRecorded = before.stateWasRecorded
            membership.sortOrderInQueue = before.sortOrderInQueue
            let now = Date()
            membership.markModified(now)
            queue.markMembershipChanged(now)
            FolderSyncService.markDirty()
            return context.saveBestEffort(reason: "Undoing Sort New keep failed")
        case .drop:
            return undoDrop(record, in: queue, context: context, isVisible: isVisible)
        }
    }

    private static func undoDrop(
        _ record: QueueSortRecord,
        in queue: ReadingQueue,
        context: ModelContext,
        isVisible: (SavedWork) -> Bool
    ) -> Bool {
        guard let before = record.before,
              let drop = record.dropOutcome,
              let expectedMembershipTombstone = drop.membershipTombstone
        else { return false }
        let workID = record.workID
        var descriptor = FetchDescriptor<SavedWork>(predicate: #Predicate { $0.id == workID })
        descriptor.fetchLimit = 1
        guard let work = try? context.fetch(descriptor).first,
              work.modelContext != nil,
              isVisible(work)
        else { return false }
        // Check before any restore: if the work already joined this queue again
        // (under a new membership id or the same one), refuse rather than
        // mutating or reviving anything.
        guard !work.queueMemberships.contains(where: { $0.queue?.id == queue.id && !$0.isPendingDeletion }) else {
            return false
        }
        guard let allTombstones = try? context.fetch(FetchDescriptor<SyncTombstone>()) else {
            return false
        }
        let membershipTombstones = allTombstones.filter {
            $0.recordType == .readingQueueMembership && $0.recordID == before.id
        }
        guard !membershipTombstones.isEmpty,
              membershipTombstones.allSatisfy({ expectedMembershipTombstone.matches($0) })
        else { return false }

        let workTombstones = matchingWorkTombstones(for: work, in: allTombstones)
        if work.isPendingDeletion {
            guard drop.sentWorkToRecentlyDeleted,
                  let expectedDeletedAt = drop.workDeletedAt,
                  let actualDeletedAt = work.deletedAt,
                  abs(actualDeletedAt.timeIntervalSince(expectedDeletedAt)) <= 0.001,
                  let expectedWorkTombstone = drop.workTombstone,
                  !workTombstones.isEmpty,
                  workTombstones.allSatisfy({ expectedWorkTombstone.matches($0) })
            else { return false }
        } else {
            // A live work with an un-swept `.savedWork` tombstone was deleted
            // elsewhere; never bump `work.lastModifiedAt` past that tombstone.
            guard workTombstones.isEmpty else { return false }
        }

        if drop.sentWorkToRecentlyDeleted, work.isPendingDeletion {
            guard PreservedWorkService.restore(work, in: context) else { return false }
        }
        let membership = ReadingQueueMembership(
            id: before.id,
            queue: queue,
            work: work,
            queuedAt: before.queuedAt,
            sortOrderInQueue: before.sortOrderInQueue,
            note: before.note
        )
        restoreAll(before, onto: membership)
        context.insert(membership)
        queue.memberships.append(membership)
        work.queueMemberships.append(membership)
        // Retract only this Drop's verified membership tombstone(s).
        for tombstone in membershipTombstones {
            context.delete(tombstone)
        }
        let minAfter = max(
            expectedMembershipTombstone.lastModifiedAt,
            drop.workTombstone?.lastModifiedAt ?? .distantPast
        ).addingTimeInterval(0.002)
        let now = max(Date(), minAfter)
        queue.markMembershipChanged(now)
        membership.markModified(now)
        work.markModified(now)
        work.isQueuedForLater = true
        ReadingQueueService.normalize(work)
        if let statusRaw = drop.preservationStatusRaw, work.epubPreservationStatusRaw == statusRaw {
            work.preservedAt = drop.preservedAt
        }
        FolderSyncService.markDirty()
        return context.saveBestEffort(reason: "Undoing Sort New drop failed")
    }

    /// Mirrors `PreservedWorkService.retractTombstone` identity matching so a
    /// foreign `.savedWork` tombstone keyed by `ao3WorkID` or canonical URL is
    /// caught alongside `recordID`.
    private static func matchingWorkTombstones(
        for work: SavedWork,
        in tombstones: [SyncTombstone]
    ) -> [SyncTombstone] {
        let ao3WorkID = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
        let canonical = WorkTags.canonicalAO3WorkURL(from: work.sourceURL)
        return tombstones.filter { tombstone in
            guard tombstone.recordType == .savedWork else { return false }
            if tombstone.recordID == work.id { return true }
            if let ao3WorkID, tombstone.ao3WorkID == ao3WorkID { return true }
            if let canonical, WorkTags.canonicalAO3WorkURL(from: tombstone.sourceURL) == canonical {
                return true
            }
            return false
        }
    }

    /// Writes every stored membership field back when recreating a dropped
    /// membership, bypassing the `state` setter (which always marks recorded).
    private static func restoreAll(_ snapshot: QueueSortMembershipSnapshot, onto membership: ReadingQueueMembership) {
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
