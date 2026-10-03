package io.github.cidy02.kudos.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef

@Dao
interface TagDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(tag: TagEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addToWork(crossRef: WorkTagCrossRef)

    @Query("SELECT * FROM user_tags WHERE id = :id")
    suspend fun getById(id: String): TagEntity?

    @Query("SELECT * FROM user_tags WHERE name = :name")
    suspend fun getByName(name: String): TagEntity?

    @Query("SELECT * FROM user_tags WHERE name = :name COLLATE NOCASE LIMIT 1")
    suspend fun getByNameCaseInsensitive(name: String): TagEntity?

    @Query("SELECT * FROM user_tags ORDER BY name COLLATE NOCASE")
    suspend fun getAll(): List<TagEntity>

    @Query("SELECT * FROM user_tags ORDER BY name COLLATE NOCASE")
    fun observeAll(): kotlinx.coroutines.flow.Flow<List<TagEntity>>

    @Query(
        """
        SELECT user_tags.* FROM user_tags
        INNER JOIN work_tag_cross_refs ON user_tags.id = work_tag_cross_refs.tagId
        WHERE work_tag_cross_refs.workId = :workId
        ORDER BY user_tags.name COLLATE NOCASE
        """
    )
    suspend fun getTagsForWork(workId: String): List<TagEntity>

    @Query(
        """
        SELECT work_tag_cross_refs.workId AS workId,
               user_tags.id AS id,
               user_tags.name AS name,
               user_tags.dateCreated AS dateCreated
        FROM user_tags
        INNER JOIN work_tag_cross_refs ON user_tags.id = work_tag_cross_refs.tagId
        ORDER BY user_tags.name COLLATE NOCASE
        """
    )
    fun observeAllWorkTagLinks(): kotlinx.coroutines.flow.Flow<List<WorkTagLink>>

    @Query("DELETE FROM work_tag_cross_refs WHERE workId = :workId AND tagId = :tagId")
    suspend fun removeFromWork(workId: String, tagId: String)
}
