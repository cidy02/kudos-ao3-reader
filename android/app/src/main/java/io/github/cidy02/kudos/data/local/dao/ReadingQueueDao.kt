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

    @Query("SELECT * FROM reading_queues WHERE id = :id")
    suspend fun getQueueById(id: String): ReadingQueueEntity?

    @Query("SELECT * FROM reading_queue_memberships")
    suspend fun getAllMemberships(): List<ReadingQueueMembershipEntity>

    @Query("SELECT * FROM reading_queue_memberships WHERE queueID = :queueId")
    suspend fun getMembershipsForQueue(queueId: String): List<ReadingQueueMembershipEntity>

    @Query("SELECT * FROM reading_queue_memberships WHERE id = :id")
    suspend fun getMembershipById(id: String): ReadingQueueMembershipEntity?

    @Query("DELETE FROM reading_queues WHERE id = :id")
    suspend fun deleteQueueById(id: String)

    @Query("DELETE FROM reading_queue_memberships WHERE id = :id")
    suspend fun deleteMembershipById(id: String)
}
