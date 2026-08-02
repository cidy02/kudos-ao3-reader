package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.SyncTombstoneEntity
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
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
    private val tombstoneDao = database.syncTombstoneDao()

    suspend fun listQueues(): List<ReadingQueue> {
        return queueDao.getActiveQueues().map { it.toDomain() }
    }

    suspend fun getQueue(queueId: String): ReadingQueue? {
        return queueDao.getQueueById(queueId)?.toDomain()
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
        return membership
    }

    suspend fun removeWork(queueId: String, workId: String) {
        val existing = queueDao.getMembershipForWork(queueId, workId) ?: return
        val now = clock()
        queueDao.deleteMembershipById(existing.id)
        // Without a tombstone, restoring a backup that still lists this membership
        // silently resurrects it (mergeQueues/TombstoneIndex.membershipResolution
        // expect one to exist for every removed membership).
        tombstoneDao.upsert(
            SyncTombstoneEntity(
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

    private suspend fun touchQueueMembershipChanged(queueId: String, now: Instant) {
        val queue = queueDao.getQueueById(queueId) ?: return
        queueDao.upsertQueue(
            queue.copy(
                dateUpdated = now,
                lastMembershipChangedAt = now
            )
        )
    }
}

data class QueueMembershipItem(
    val membership: ReadingQueueMembership,
    val work: SavedWork?,
    val title: String,
    val author: String
)
