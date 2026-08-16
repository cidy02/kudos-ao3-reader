package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import java.time.Instant

/**
 * One-time reconciliation pass for rows affected by the D8 bug (unsigned tombstones
 * creating pending-deletion schedules instead of hiding instantly).
 */
object D8ReconciliationMigration {
    suspend fun runIfNeeded(
        database: KudosDatabase,
        settingsRepository: SettingsRepository
    ) {
        if (settingsRepository.isD8ReconciliationComplete()) return

        val tombstones = database.syncTombstoneDao().getAll().map { it.toDomain() }
        val tombstoneIndex = TombstoneIndex(
            tombstones = tombstones,
            exportedAt = null,
            now = Instant.now()
        )

        // 1. SavedWorks
        val workDao = database.workDao()
        for (work in workDao.getPendingDeletions().map { it.toDomain() }) {
            val archived = work.toBackupWork()
            // If it doesn't have a trusted tombstone, clear its schedule.
            // (If it DOES have a trusted tombstone, it stays scheduled, matching Phase 1).
            if (!tombstoneIndex.suppressesWorkResurrection(archived)) {
                workDao.clearDeletionSchedule(work.id)
            }
        }

        // 2. WorkCollections
        val collectionDao = database.collectionDao()
        for (collection in collectionDao.getPendingDeletions()) {
            val hasTrustedTombstone = tombstoneIndex.collectionResolution(
                collection.id,
                Instant.MIN // MIN ensures an existing tombstone will suppress
            ) == TombstoneResolution.SUPPRESS_STALE
            if (!hasTrustedTombstone) {
                collectionDao.clearDeletionSchedule(collection.id)
            }
        }

        // 3. ReadingQueues
        val queueDao = database.readingQueueDao()
        for (queue in queueDao.getPendingDeletions()) {
            val hasTrustedTombstone = tombstoneIndex.queueResolution(
                queue.id,
                Instant.MIN
            ) == TombstoneResolution.SUPPRESS_STALE
            if (!hasTrustedTombstone) {
                queueDao.clearDeletionSchedule(queue.id)
            }
        }

        settingsRepository.setD8ReconciliationComplete(true)
    }
}
