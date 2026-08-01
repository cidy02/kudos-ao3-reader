package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import io.github.cidy02.kudos.data.local.entity.WorkEntity
import java.time.Instant
import kotlinx.coroutines.flow.Flow

@Dao
interface WorkDao {
    // @Upsert performs an in-place UPDATE on primary-key conflict (not DELETE+INSERT),
    // so updating a work never fires the ON DELETE CASCADE on its tag/collection
    // cross-refs. Using @Insert(REPLACE) here silently wiped a work's user tags and
    // collection memberships on every favorite/finished/progress save.
    @Upsert
    suspend fun upsert(work: WorkEntity)

    @Upsert
    suspend fun upsertAll(works: List<WorkEntity>)

    @Query("SELECT * FROM works WHERE id = :id")
    suspend fun getById(id: String): WorkEntity?

    @Query("SELECT * FROM works WHERE id = :id")
    fun observeById(id: String): Flow<WorkEntity?>

    @Query("SELECT * FROM works WHERE sourceUrl = :sourceUrl LIMIT 1")
    suspend fun getBySourceUrl(sourceUrl: String): WorkEntity?

    /** Active library works (excludes soft-deleted). */
    @Query("SELECT * FROM works WHERE isDeleted = 0 ORDER BY dateAdded DESC")
    suspend fun getAll(): List<WorkEntity>

    /** All works including soft-deleted — used by backup capture/export. */
    @Query("SELECT * FROM works ORDER BY dateAdded DESC")
    suspend fun getAllIncludingDeleted(): List<WorkEntity>

    @Query("SELECT * FROM works WHERE isDeleted = 0 ORDER BY dateAdded DESC")
    fun observeAll(): Flow<List<WorkEntity>>

    @Query("SELECT COUNT(*) FROM works WHERE isDeleted = 0")
    suspend fun count(): Int

    /** Soft-deleted works in Recently Deleted (newest first). */
    @Query("SELECT * FROM works WHERE isDeleted = 1 ORDER BY deletedAt DESC")
    suspend fun getDeleted(): List<WorkEntity>

    @Query("SELECT * FROM works WHERE isDeleted = 1 ORDER BY deletedAt DESC")
    fun observeDeleted(): Flow<List<WorkEntity>>

    /**
     * Soft-deleted works whose recovery window has elapsed
     * (`permanentDeletionScheduledAt` ≤ [now]).
     */
    @Query(
        """
        SELECT * FROM works
        WHERE isDeleted = 1
          AND permanentDeletionScheduledAt IS NOT NULL
          AND permanentDeletionScheduledAt <= :now
        """
    )
    suspend fun getExpiredSoftDeletes(now: Instant): List<WorkEntity>

    @Query("DELETE FROM works WHERE id = :id")
    suspend fun deleteById(id: String)
}
