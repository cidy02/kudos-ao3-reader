package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import io.github.cidy02.kudos.data.local.entity.AnnotationEntity

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

    @Query("SELECT * FROM annotations WHERE workID = :workId")
    suspend fun getForWork(workId: String): List<AnnotationEntity>

    @Query("DELETE FROM annotations WHERE id = :id")
    suspend fun deleteById(id: String)
}
