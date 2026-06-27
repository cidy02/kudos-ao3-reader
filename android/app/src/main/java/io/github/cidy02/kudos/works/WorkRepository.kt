package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.CollectionEntity
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.files.WorkFileStore
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class WorkRepository(
    private val database: KudosDatabase,
    private val fileStore: WorkFileStore,
    private val clock: () -> Instant = { Instant.now() },
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() }
) {
    private val workDao = database.workDao()
    private val tagDao = database.tagDao()
    private val collectionDao = database.collectionDao()

    fun observeSavedWorks(): Flow<List<SavedWork>> {
        return workDao.observeAll()
            .map { works -> works.map { it.toDomain() }.filter { it.isSaved } }
    }

    suspend fun getWork(id: String): SavedWork? = workDao.getById(id)?.toDomain()

    suspend fun findBySourceUrl(sourceUrl: String): SavedWork? {
        if (sourceUrl.isBlank()) return null
        return workDao.getBySourceUrl(sourceUrl)?.toDomain()
    }

    suspend fun upsert(work: SavedWork): SavedWork {
        workDao.upsert(work.toEntity())
        return work
    }

    suspend fun setHasEpub(workId: String, hasEpub: Boolean): SavedWork? {
        val work = getWork(workId) ?: return null
        return upsert(work.copy(hasEpub = hasEpub))
    }

    suspend fun toggleFavorite(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        return upsert(work.copy(isFavorite = !work.isFavorite))
    }

    suspend fun toggleFinished(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        return upsert(work.copy(isFinished = !work.isFinished))
    }

    suspend fun deleteLocalEpub(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        fileStore.deleteWorkEpub(workId)
        return upsert(work.copy(hasEpub = false))
    }

    suspend fun removeFromLibrary(workId: String) {
        fileStore.deleteWorkEpub(workId)
        workDao.deleteById(workId)
    }

    suspend fun userTagsForWork(workId: String): List<Tag> {
        return tagDao.getTagsForWork(workId).map { it.toDomain() }
    }

    suspend fun allUserTags(): List<Tag> {
        return tagDao.getAll().map { it.toDomain() }
    }

    suspend fun addUserTag(workId: String, name: String): List<Tag> {
        val trimmed = name.trim()
        require(trimmed.isNotEmpty()) { "Tag name must not be blank." }
        val tag = tagDao.getByNameCaseInsensitive(trimmed) ?: TagEntity(
            id = uuidFactory(),
            name = trimmed,
            dateCreated = clock()
        ).also { tagDao.upsert(it) }
        tagDao.addToWork(WorkTagCrossRef(workId = workId, tagId = tag.id))
        return userTagsForWork(workId)
    }

    suspend fun removeUserTag(workId: String, tagId: String): List<Tag> {
        tagDao.removeFromWork(workId, tagId)
        return userTagsForWork(workId)
    }

    suspend fun collectionsForWork(workId: String): List<WorkCollection> {
        return collectionDao.getCollectionsForWork(workId).map { entity ->
            entity.toDomain(collectionDao.getWorkIdsForCollection(entity.id))
        }
    }

    suspend fun allCollections(): List<WorkCollection> {
        return collectionDao.getAll().map { entity ->
            entity.toDomain(collectionDao.getWorkIdsForCollection(entity.id))
        }
    }

    suspend fun addToCollection(workId: String, name: String): List<WorkCollection> {
        val trimmed = name.trim()
        require(trimmed.isNotEmpty()) { "Collection name must not be blank." }
        val existing = collectionDao.getAll().firstOrNull {
            it.name.equals(trimmed, ignoreCase = true)
        }
        val collection = existing ?: CollectionEntity(
            id = uuidFactory(),
            name = trimmed,
            dateAdded = clock(),
            description = null,
            sortOrder = null
        ).also { collectionDao.upsert(it) }
        collectionDao.addWork(CollectionWorkCrossRef(collection.id, workId))
        return collectionsForWork(workId)
    }

    suspend fun removeFromCollection(workId: String, collectionId: String): List<WorkCollection> {
        collectionDao.removeWork(collectionId, workId)
        return collectionsForWork(workId)
    }
}
