package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.github.cidy02.kudos.data.local.entity.BookmarkEntity

@Dao
interface BookmarkDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(bookmark: BookmarkEntity)

    @Query("SELECT * FROM bookmarks WHERE id = :id")
    suspend fun getById(id: String): BookmarkEntity?

    @Query("SELECT * FROM bookmarks WHERE urlString = :urlString")
    suspend fun getByUrl(urlString: String): BookmarkEntity?
}
