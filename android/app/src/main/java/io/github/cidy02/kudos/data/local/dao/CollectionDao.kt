package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.github.cidy02.kudos.data.local.entity.CollectionEntity
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.WorkEntity

@Dao
interface CollectionDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(collection: CollectionEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addWork(crossRef: CollectionWorkCrossRef)

    @Query("SELECT * FROM collections WHERE id = :id")
    suspend fun getById(id: String): CollectionEntity?

    @Query(
        """
        SELECT works.* FROM works
        INNER JOIN collection_work_cross_refs
            ON works.id = collection_work_cross_refs.workId
        WHERE collection_work_cross_refs.collectionId = :collectionId
        ORDER BY works.dateAdded DESC
        """
    )
    suspend fun getWorksForCollection(collectionId: String): List<WorkEntity>

    @Query(
        """
        SELECT workId FROM collection_work_cross_refs
        WHERE collectionId = :collectionId
        ORDER BY workId
        """
    )
    suspend fun getWorkIdsForCollection(collectionId: String): List<String>
}
