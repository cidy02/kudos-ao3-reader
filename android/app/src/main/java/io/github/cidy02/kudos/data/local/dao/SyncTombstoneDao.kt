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
}
