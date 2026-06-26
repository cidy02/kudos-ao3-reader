package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.github.cidy02.kudos.data.local.entity.WorkEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface WorkDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(work: WorkEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(works: List<WorkEntity>)

    @Query("SELECT * FROM works WHERE id = :id")
    suspend fun getById(id: String): WorkEntity?

    @Query("SELECT * FROM works ORDER BY dateAdded DESC")
    fun observeAll(): Flow<List<WorkEntity>>

    @Query("SELECT COUNT(*) FROM works")
    suspend fun count(): Int
}
