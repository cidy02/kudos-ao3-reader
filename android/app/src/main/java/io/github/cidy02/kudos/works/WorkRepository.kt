package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.CollectionEntity
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.SyncTombstoneEntity
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.files.WorkFileStore
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Library work persistence. Soft-delete / Recently Deleted follows Apple
 * `PreservedWorkService`: delete → 90-day recoverable window (EPUB kept) →
 * permanent hard-delete (EPUB + row removed, tombstone retained).
 */
class WorkRepository(
    private val database: KudosDatabase,
    private val fileStore: WorkFileStore,
    private val clock: () -> Instant = { Instant.now() },
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() }
) {
    private val workDao = database.workDao()
    private val tagDao = database.tagDao()
    private val collectionDao = database.collectionDao()
    private val tombstoneDao = database.syncTombstoneDao()

    fun observeSavedWorks(): Flow<List<SavedWork>> {
        return workDao.observeAll()
            .map { works -> works.map { it.toDomain() }.filter { it.isSaved } }
    }

    /** Soft-deleted works in Recently Deleted (newest first). */
    fun observeRecentlyDeleted(): Flow<List<SavedWork>> {
        return workDao.observeDeleted().map { works -> works.map { it.toDomain() } }
    }

    suspend fun listRecentlyDeleted(): List<SavedWork> {
        return workDao.getDeleted().map { it.toDomain() }
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
        return upsert(work.copy(hasEpub = hasEpub, lastModifiedAt = clock()))
    }

    suspend fun toggleFavorite(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        return upsert(work.copy(isFavorite = !work.isFavorite, lastModifiedAt = clock()))
    }

    suspend fun toggleFinished(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        return setFinished(workId, !work.isFinished)
    }

    /**
     * Apple `WorkLifecycle.markFinished` / `markStillReading` parity:
     * - Mark finished: set flag; if the work is **not** protected (saved/favorite),
     *   free the local EPUB (history-only entry).
     * - Mark unfinished: clear flag only — never auto-restore the EPUB.
     */
    suspend fun setFinished(workId: String, finished: Boolean): SavedWork? {
        val work = getWork(workId) ?: return null
        if (work.isFinished == finished) return work
        val now = clock()
        return if (finished) {
            var next = work.copy(isFinished = true, lastModifiedAt = now)
            if (!next.isProtected && next.hasEpub) {
                fileStore.deleteWorkEpub(workId)
                next = next.copy(hasEpub = false)
            }
            upsert(next)
        } else {
            upsert(work.copy(isFinished = false, lastModifiedAt = now))
        }
    }

    suspend fun deleteLocalEpub(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        fileStore.deleteWorkEpub(workId)
        return upsert(work.copy(hasEpub = false, lastModifiedAt = clock()))
    }

    /**
     * Moves a work to Recently Deleted for [RECOVERY_WINDOW]. Keeps the EPUB on
     * disk so restore is instant. Records a sync tombstone so a stale backup
     * cannot resurrect the work while it remains deleted (Apple softDelete).
     */
    suspend fun softDelete(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        val now = clock()
        val updated = work.copy(
            isDeleted = true,
            deletedAt = now,
            permanentDeletionScheduledAt = now.plus(RECOVERY_WINDOW),
            lastModifiedAt = now
        )
        upsert(updated)
        recordWorkTombstone(updated, now, deletionReason = "workDeleted")
        return updated
    }

    /**
     * Restores a soft-deleted work to the active library and retracts any
     * savedWork tombstones for its id (Apple PreservedWorkService.restore).
     */
    suspend fun restoreFromRecentlyDeleted(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        val now = clock()
        val restored = work.copy(
            isDeleted = false,
            deletedAt = null,
            permanentDeletionScheduledAt = null,
            lastModifiedAt = now
        )
        upsert(restored)
        retractWorkTombstone(workId)
        return restored
    }

    /** Soft-deleted works for Recently Deleted UI (newest deletion first). */
    fun observeRecentlyDeleted(): Flow<List<SavedWork>> {
        return workDao.observeDeleted().map { works -> works.map { it.toDomain() } }
    }

    suspend fun listRecentlyDeleted(): List<SavedWork> {
        return workDao.getDeleted().map { it.toDomain() }
    }

    /**
     * Permanently removes the work row and local EPUB, and records a sync
     * tombstone so a later backup import does not resurrect it by UUID.
     * Used by "Delete forever" and [sweepExpiredSoftDeletes].
     */
    suspend fun hardDelete(workId: String) {
        val work = getWork(workId)
        fileStore.deleteWorkEpub(workId)
        workDao.deleteById(workId)
        if (work != null) {
            recordWorkTombstone(work, clock(), deletionReason = "workDeleted")
        }
    }

    /**
     * Legacy entry point: permanent removal. Delegates to [hardDelete].
     * Everyday UI deletion should prefer [softDelete] once Recently Deleted UI lands.
     */
    suspend fun removeFromLibrary(workId: String) {
        hardDelete(workId)
    }

    /**
     * Permanently deletes soft-deleted works past
     * `permanentDeletionScheduledAt`. Returns how many works were removed.
     */
    suspend fun sweepExpiredSoftDeletes(): Int {
        val now = clock()
        val expired = workDao.getExpiredSoftDeletes(now)
        for (entity in expired) {
            hardDelete(entity.id)
        }
        return expired.size
    }

    private suspend fun recordWorkTombstone(
        work: SavedWork,
        now: Instant,
        deletionReason: String
    ) {
        val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
            ?.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }
            ?.toInt()
        tombstoneDao.upsert(
            SyncTombstoneEntity(
                id = uuidFactory(),
                recordID = work.id,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = now,
                lastModifiedAt = now,
                sourceURL = work.sourceUrl,
                ao3WorkID = ao3Id,
                deletedOnDeviceID = "",
                deletionReason = deletionReason
            )
        )
    }

    private suspend fun retractWorkTombstone(workId: String) {
        tombstoneDao.deleteByRecord(workId, SyncTombstoneRecordType.SAVED_WORK)
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

    companion object {
        /** Apple `PreservedWorkService.recoveryWindow` — 90 days. */
        val RECOVERY_WINDOW: Duration = Duration.ofDays(90)
    }
}
