package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Upsert
import io.github.cidy02.kudos.data.local.entity.AnnotationEntity
import io.github.cidy02.kudos.data.local.entity.SyncTombstoneEntity

@Dao
interface AnnotationDao {
    @Upsert
    suspend fun upsert(annotation: AnnotationEntity)

    @Upsert
    suspend fun upsertAll(annotations: List<AnnotationEntity>)

    @Query("SELECT * FROM annotations")
    suspend fun getAll(): List<AnnotationEntity>

    @Query("SELECT * FROM annotations WHERE id = :id")
    suspend fun getById(id: String): AnnotationEntity?

    @Query("SELECT * FROM annotations WHERE workID = :workId AND isPendingDeletion = 0 ORDER BY spineIndex ASC, progression ASC")
    fun observeForWork(workId: String): kotlinx.coroutines.flow.Flow<List<AnnotationEntity>>

    /** Every row for the work, pending deletion included (hard delete clears them all). */
    @Query("SELECT * FROM annotations WHERE workID = :workId")
    suspend fun getAllForWork(workId: String): List<AnnotationEntity>

    @Query("DELETE FROM annotations WHERE id = :id")
    suspend fun deleteById(id: String)

    /** One Room transaction across both DAOs; marker first, then the immediate delete. */
    @Transaction
    suspend fun deleteWithTombstone(id: String, tombstone: SyncTombstoneEntity, tombstoneDao: SyncTombstoneDao) {
        tombstoneDao.upsert(tombstone)
        deleteById(id)
    }
}
