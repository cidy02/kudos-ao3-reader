package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.github.cidy02.kudos.data.local.entity.SavedSearchEntity

@Dao
interface SavedSearchDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(savedSearch: SavedSearchEntity)

    @Query("SELECT * FROM saved_searches WHERE id = :id")
    suspend fun getById(id: String): SavedSearchEntity?

    @Query("SELECT * FROM saved_searches ORDER BY dateAdded DESC")
    suspend fun getAll(): List<SavedSearchEntity>
}
