package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import io.github.cidy02.kudos.data.local.entity.FandomReadWatermarkEntity
import io.github.cidy02.kudos.data.local.entity.QueueTagCrossRef
import io.github.cidy02.kudos.data.local.entity.ReadingFavoriteEntity
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import kotlinx.coroutines.flow.Flow

/** Storage for the v11 reading-log tables and queue tags. Behaviour lives in repositories. */
@Dao
interface ReadingLogDao {
    @Upsert
    suspend fun upsertSession(session: ReadingSessionEntity)

    @Query("SELECT * FROM reading_sessions ORDER BY startedAt DESC")
    suspend fun getAllSessions(): List<ReadingSessionEntity>

    @Query("SELECT * FROM reading_sessions ORDER BY startedAt DESC")
    fun observeSessions(): Flow<List<ReadingSessionEntity>>

    @Query("DELETE FROM reading_sessions WHERE id = :id")
    suspend fun deleteSession(id: String)

    @Upsert
    suspend fun upsertFavorite(favorite: ReadingFavoriteEntity)

    @Query("SELECT * FROM reading_favorites ORDER BY createdAt DESC")
    suspend fun getAllFavorites(): List<ReadingFavoriteEntity>

    @Query("SELECT * FROM reading_favorites ORDER BY createdAt DESC")
    fun observeFavorites(): Flow<List<ReadingFavoriteEntity>>

    @Query("DELETE FROM reading_favorites WHERE id = :id")
    suspend fun deleteFavorite(id: String)

    @Upsert
    suspend fun upsertWatermark(watermark: FandomReadWatermarkEntity)

    @Query("SELECT * FROM fandom_read_watermarks")
    suspend fun getAllWatermarks(): List<FandomReadWatermarkEntity>

    @Query("SELECT * FROM fandom_read_watermarks")
    fun observeWatermarks(): Flow<List<FandomReadWatermarkEntity>>

    @Query("SELECT * FROM fandom_read_watermarks WHERE fandomName = :name LIMIT 1")
    suspend fun getWatermark(name: String): FandomReadWatermarkEntity?

    @Query("DELETE FROM fandom_read_watermarks WHERE id = :id")
    suspend fun deleteWatermark(id: String)

    @Upsert
    suspend fun upsertQueueTag(ref: QueueTagCrossRef)

    @Query("SELECT * FROM queue_tag_cross_refs WHERE queueId = :queueId")
    suspend fun getQueueTags(queueId: String): List<QueueTagCrossRef>

    @Query("SELECT * FROM queue_tag_cross_refs")
    suspend fun getAllQueueTags(): List<QueueTagCrossRef>

    @Query("DELETE FROM queue_tag_cross_refs WHERE queueId = :queueId AND tagId = :tagId")
    suspend fun deleteQueueTag(queueId: String, tagId: String)
}
