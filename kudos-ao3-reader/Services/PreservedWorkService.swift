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

    /// Delete-confirmation copy for a work, escalated when AO3 no longer has it
    /// (`SavedWork.ao3Unavailable`, set from a prior 404 during a tag refresh — no
    /// extra network call needed here): losing the local copy after the recovery
    /// window would mean losing the work entirely, so the user is told plainly.
    static func deleteConfirmationMessage(for work: SavedWork) -> String {
        if work.ao3Unavailable {
            return "“\(work.title)” is no longer available on AO3. If you don't restore it "
                + "within 90 days, this will be the only copy — it can't be re-saved from AO3 afterward."
        }
        return "“\(work.title)” will be moved to Recently Deleted. You can restore it anytime "
            + "in the next 90 days."
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

    static func restore(_ work: SavedWork, in context: ModelContext) {
        work.isPendingDeletion = false
        work.deletedAt = nil
        work.permanentDeletionScheduledAt = nil
        work.markModified()
        retractTombstone(recordID: work.id, type: .savedWork, in: context)
        context.saveBestEffort(reason: "Saving restored work failed")
    }

    static func restore(_ collection: WorkCollection, in context: ModelContext) {
        collection.isPendingDeletion = false
        collection.deletedAt = nil
        collection.permanentDeletionScheduledAt = nil
        collection.markModified()
        retractTombstone(recordID: collection.id, type: .workCollection, in: context)
        context.saveBestEffort(reason: "Saving restored collection failed")
    }

    static func restore(_ queue: ReadingQueue, in context: ModelContext) {
        queue.isPendingDeletion = false
        queue.deletedAt = nil
        queue.permanentDeletionScheduledAt = nil
        queue.markModified()
        retractTombstone(recordID: queue.id, type: .readingQueue, in: context)
        context.saveBestEffort(reason: "Saving restored queue failed")
    }

    /// Deletes the tombstone recorded at soft-delete time, rather than relying on a
    /// timestamp race against a sync from another device — once retracted, nothing
    /// suppresses the record on the next sync from anywhere.
    private static func retractTombstone(
        recordID: UUID,
        type: SyncTombstoneRecordType,
        in context: ModelContext
    ) {
        guard let tombstones = try? context.fetch(FetchDescriptor<SyncTombstone>()) else { return }
        for tombstone in tombstones where tombstone.recordID == recordID && tombstone.recordType == type {
            context.delete(tombstone)
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

    // MARK: - Sweep

    /// Permanently deletes everything past its recovery window. Skipped entirely
    /// while any other persistence operation is running, since permanent deletion
    /// must never race a migration or an in-flight sync's view of what still exists.
    @discardableResult
    static func sweepExpired(in context: ModelContext) -> Int {
        guard PersistenceOperationGate.active == nil else { return 0 }
        let now = Date()
        var count = 0

        if let works = try? context.fetch(FetchDescriptor<SavedWork>()) {
            for work in works {
                guard work.isPendingDeletion, let scheduledAt = work.permanentDeletionScheduledAt, scheduledAt <= now
                else { continue }
                WorkLifecycle.hardDelete(work, in: context)
                count += 1
            }
        }

        if let collections = try? context.fetch(FetchDescriptor<WorkCollection>()) {
            for collection in collections {
                guard collection.isPendingDeletion,
                      let scheduledAt = collection.permanentDeletionScheduledAt,
                      scheduledAt <= now
                else { continue }
                hardDelete(collection, in: context)
                count += 1
            }
        }

        if let queues = try? context.fetch(FetchDescriptor<ReadingQueue>()) {
            for queue in queues {
                guard queue.isPendingDeletion, let scheduledAt = queue.permanentDeletionScheduledAt, scheduledAt <= now
                else { continue }
                hardDelete(queue, in: context)
                count += 1
            }
        }

        if count > 0 {
            Log.library.info("Recently Deleted sweep permanently removed \(count, privacy: .public) record(s)")
        }
        return count
    }
}
