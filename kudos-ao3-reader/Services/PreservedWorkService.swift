import Foundation
import OSLog
import SwiftData

/// Soft-delete / restore / sweep for the "Recently Deleted" 90-day recovery window.
/// Deleting a work, collection, or reading queue moves it into a recoverable state
/// instead of an instant, permanent removal — `RecentlyDeletedView` lists everything
/// currently pending, and `sweepExpired` performs the real, permanent deletion once
/// the window ends (or the user asks to delete permanently right away).
@MainActor
enum PreservedWorkService {
    static let recoveryWindow: TimeInterval = 90 * 24 * 60 * 60
    /// The window in the words every ask uses, so they follow the constant.
    static var recoveryWindowText: String { "\(Int(recoveryWindow / 86_400)) days" }

    /// Delete-confirmation copy for a work. Escalated when Kudos cannot fetch the
    /// work again (`WorkRedownloadability`) — gone from AO3, or a non-AO3 import.
    /// A work still on AO3 keeps the ordinary Recently Deleted sentence. Never
    /// called from a network error path: the reason is a durable flag / origin.
    static func deleteConfirmationMessage(for work: SavedWork, permanently: Bool = false) -> String {
        deleteConfirmationMessage(
            title: work.title,
            reason: WorkRedownloadability.of(work),
            permanently: permanently
        )
    }

    /// Bulk Delete from Library / Delete Permanently. Counts the works that
    /// cannot be fetched again: "2 of these 5 can't be downloaded again".
    static func deleteConfirmationMessage(for works: [SavedWork], permanently: Bool = false) -> String {
        if works.count == 1, let work = works.first {
            return deleteConfirmationMessage(for: work, permanently: permanently)
        }
        let irreplaceable = works.reduce(into: 0) { count, work in
            if !WorkRedownloadability.of(work).canRedownload { count += 1 }
        }
        return deleteConfirmationMessage(
            itemCount: works.count,
            irreplaceableCount: irreplaceable,
            permanently: permanently
        )
    }

    /// Same builder the bulk UI uses when the selection mixes works with
    /// collections or queues — `itemCount` is the selection, `irreplaceableCount`
    /// is how many of those works Kudos cannot fetch again.
    static func deleteConfirmationMessage(
        itemCount: Int,
        irreplaceableCount: Int,
        permanently: Bool
    ) -> String {
        if itemCount == 1, irreplaceableCount == 0 {
            return permanently
                ? "Kudos will permanently remove this item and any download, progress, or notes stored with it. "
                    + "The work stays on AO3. You can't undo this."
                : "Kudos will move this work to Recently Deleted. You can restore it for the next \(recoveryWindowText)."
        }
        let base: String
        if permanently {
            let ao3Clause = irreplaceableCount == 0
                ? " The works stay on AO3."
                : ""
            base = "Kudos will permanently remove each item and any download, progress, or notes stored with it."
                + ao3Clause
                + " You can't undo this."
        } else {
            base = "Kudos will move the selected works to Recently Deleted. "
                + "You can restore them for the next \(recoveryWindowText)."
        }
        guard irreplaceableCount > 0, itemCount > 0 else { return base }
        return base + " \(irreplaceableCount) of these \(itemCount) can't be downloaded again."
    }

    static func deleteConfirmationMessage(
        title: String,
        reason: WorkRedownloadability,
        permanently: Bool = false
    ) -> String {
        switch reason {
        case .canRedownload:
            if permanently {
                return "Kudos will permanently remove “\(title)” and any download, progress, or notes "
                    + "stored with it. The work stays on AO3. You can't undo this."
            }
            return "Kudos will move “\(title)” to Recently Deleted. You can restore it for the next "
                + "\(recoveryWindowText)."
        case .noLongerOnAO3:
            if permanently {
                return "“\(title)” is no longer on AO3, so Kudos can't download it again. You can't undo this."
            }
            return "“\(title)” is no longer on AO3, so Kudos can't download it again. It stays in Recently "
                + "Deleted for \(recoveryWindowText), then it's gone for good."
        case .imported:
            let source = reason.importSourcePhrase ?? "a file"
            if permanently {
                return "“\(title)” was imported from \(source). Kudos only downloads from AO3, so this "
                    + "is the only copy."
            }
            return "“\(title)” was imported from \(source). Kudos only downloads from AO3, so this is "
                + "the only copy. It stays in Recently Deleted for \(recoveryWindowText), then it's gone for good."
        }
    }

    /// A work still on AO3 follows the Confirm-before-deleting setting. A work
    /// Kudos cannot fetch again always asks.
    static func shouldConfirmDelete(_ work: SavedWork, settingOn: Bool) -> Bool {
        WorkRedownloadability.of(work).shouldConfirmDelete(settingOn: settingOn)
    }

    // MARK: - Soft delete

    /// Moves a work to Recently Deleted. The EPUB stays on disk for the whole
    /// recovery window so restoring is instant — freeing it is `hardDelete`'s job.
    static func softDelete(_ work: SavedWork, in context: ModelContext) {
        let now = Date()
        work.isPendingDeletion = true
        work.deletedAt = now
        work.permanentDeletionScheduledAt = now.addingTimeInterval(recoveryWindow)
        work.markModified(now)
        SyncTombstones.recordDeletion(of: work, in: context)
        context.saveBestEffort(reason: "Saving soft-deleted work failed")
    }

    /// Moves a collection to Recently Deleted. Its `works` relationship is left
    /// intact (the works themselves were never part of the collection's own
    /// deletion) so restoring brings the collection back exactly as it was.
    static func softDelete(_ collection: WorkCollection, in context: ModelContext) {
        let now = Date()
        collection.isPendingDeletion = true
        collection.deletedAt = now
        collection.permanentDeletionScheduledAt = now.addingTimeInterval(recoveryWindow)
        collection.markModified(now)
        SyncTombstones.recordDeletion(of: collection, in: context)
        context.saveBestEffort(reason: "Saving soft-deleted collection failed")
    }

    /// Moves a reading queue to Recently Deleted. Deliberately does **not** remove
    /// its memberships (unlike the old immediate-delete flow) — they stay exactly as
    /// they are so restoring the queue brings back every work in it, in order. Only
    /// `hardDelete`'s permanent removal actually tears memberships down.
    static func softDelete(_ queue: ReadingQueue, in context: ModelContext) {
        let now = Date()
        queue.isPendingDeletion = true
        queue.deletedAt = now
        queue.permanentDeletionScheduledAt = now.addingTimeInterval(recoveryWindow)
        queue.markModified(now)
        SyncTombstones.recordDeletion(of: queue, in: context)
        context.saveBestEffort(reason: "Saving soft-deleted queue failed")
    }

    // MARK: - Restore

    // These return whether the restore actually persisted. Recently Deleted used
    // to call them as bare statements: the in-memory object flipped, the row
    // vanished from the list, and a failed save left the record still
    // `isPendingDeletion` with its `permanentDeletionScheduledAt` intact — so
    // `sweepExpired` deleted it at the 90-day mark, having told the reader it
    // was rescued. Silence is the whole bug; the caller must be able to speak.

    @discardableResult
    static func restore(_ work: SavedWork, in context: ModelContext) -> Bool {
        work.isPendingDeletion = false
        work.deletedAt = nil
        work.permanentDeletionScheduledAt = nil
        work.markModified()
        retractTombstone(
            recordID: work.id,
            type: .savedWork,
            ao3WorkID: work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL),
            sourceURL: work.sourceURL,
            in: context
        )
        return context.saveBestEffort(reason: "Saving restored work failed")
    }

    @discardableResult
    static func restore(_ collection: WorkCollection, in context: ModelContext) -> Bool {
        collection.isPendingDeletion = false
        collection.deletedAt = nil
        collection.permanentDeletionScheduledAt = nil
        collection.markModified()
        retractTombstone(recordID: collection.id, type: .workCollection, in: context)
        return context.saveBestEffort(reason: "Saving restored collection failed")
    }

    @discardableResult
    static func restore(_ queue: ReadingQueue, in context: ModelContext) -> Bool {
        queue.isPendingDeletion = false
        queue.deletedAt = nil
        queue.permanentDeletionScheduledAt = nil
        queue.markModified()
        retractTombstone(recordID: queue.id, type: .readingQueue, in: context)
        return context.saveBestEffort(reason: "Saving restored queue failed")
    }

    /// Deletes the tombstone recorded at soft-delete time, rather than relying on a
    /// timestamp race against a sync from another device — once retracted, nothing
    /// suppresses the record on the next sync from anywhere.
    ///
    /// `savedWork` tombstones match ao3WorkID or canonical sourceURL or recordID.
    static func retractTombstone(
        recordID: UUID,
        type: SyncTombstoneRecordType,
        ao3WorkID: Int? = nil,
        sourceURL: String = "",
        in context: ModelContext
    ) {
        guard let tombstones = try? context.fetch(FetchDescriptor<SyncTombstone>()) else { return }
        let canonical = WorkTags.canonicalAO3WorkURL(from: sourceURL)
        for tombstone in tombstones where tombstone.recordType == type {
            let idMatch = tombstone.recordID == recordID
            let ao3Match = type == .savedWork
                && ao3WorkID != nil
                && tombstone.ao3WorkID == ao3WorkID
            let urlMatch = type == .savedWork
                && canonical != nil
                && WorkTags.canonicalAO3WorkURL(from: tombstone.sourceURL) == canonical
            if idMatch || ao3Match || urlMatch {
                context.delete(tombstone)
            }
        }
    }

    // MARK: - Permanent (hard) delete

    /// Permanently deletes a collection right away, skipping the rest of its
    /// recovery window. Used by both `RecentlyDeletedView`'s explicit action and
    /// `sweepExpired` once the window naturally lapses.
    static func hardDelete(_ collection: WorkCollection, in context: ModelContext) {
        context.delete(collection)
        context.saveBestEffort(reason: "Saving permanently-deleted collection failed")
    }

    /// Permanently deletes a reading queue right away. Tombstones each membership
    /// before SwiftData's cascade delete rule removes it, and recomputes
    /// `isQueuedForLater` for every affected work — the same bookkeeping
    /// `ReadingQueueService.removeFromQueue` does for a single removal, needed here
    /// since the queue's memberships were left untouched at soft-delete time.
    static func hardDelete(_ queue: ReadingQueue, in context: ModelContext) {
        for membership in queue.memberships {
            SyncTombstones.recordDeletion(of: membership, in: context)
            if let work = membership.work {
                work.queueMemberships.removeAll { $0.id == membership.id }
                work.isQueuedForLater = !work.queueMemberships.isEmpty
            }
        }
        context.delete(queue)
        context.saveBestEffort(reason: "Saving permanently-deleted queue failed")
    }

    /// Recently Deleted's Delete Permanently, per item. Its confirmation can
    /// outlive the item's deleted state — a restore in another window, or sync
    /// bringing it back — so confirming then must leave a live record alone.
    /// Guarded here, not in `WorkLifecycle.hardDelete`, which tests call on live
    /// works on purpose.
    static func deletePermanently(_ work: SavedWork, in context: ModelContext) {
        guard work.isPendingDeletion else { return }
        WorkLifecycle.hardDelete(work, in: context)
    }

    static func deletePermanently(_ collection: WorkCollection, in context: ModelContext) {
        guard collection.isPendingDeletion else { return }
        hardDelete(collection, in: context)
    }

    static func deletePermanently(_ queue: ReadingQueue, in context: ModelContext) {
        guard queue.isPendingDeletion else { return }
        hardDelete(queue, in: context)
    }

    // MARK: - Sweep

    /// Permanently deletes everything past its recovery window. Skipped entirely
    /// while any other persistence operation is running, since permanent deletion
    /// must never race a migration or an in-flight sync's view of what still exists.
    @discardableResult
    static func sweepExpired(in context: ModelContext) -> Int {
        guard PersistenceOperationGate.active == nil else { return 0 }
        let now = Date()
        let count = hardDeletePending(in: context) { scheduledAt in
            scheduledAt.map { $0 <= now } ?? false
        }
        // Recently Deleted's other section: finished, un-kept copies past 60 days.
        WorkLifecycle.sweepHeldCopies(in: context, now: now)
        if count > 0 {
            Log.library.info("Recently Deleted sweep permanently removed \(count, privacy: .public) record(s)")
        }
        return count
    }

    /// Permanently deletes every pending record, whatever is left of its window,
    /// through the same per-kind `hardDelete`s the per-item action and the sweep
    /// use. The Recently Deleted UI no longer offers Delete All (T-469); Select →
    /// Select All → Delete Permanently is the path, and still goes through each
    /// entry's own `deletePermanently`.
    @discardableResult
    static func hardDeleteAllPending(in context: ModelContext) -> Int {
        WorkLifecycle.sweepHeldCopies(in: context, everything: true)
            + hardDeletePending(in: context) { _ in true }
    }

    /// The shared pass: permanently deletes each pending work, collection and
    /// queue whose scheduled deletion date `isDue` accepts.
    private static func hardDeletePending(in context: ModelContext, isDue: (Date?) -> Bool) -> Int {
        var count = 0
        if let works = try? context.fetch(FetchDescriptor<SavedWork>()) {
            for work in works where work.isPendingDeletion && isDue(work.permanentDeletionScheduledAt) {
                deletePermanently(work, in: context)
                count += 1
            }
        }
        if let collections = try? context.fetch(FetchDescriptor<WorkCollection>()) {
            for collection in collections
            where collection.isPendingDeletion && isDue(collection.permanentDeletionScheduledAt) {
                deletePermanently(collection, in: context)
                count += 1
            }
        }
        if let queues = try? context.fetch(FetchDescriptor<ReadingQueue>()) {
            for queue in queues where queue.isPendingDeletion && isDue(queue.permanentDeletionScheduledAt) {
                deletePermanently(queue, in: context)
                count += 1
            }
        }
        return count
    }
}
