package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.github.cidy02.kudos.data.local.entity.CustomFontEntity

@Dao
interface CustomFontDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(font: CustomFontEntity)

    @Query("SELECT * FROM custom_fonts WHERE id = :id")
    suspend fun getById(id: String): CustomFontEntity?

    @Query("SELECT * FROM custom_fonts WHERE fileName = :fileName")
    suspend fun getByFileName(fileName: String): CustomFontEntity?
}
