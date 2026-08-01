package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
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

    suspend fun listQueues(): List<ReadingQueue> {
        return queueDao.getActiveQueues().map { it.toDomain() }
    }

    suspend fun getQueue(queueId: String): ReadingQueue? {
        return queueDao.getQueueById(queueId)?.toDomain()
    }

    /**
     * Memberships for [queueId] joined with work titles from WorkDao.
     * Works that were tombstoned/missing still appear with a fallback title.
     */
    suspend fun listWorks(queueId: String): List<QueueMembershipItem> {
        return queueDao.getMembershipsForQueue(queueId).map { membershipEntity ->
            val membership = membershipEntity.toDomain()
            val work = workDao.getById(membership.workID)?.toDomain()
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
        queueDao.deleteMembershipById(existing.id)
        touchQueueMembershipChanged(queueId, clock())
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
