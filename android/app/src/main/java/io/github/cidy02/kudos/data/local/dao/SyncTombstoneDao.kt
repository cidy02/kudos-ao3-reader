package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import io.github.cidy02.kudos.data.local.entity.SyncTombstoneEntity

@Dao
interface SyncTombstoneDao {
    @Upsert
    suspend fun upsert(tombstone: SyncTombstoneEntity)

    @Upsert
    suspend fun upsertAll(tombstones: List<SyncTombstoneEntity>)

    @Query("SELECT * FROM sync_tombstones")
    suspend fun getAll(): List<SyncTombstoneEntity>

    @Query("SELECT * FROM sync_tombstones WHERE recordID = :recordId AND recordTypeRaw = :recordType")
    suspend fun getByRecord(recordId: String, recordType: String): List<SyncTombstoneEntity>

    @Query("DELETE FROM sync_tombstones WHERE id = :id")
    suspend fun deleteById(id: String)

    /** Retract all tombstones for a restored record (Apple PreservedWorkService). */
    @Query("DELETE FROM sync_tombstones WHERE recordID = :recordId AND recordTypeRaw = :recordType")
    suspend fun deleteByRecord(recordId: String, recordType: String)

    /**
     * Identity-aware retract for savedWork: record UUID, ao3WorkID, or source URL
     * (canonical or the original stored value).
     */
    @Query(
        """
        DELETE FROM sync_tombstones
        WHERE recordTypeRaw = :recordType
          AND (
            recordID = :recordId
            OR (:ao3WorkId IS NOT NULL AND ao3WorkID = :ao3WorkId)
            OR (:canonicalSourceUrl != '' AND sourceURL = :canonicalSourceUrl)
            OR (:sourceUrl != '' AND sourceURL = :sourceUrl)
          )
        """
    )
    suspend fun deleteSavedWorkByIdentity(
        recordId: String,
        ao3WorkId: Int?,
        canonicalSourceUrl: String,
        sourceUrl: String,
        recordType: String
    )
}
