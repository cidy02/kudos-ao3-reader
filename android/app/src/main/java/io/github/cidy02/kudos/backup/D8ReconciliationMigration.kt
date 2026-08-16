package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.preferences.SettingsRepository

/**
 * One-time reconciliation for rows the D8 bug already scheduled.
 *
 * Pre-fix unsigned `isDeleted` merges left records in
 * `isDeleted && permanentDeletionScheduledAt != null` with no local
 * [io.github.cidy02.kudos.core.model.SyncTombstone]. Those clocks must be
 * disarmed before [io.github.cidy02.kudos.works.WorkRepository.sweepExpiredSoftDeletes]
 * can mint a signed tombstone from them.
 *
 * Identity match is the same fallback chain as tombstone retract /
 * [TombstoneIndex]: AO3 work ID → canonical URL → record ID for works;
 * record ID for collections and queues. Recency is not required — any
 * matching local tombstone means a trusted delete was recorded here.
 */
object D8ReconciliationMigration {
    suspend fun runIfNeeded(
        database: KudosDatabase,
        settingsRepository: SettingsRepository
    ) {
        if (settingsRepository.isD8ReconciliationComplete()) return

        val tombstones = database.syncTombstoneDao().getAll().map { it.toDomain() }
        val tombstoneIndex = TombstoneIndex(tombstones = tombstones)

        val workDao = database.workDao()
        for (work in workDao.getPendingDeletions().map { it.toDomain() }) {
            if (!tombstoneIndex.hasLocalWorkTombstone(work)) {
                workDao.clearDeletionSchedule(work.id)
            }
        }

        val collectionDao = database.collectionDao()
        for (collection in collectionDao.getPendingDeletions()) {
            if (!tombstoneIndex.hasLocalCollectionTombstone(collection.id)) {
                collectionDao.clearDeletionSchedule(collection.id)
            }
        }

        val queueDao = database.readingQueueDao()
        for (queue in queueDao.getPendingDeletions()) {
            if (!tombstoneIndex.hasLocalQueueTombstone(queue.id)) {
                queueDao.clearDeletionSchedule(queue.id)
            }
        }

        settingsRepository.setD8ReconciliationComplete(true)
    }
}
