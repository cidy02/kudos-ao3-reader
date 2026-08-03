package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import io.github.cidy02.kudos.data.local.entity.ReadingQueueEntity
import io.github.cidy02.kudos.data.local.entity.ReadingQueueMembershipEntity

@Dao
interface ReadingQueueDao {
    @Upsert
    suspend fun upsertQueue(queue: ReadingQueueEntity)

    @Upsert
    suspend fun upsertMembership(membership: ReadingQueueMembershipEntity)

    @Query("SELECT * FROM reading_queues ORDER BY sortOrder ASC, name ASC")
    suspend fun getAllQueues(): List<ReadingQueueEntity>

    @Query(
        """
        SELECT * FROM reading_queues
        WHERE isDeleted = 0
        ORDER BY sortOrder ASC, name ASC
        """
    )
    suspend fun getActiveQueues(): List<ReadingQueueEntity>

    @Query("SELECT * FROM reading_queues WHERE id = :id")
    suspend fun getQueueById(id: String): ReadingQueueEntity?

    @Query(
        """
        SELECT * FROM reading_queues
        WHERE kindRaw = :kindRaw AND isDeleted = 0
        ORDER BY sortOrder ASC, name ASC
        LIMIT 1
        """
    )
    suspend fun getActiveQueueByKind(kindRaw: String): ReadingQueueEntity?

    @Query("SELECT * FROM reading_queue_memberships")
    suspend fun getAllMemberships(): List<ReadingQueueMembershipEntity>

    @Query(
        """
        SELECT * FROM reading_queue_memberships
        WHERE queueID = :queueId
        ORDER BY sortOrderInQueue ASC, queuedAt ASC
        """
    )
    suspend fun getMembershipsForQueue(queueId: String): List<ReadingQueueMembershipEntity>

    @Query(
        """
        SELECT * FROM reading_queue_memberships
        WHERE queueID = :queueId AND workID = :workId
        LIMIT 1
        """
    )
    suspend fun getMembershipForWork(queueId: String, workId: String): ReadingQueueMembershipEntity?

    @Query("SELECT * FROM reading_queue_memberships WHERE id = :id")
    suspend fun getMembershipById(id: String): ReadingQueueMembershipEntity?

    @Query("DELETE FROM reading_queues WHERE id = :id")
    suspend fun deleteQueueById(id: String)

    @Query("DELETE FROM reading_queue_memberships WHERE id = :id")
    suspend fun deleteMembershipById(id: String)

    @Query(
        """
        DELETE FROM reading_queue_memberships
        WHERE queueID = :queueId AND workID = :workId
        """
    )
    suspend fun deleteMembershipForWork(queueId: String, workId: String)

    @Query(
        """
        SELECT COUNT(*) FROM reading_queue_memberships m
        INNER JOIN reading_queues q ON m.queueID = q.id
        WHERE m.workID = :workId AND q.isDeleted = 0
        """
    )
    suspend fun getActiveMembershipCountForWork(workId: String): Int
}
