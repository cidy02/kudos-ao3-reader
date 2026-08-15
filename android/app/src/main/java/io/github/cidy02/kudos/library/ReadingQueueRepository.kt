package io.github.cidy02.kudos.library

import androidx.room.withTransaction
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.works.WorkTags
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.delay
import kotlin.math.max
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkImportResult
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.time.Instant
import java.util.UUID

/**
 * Local reading-queue membership API (Apple ReadingQueueService subset).
 * Uses existing [io.github.cidy02.kudos.data.local.dao.ReadingQueueDao] + WorkDao.
 */
class ReadingQueueRepository(
    private val database: KudosDatabase,
    private val clock: () -> Instant = { Instant.now() },
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() }
) {
    private val queueDao = database.readingQueueDao()
    private val workDao = database.workDao()
    private val tagDao = database.tagDao()
    private val collectionDao = database.collectionDao()
    private val tombstoneDao = database.syncTombstoneDao()

    suspend fun listQueues(): List<ReadingQueue> {
        return queueDao.getActiveQueues().map { it.toDomain() }
    }

    suspend fun getQueue(queueId: String): ReadingQueue? {
        return queueDao.getQueueById(queueId)?.toDomain()
    }

    /** Active (non-deleted-queue) membership count for multi-queue "In N" badges. */
    suspend fun activeMembershipCountForWork(workId: String): Int {
        return queueDao.getActiveMembershipCountForWork(workId)
    }

    /**
     * Memberships for [queueId] joined with work titles from WorkDao, excluding
     * works currently soft-deleted (Recently Deleted) — same as Collections'
     * getActiveWorkIdsForCollection. The membership row itself is untouched, so a
     * restored work reappears here automatically. Works missing outright (hard
     * deleted/tombstoned) still appear with a fallback title.
     */
    suspend fun listWorks(queueId: String): List<QueueMembershipItem> {
        return queueDao.getMembershipsForQueue(queueId).mapNotNull { membershipEntity ->
            val membership = membershipEntity.toDomain()
            val work = workDao.getById(membership.workID)?.toDomain()
            if (work?.isDeleted == true) return@mapNotNull null
            QueueMembershipItem(
                membership = membership,
                work = work,
                title = work?.title?.takeIf { it.isNotBlank() } ?: "Missing work",
                author = work?.author.orEmpty()
            )
        }
    }

    suspend fun addWork(queueId: String, workId: String): ReadingQueueMembership {
        val queue = queueDao.getQueueById(queueId)
            ?: error("Queue not found: $queueId")
        require(!queue.isDeleted) { "Cannot add works to a deleted queue." }

        queueDao.getMembershipForWork(queueId, workId)?.let { return it.toDomain() }

        val now = clock()
        val nextOrder = queueDao.getMembershipsForQueue(queueId)
            .maxOfOrNull { it.sortOrderInQueue }
            ?.plus(1)
            ?: 0
        val membership = ReadingQueueMembership(
            id = uuidFactory(),
            queueID = queueId,
            workID = workId,
            queuedAt = now,
            lastModifiedAt = now,
            sortOrderInQueue = nextOrder
        )
        queueDao.upsertMembership(membership.toEntity())
        touchQueueMembershipChanged(queueId, now)

        // Queue-add localizes a not-yet-local work as queue-only (T-89), but a work
        // that was already local (e.g. reading history) needs the flag stamped here
        // too - this runs for every addWork caller, not just the ones that already
        // went through WorkDetailScreen's queue-add localize path.
        val workEntity = workDao.getById(workId)
        if (workEntity != null && !workEntity.isQueuedForLater) {
            workDao.upsert(workEntity.copy(isQueuedForLater = true, lastModifiedAt = now))
        }

        return membership
    }

    suspend fun removeWork(queueId: String, workId: String) {
        val existing = queueDao.getMembershipForWork(queueId, workId) ?: return
        val now = clock()

        queueDao.deleteMembershipById(existing.id)
        // Without a tombstone, restoring a backup that still lists this membership
        // silently resurrects it (mergeQueues/TombstoneIndex.membershipResolution
        // expect one to exist for every removed membership).
        upsertSignedTombstone(
            SyncTombstone(
                id = uuidFactory(),
                recordID = existing.id,
                recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP,
                createdAt = now,
                lastModifiedAt = now,
                deletedOnDeviceID = "",
                deletionReason = "queueMembershipRemoved"
            )
        )
        touchQueueMembershipChanged(queueId, now)

        // iOS parity: removeFromQueueAndDeleteIfQueueOnly. Once a work loses its last
        // queue membership, clear the flag; if it was queue-only (never explicitly
        // saved or favorited), the user is abandoning it entirely - soft-delete it
        // the same way any other removal goes to Recently Deleted, rather than
        // leaving an orphaned, invisible row behind forever.
        //
        // Re-read the row here rather than reusing an entity fetched before the
        // membership delete above: this suspends across several DB writes
        // (tombstone insert, queue touch), a real window for something else -
        // a completed download setting hasEpub, a favorite toggle - to have
        // changed the row in the meantime. Deciding and writing from a stale
        // snapshot could soft-delete a work that just became protected, or
        // clobber a concurrent field change.
        val freshEntity = workDao.getById(workId)
        if (freshEntity != null) {
            val remainingCount = queueDao.getActiveMembershipCountForWork(workId)
            // Must read isQueueOnlyWork from the still-queued entity, before the
            // flag gets cleared below - isQueueOnlyWork is defined in terms of
            // isQueuedForLater, so checking it on the already-cleared copy would
            // always read false regardless of prior state.
            val wasQueueOnly = freshEntity.toDomain().isQueueOnlyWork
            if (remainingCount == 0 && freshEntity.isQueuedForLater) {
                val cleared = freshEntity.copy(isQueuedForLater = false, lastModifiedAt = now)
                if (wasQueueOnly) {
                    workDao.upsert(
                        cleared.copy(
                            isDeleted = true,
                            deletedAt = now,
                            permanentDeletionScheduledAt = now.plus(WorkRepository.RECOVERY_WINDOW)
                        )
                    )
                } else {
                    workDao.upsert(cleared)
                }
            }
        }
    }

    
    suspend fun removeFromAllQueuesAndDeleteIfQueueOnly(workId: String) {
        val memberships = queueDao.getMembershipsForWork(workId)
        for (membership in memberships) {
            removeWork(membership.queueID, workId)
        }
    }

    suspend fun ensureSavedForLaterQueue(): ReadingQueue {
        queueDao.getActiveQueueByKind(ReadingQueueKind.SAVED_FOR_LATER)?.let {
            return it.toDomain()
        }
        val now = clock()
        val queue = ReadingQueue(
            id = uuidFactory(),
            name = ReadingQueueKind.SAVED_FOR_LATER_NAME,
            kindRaw = ReadingQueueKind.SAVED_FOR_LATER,
            sortOrder = 0,
            dateCreated = now,
            dateUpdated = now
        )
        queueDao.upsertQueue(queue.toEntity())
        return queue
    }

    /** Creates a user-named custom queue (Library “+ New Queue”). */
    suspend fun createQueue(name: String): ReadingQueue {
        val trimmed = name.trim()
        require(trimmed.isNotEmpty()) { "Queue name must not be blank." }
        val existing = queueDao.getActiveQueues().firstOrNull {
            it.name.equals(trimmed, ignoreCase = true) &&
                it.kindRaw == ReadingQueueKind.CUSTOM
        }
        if (existing != null) return existing.toDomain()

        val now = clock()
        val nextOrder = (queueDao.getActiveQueues().maxOfOrNull { it.sortOrder } ?: -1) + 1
        val queue = ReadingQueue(
            id = uuidFactory(),
            name = trimmed,
            kindRaw = ReadingQueueKind.CUSTOM,
            sortOrder = nextOrder,
            dateCreated = now,
            dateUpdated = now
        )
        queueDao.upsertQueue(queue.toEntity())
        return queue
    }

    suspend fun addToSavedForLater(workId: String): ReadingQueueMembership {
        val queue = ensureSavedForLaterQueue()
        return addWork(queue.id, workId)
    }

    suspend fun isInSavedForLater(workId: String): Boolean {
        val queue = queueDao.getActiveQueueByKind(ReadingQueueKind.SAVED_FOR_LATER) ?: return false
        return queueDao.getMembershipForWork(queue.id, workId) != null
    }

    suspend fun removeFromSavedForLater(workId: String) {
        val queue = queueDao.getActiveQueueByKind(ReadingQueueKind.SAVED_FOR_LATER) ?: return
        removeWork(queue.id, workId)
    }

    suspend fun renameQueue(queueId: String, newName: String) {
        val trimmed = newName.trim()
        require(trimmed.isNotEmpty()) { "Queue name must not be blank." }
        val queue = queueDao.getQueueById(queueId) ?: return
        require(queue.kindRaw != ReadingQueueKind.SAVED_FOR_LATER) { "Cannot rename system queues." }
        queueDao.upsertQueue(
            queue.copy(
                name = trimmed,
                dateUpdated = clock()
            )
        )
    }

    suspend fun deleteQueue(queueId: String) {
        val queue = queueDao.getQueueById(queueId) ?: return
        require(queue.kindRaw != ReadingQueueKind.SAVED_FOR_LATER) { "Cannot delete system queues." }
        val now = clock()
        queueDao.upsertQueue(
            queue.copy(
                isDeleted = true,
                deletedAt = now,
                permanentDeletionScheduledAt = now.plus(WorkRepository.RECOVERY_WINDOW),
                dateUpdated = now
            )
        )
    }

    suspend fun updateSortOrder(queueId: String, workIds: List<String>) {
        val now = clock()
        database.withTransaction {
            workIds.forEachIndexed { index, workId ->
                queueDao.getMembershipForWork(queueId, workId)?.let { membership ->
                    queueDao.upsertMembership(
                        membership.copy(
                            sortOrderInQueue = index,
                            lastModifiedAt = now
                        )
                    )
                }
            }
        }
        touchQueueMembershipChanged(queueId, now)
    }

    suspend fun listRecentlyDeletedQueues(): List<ReadingQueue> {
        return queueDao.getAllQueues().filter { it.isDeleted }.map { it.toDomain() }
    }

    suspend fun restoreQueueFromRecentlyDeleted(queueId: String): ReadingQueue? {
        val queue = queueDao.getQueueById(queueId) ?: return null
        val now = clock()
        val restored = queue.copy(
            isDeleted = false,
            deletedAt = null,
            permanentDeletionScheduledAt = null,
            dateUpdated = now
        )
        queueDao.upsertQueue(restored)
        tombstoneDao.deleteByRecord(queueId, SyncTombstoneRecordType.READING_QUEUE)
        return restored.toDomain()
    }

    suspend fun hardDeleteQueue(queueId: String) {
        queueDao.deleteQueueById(queueId)
        // Membership rows cascade via FK in DB.
        val now = clock()
        upsertSignedTombstone(
            SyncTombstone(
                id = uuidFactory(),
                recordID = queueId,
                recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE,
                createdAt = now,
                lastModifiedAt = now,
                deletedOnDeviceID = "",
                deletionReason = "queueDeleted"
            )
        )
    }

    suspend fun sweepExpiredQueueSoftDeletes(): Int {
        val now = clock()
        val expired = queueDao.getAllQueues().filter { 
            it.isDeleted && it.permanentDeletionScheduledAt != null && it.permanentDeletionScheduledAt!! <= now 
        }
        for (entity in expired) {
            hardDeleteQueue(entity.id)
        }
        return expired.size
    }

    fun observeAllUserTags(): Flow<List<Tag>> {
        return tagDao.observeAll().map { tags -> tags.map { it.toDomain() } }
    }

    fun observeAllCollections(): Flow<List<WorkCollection>> {
        return collectionDao.observeAllActive().map { entities ->
            entities.map { it.toDomain() }
        }
    }

    private suspend fun upsertSignedTombstone(tombstone: SyncTombstone) {
        tombstoneDao.upsert(TombstoneSigning.sign(tombstone).toEntity())
    }

    private suspend fun touchQueueMembershipChanged(queueId: String, now: Instant) {
        val queue = queueDao.getQueueById(queueId) ?: return
        queueDao.upsertQueue(
            queue.copy(
                dateUpdated = now,
                lastMembershipChangedAt = now
            )
        )
    }

    suspend fun preserveSeries(
        seriesUrl: String,
        targetQueues: List<ReadingQueue>?,
        seriesRepository: AO3SeriesRepository,
        workImporter: WorkImporter,
        pauseMillis: Long = 2000L,
        progress: ((SeriesPreservationResult) -> Unit)? = null,
        enqueueDownload: ((AO3WorkSummary) -> Unit)? = null
    ): SeriesPreservationResult {
        if (seriesUrl.isBlank()) return SeriesPreservationResult()

        val summaries = try {
            when (val result = seriesRepository.seriesWorks(seriesUrl)) {
                is AO3Result.Success -> result.value
                is AO3Result.Failure -> return SeriesPreservationResult(failed = 1)
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            return SeriesPreservationResult(cancelled = 1)
        } catch (e: Exception) {
            return SeriesPreservationResult(failed = 1)
        }

        return preserveSeries(
            summaries = summaries,
            targetQueues = targetQueues,
            workImporter = workImporter,
            pauseMillis = pauseMillis,
            progress = progress,
            enqueueDownload = enqueueDownload
        )
    }

    suspend fun preserveSeries(
        summaries: List<AO3WorkSummary>,
        targetQueues: List<ReadingQueue>?,
        workImporter: WorkImporter,
        pauseMillis: Long = 2000L,
        progress: ((SeriesPreservationResult) -> Unit)? = null,
        enqueueDownload: ((AO3WorkSummary) -> Unit)? = null
    ): SeriesPreservationResult {
        val result = SeriesPreservationResult(total = summaries.size)
        val queues = targetQueues ?: listOf(ensureSavedForLaterQueue())
        progress?.invoke(result.copy())

        for (summary in summaries) {
            if (!currentCoroutineContext().isActive) {
                result.cancelled += max(0, result.total - result.completed)
                progress?.invoke(result.copy())
                break
            }

            val existing = workDao.getBySourceUrl(summary.workUrl)?.toDomain()
                ?: workDao.getById(summary.id.toString())?.toDomain()

            if (existing != null) {
                if (existing.isDeleted) {
                    val now = clock()
                    val entity = workDao.getById(existing.id)
                    if (entity != null) {
                        workDao.upsert(entity.copy(
                            isDeleted = false,
                            deletedAt = null,
                            permanentDeletionScheduledAt = null,
                            lastModifiedAt = now
                        ))
                        val ao3Id = WorkTags.ao3WorkIdFromUrl(existing.sourceUrl)
                            ?.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }
                            ?.toInt()
                        tombstoneDao.deleteSavedWorkByIdentity(
                            recordId = existing.id,
                            ao3WorkId = ao3Id,
                            canonicalSourceUrl = WorkTags.canonicalAO3WorkURL(existing.sourceUrl)
                                .orEmpty(),
                            sourceUrl = existing.sourceUrl,
                            recordType = SyncTombstoneRecordType.SAVED_WORK
                        )
                    }
                }

                val isInAllQueues = queues.all { q ->
                    queueDao.getMembershipForWork(q.id, existing.id) != null
                }

                if (existing.hasEpub && isInAllQueues) {
                    result.alreadyPreserved += 1
                    progress?.invoke(result.copy())
                    continue
                }

                if (existing.hasEpub) {
                    for (queue in queues) {
                        addWork(queue.id, existing.id)
                    }
                    result.alreadyPreserved += 1
                    progress?.invoke(result.copy())
                    continue
                }
            }

            if (queues.isEmpty()) {
                result.skipped += 1
                progress?.invoke(result.copy())
                continue
            }

            try {
                currentCoroutineContext().ensureActive()
                val importResult = workImporter.saveMetadataOnly(
                    summary,
                    markSaved = false,
                    isQueuedForLater = true
                )
                when (importResult) {
                    is WorkImportResult.Success -> {
                        val saved = importResult.work
                        for (queue in queues) {
                            addWork(queue.id, saved.id)
                        }
                        enqueueDownload?.invoke(summary)
                        result.preserved += 1
                    }
                    is WorkImportResult.Failure -> {
                        result.failed += 1
                    }
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                result.cancelled += max(1, result.total - result.completed)
                progress?.invoke(result.copy())
                break
            } catch (e: Exception) {
                result.failed += 1
            }
            progress?.invoke(result.copy())

            if (result.completed < result.total && pauseMillis > 0) {
                try {
                    delay(pauseMillis)
                } catch (e: kotlinx.coroutines.CancellationException) {
                    result.cancelled += max(0, result.total - result.completed)
                    progress?.invoke(result.copy())
                    break
                }
            }
        }
        return result
    }
}

data class QueueMembershipItem(
    val membership: ReadingQueueMembership,
    val work: SavedWork?,
    val title: String,
    val author: String
)
