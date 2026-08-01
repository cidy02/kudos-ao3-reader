package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Upsert
import io.github.cidy02.kudos.data.local.entity.CollectionEntity
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.WorkEntity
import java.time.Instant
import kotlinx.coroutines.flow.Flow

@Dao
interface CollectionDao {
    // @Upsert performs an in-place UPDATE on primary-key conflict (not DELETE+INSERT),
    // so updating a collection never fires the ON DELETE CASCADE on its work cross-refs.
    // @Insert(REPLACE) here silently wiped a collection's work memberships on every
    // rename/lastModifiedAt touch/soft-delete/restore — same bug already fixed once for
    // WorkDao.upsert, for the same reason.
    @Upsert
    suspend fun upsert(collection: CollectionEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addWork(crossRef: CollectionWorkCrossRef)

    @Query("SELECT * FROM collections WHERE id = :id")
    suspend fun getById(id: String): CollectionEntity?

    /** Active collections (excludes soft-deleted). */
    @Query("SELECT * FROM collections WHERE isDeleted = 0 ORDER BY dateAdded DESC")
    suspend fun getAll(): List<CollectionEntity>

    /** All collections including soft-deleted — used by backup capture/export. */
    @Query("SELECT * FROM collections ORDER BY dateAdded DESC")
    suspend fun getAllIncludingDeleted(): List<CollectionEntity>

    /** Soft-deleted collections for Recently Deleted UI (newest deletion first). */
    @Query(
        """
        SELECT * FROM collections
        WHERE isDeleted = 1
        ORDER BY deletedAt DESC, dateAdded DESC
        """
    )
    suspend fun getDeleted(): List<CollectionEntity>

    @Query(
        """
        SELECT * FROM collections
        WHERE isDeleted = 1
        ORDER BY deletedAt DESC, dateAdded DESC
        """
    )
    fun observeDeleted(): Flow<List<CollectionEntity>>

    /**
     * Soft-deleted collections whose recovery window has elapsed
     * (`permanentDeletionScheduledAt` ≤ [now]).
     */
    @Query(
        """
        SELECT * FROM collections
        WHERE isDeleted = 1
          AND permanentDeletionScheduledAt IS NOT NULL
          AND permanentDeletionScheduledAt <= :now
        """
    )
    suspend fun getExpiredSoftDeletes(now: Instant): List<CollectionEntity>

    @Query(
        """
        SELECT collections.* FROM collections
        INNER JOIN collection_work_cross_refs
            ON collections.id = collection_work_cross_refs.collectionId
        WHERE collection_work_cross_refs.workId = :workId AND collections.isDeleted = 0
        ORDER BY collections.dateAdded DESC
        """
    )
    suspend fun getCollectionsForWork(workId: String): List<CollectionEntity>

    @Query(
        """
        SELECT works.* FROM works
        INNER JOIN collection_work_cross_refs
            ON works.id = collection_work_cross_refs.workId
        WHERE collection_work_cross_refs.collectionId = :collectionId AND works.isDeleted = 0
        ORDER BY works.dateAdded DESC
        """
    )
    suspend fun getWorksForCollection(collectionId: String): List<WorkEntity>

    // Deliberately unfiltered by works.isDeleted — this backs both UI reads and
    // BackupRepository's export, and export must keep a soft-deleted work's
    // membership so restoring that work inside its 90-day window also restores
    // its collection membership. UI-facing "N works" counts should use
    // [getActiveWorkIdsForCollection] instead.
    @Query(
        """
        SELECT workId FROM collection_work_cross_refs
        WHERE collectionId = :collectionId
        ORDER BY workId
        """
    )
    suspend fun getWorkIdsForCollection(collectionId: String): List<String>

    /** Work ids for [collectionId] excluding soft-deleted works — for UI counts/lists. */
    @Query(
        """
        SELECT collection_work_cross_refs.workId FROM collection_work_cross_refs
        INNER JOIN works ON works.id = collection_work_cross_refs.workId
        WHERE collection_work_cross_refs.collectionId = :collectionId AND works.isDeleted = 0
        ORDER BY collection_work_cross_refs.workId
        """
    )
    suspend fun getActiveWorkIdsForCollection(collectionId: String): List<String>

    @Query("DELETE FROM collection_work_cross_refs WHERE collectionId = :collectionId AND workId = :workId")
    suspend fun removeWork(collectionId: String, workId: String)

    @Query("DELETE FROM collection_work_cross_refs WHERE collectionId = :collectionId")
    suspend fun removeAllWorks(collectionId: String)

    @Query("DELETE FROM collections WHERE id = :id")
    suspend fun deleteById(id: String)
}
