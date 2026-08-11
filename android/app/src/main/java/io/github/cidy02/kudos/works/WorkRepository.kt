package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.collectionMembershipRecordId
import io.github.cidy02.kudos.core.model.legacyCollectionMembershipRecordId
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
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository
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
    private val tagsRepository: WorkTagsRepository? = null,
    private val clock: () -> Instant = { Instant.now() },
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() }
) {
    private val workDao = database.workDao()
    private val tagDao = database.tagDao()
    private val collectionDao = database.collectionDao()
    private val tombstoneDao = database.syncTombstoneDao()

    fun observeSavedWorks(): Flow<List<SavedWork>> {
        return workDao.observeAll()
            .map { works -> works.map { it.toDomain() }.filter { it.isProtected && !it.isQueueOnlyWork } }
    }

    /**
     * All active library works (excludes soft-deleted). Used by Browse category
     * enrichment for saved counts and recently-read chips — not only `isSaved`.
     */
    fun observeLibraryWorks(): Flow<List<SavedWork>> {
        return workDao.observeAll().map { works -> works.map { it.toDomain() } }
    }

    /** One-shot list of active saved library works (excludes soft-deleted). */
    suspend fun listSavedWorks(): List<SavedWork> {
        return workDao.getAll().map { it.toDomain() }.filter { it.isProtected && !it.isQueueOnlyWork }
    }

    /** Active finished works in local reading history (excludes soft-deleted). */
    fun observeFinishedWorks(): Flow<List<SavedWork>> {
        return observeLibraryWorks().map { works -> works.filter { it.isFinished } }
    }

    /** One-shot list of active finished works in local reading history (excludes soft-deleted). */
    suspend fun listFinishedWorks(): List<SavedWork> {
        return workDao.getAll().map { it.toDomain() }.filter { it.isFinished }
    }

    /**
     * Soft-deletes all active finished works into Recently Deleted for [RECOVERY_WINDOW] (90 days).
     * Mirrors Apple `PrivacyDataView` clear reading history intent. Returns the count of works cleared.
     */
    suspend fun softDeleteAllFinished(): Int {
        val finished = listFinishedWorks()
        for (work in finished) {
            softDelete(work.id)
        }
        return finished.size
    }


    /** Soft-deleted works in Recently Deleted (newest first). */
    fun observeRecentlyDeleted(): Flow<List<SavedWork>> {
        return workDao.observeDeleted().map { works -> works.map { it.toDomain() } }
    }

    suspend fun listRecentlyDeleted(): List<SavedWork> {
        return workDao.getDeleted().map { it.toDomain() }
    }

    suspend fun getWork(id: String): SavedWork? = workDao.getById(id)?.toDomain()

    /**
     * Marks current posted chapter count as seen, clearing Home → Recently Updated.
     * Apple `HomeWorkDestination` parity.
     */
    suspend fun markUpdateSeen(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        if (!work.hasUpdate) return work
        return upsert(
            work.copy(
                knownChapterCount = work.postedChapterCount,
                lastModifiedAt = clock()
            )
        )
    }

    suspend fun findBySourceUrl(sourceUrl: String): SavedWork? {
        if (sourceUrl.isBlank()) return null
        return workDao.getBySourceUrl(sourceUrl)?.toDomain()
    }

    suspend fun upsert(work: SavedWork): SavedWork {
        // Keep searchText derived and current without bumping lastModifiedAt.
        val userTags = runCatching { userTagsForWork(work.id).map { it.name } }.getOrDefault(emptyList())
        val indexed = WorkSearchIndex.reindex(work, userTags)
        workDao.upsert(indexed.toEntity())
        return indexed
    }

    /**
     * Launch-time paced rebuild of stale [SavedWork.searchText] rows
     * (schema bump, pre-index libraries, backup restores). Cheap no-op when current.
     */
    suspend fun rebuildSearchIndexIfNeeded(): Int {
        return WorkSearchIndex.rebuildIfNeeded(
            loadStale = { version ->
                workDao.getWithStaleSearchIndex(version).map { it.toDomain() }
            },
            userTagsFor = { workId ->
                userTagsForWork(workId).map { it.name }
            },
            save = { batch ->
                workDao.upsertAll(batch.map { it.toEntity() })
            }
        )
    }

    suspend fun setHasEpub(workId: String, hasEpub: Boolean): SavedWork? {
        val work = getWork(workId) ?: return null
        return upsert(work.copy(hasEpub = hasEpub, lastModifiedAt = clock()))
    }

    suspend fun toggleFavorite(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        return upsert(work.copy(isFavorite = !work.isFavorite, lastModifiedAt = clock()))
    }

    /** Sets favorite flag without toggling (Library bulk favorite / unfavorite). */
    suspend fun setFavorite(workId: String, favorite: Boolean): SavedWork? {
        val work = getWork(workId) ?: return null
        if (work.isFavorite == favorite) return work
        return upsert(work.copy(isFavorite = favorite, lastModifiedAt = clock()))
    }

    /**
     * Apple `WorkLifecycle.setSaved` — keep (protect EPUB) or un-save a work.
     * Library observe path only surfaces [SavedWork.isSaved] works.
     */
    suspend fun setSaved(workId: String, saved: Boolean): SavedWork? {
        val work = getWork(workId) ?: return null
        if (work.isSaved == saved) return work
        return upsert(work.copy(isSaved = saved, lastModifiedAt = clock()))
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
     * Permanently deletes soft-deleted works whose
     * `permanentDeletionScheduledAt` has elapsed (`<=` now). Invoked once on
     * app start from [io.github.cidy02.kudos.KudosApplication] (Apple
     * `PreservedWorkService` launch sweep). Returns how many works were removed.
     */
    suspend fun sweepExpiredSoftDeletes(): Int {
        val now = clock()
        val expired = workDao.getExpiredSoftDeletes(now)
        for (entity in expired) {
            hardDelete(entity.id)
        }
        return expired.size
    }

    /** Alias for [sweepExpiredSoftDeletes] — same 90-day permanent purge. */
    suspend fun purgeExpiredSoftDeletes(): Int = sweepExpiredSoftDeletes()

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
        reindexSearchForWork(workId)
        return userTagsForWork(workId)
    }

    suspend fun removeUserTag(workId: String, tagId: String): List<Tag> {
        tagDao.removeFromWork(workId, tagId)
        reindexSearchForWork(workId)
        return userTagsForWork(workId)
    }

    private suspend fun reindexSearchForWork(workId: String) {
        val work = getWork(workId) ?: return
        val tags = userTagsForWork(workId).map { it.name }
        workDao.upsert(WorkSearchIndex.reindex(work, tags).toEntity())
    }

    suspend fun collectionsForWork(workId: String): List<WorkCollection> {
        return collectionDao.getCollectionsForWork(workId).map { entity ->
            entity.toDomain(collectionDao.getActiveWorkIdsForCollection(entity.id))
        }
    }

    suspend fun allCollections(): List<WorkCollection> {
        return collectionDao.getAll().map { entity ->
            entity.toDomain(collectionDao.getActiveWorkIdsForCollection(entity.id))
        }
    }

    suspend fun getCollection(collectionId: String): WorkCollection? {
        val entity = collectionDao.getById(collectionId) ?: return null
        return entity.toDomain(collectionDao.getActiveWorkIdsForCollection(entity.id))
    }

    /** Soft-deleted collections in Recently Deleted (newest deletion first). */
    suspend fun listRecentlyDeletedCollections(): List<WorkCollection> {
        return collectionDao.getDeleted().map { entity ->
            entity.toDomain(collectionDao.getActiveWorkIdsForCollection(entity.id))
        }
    }

    /**
     * Re-fetches metadata for one work to detect AO3 deletion (404) or tag updates.
     * Port of iOS `WorkTagsService.refreshTags`.
     */
    suspend fun refreshMetadata(workId: String): AO3Result<Unit> {
        val repo = tagsRepository ?: return AO3Result.Failure(AO3Error.Validation("No tags repository."))
        val work = getWork(workId) ?: return AO3Result.Failure(AO3Error.NotFound)
        val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: return AO3Result.Failure(AO3Error.BadRequest)
        
        return when (val result = repo.refreshTags(ao3Id)) {
            is AO3Result.Failure -> {
                if (result.error == AO3Error.NotFound) {
                    // Work is gone from AO3 (404). Stamp lastUpdateCheck so we don't
                    // immediately retry, but keep the record (Kudos preserves works).
                    upsert(work.copy(lastUpdateCheck = clock()))
                    AO3Result.Success(Unit)
                } else result
            }
            is AO3Result.Success -> {
                val meta = result.value
                val updated = work.copy(
                    rating = if (meta.rating.isNotBlank()) meta.rating else work.rating,
                    workWarnings = if (meta.warnings.isNotEmpty()) meta.warnings else work.workWarnings,
                    workCategories = if (meta.categories.isNotEmpty()) meta.categories else work.workCategories,
                    workFandoms = if (meta.fandoms.isNotEmpty()) meta.fandoms else work.workFandoms,
                    workRelationships = if (meta.relationships.isNotEmpty()) meta.relationships else work.workRelationships,
                    workCharacters = if (meta.characters.isNotEmpty()) meta.characters else work.workCharacters,
                    workFreeforms = if (meta.freeforms.isNotEmpty()) meta.freeforms else work.workFreeforms,
                    lastUpdateCheck = clock()
                )
                upsert(updated)
                AO3Result.Success(Unit)
            }
        }
    }

    /**
     * Soft-deleted collections for Recently Deleted UI. Membership is loaded as a
     * flat id list without the [collectionDao] work-count join — Recently Deleted
     * only needs the collection's name/expiry, not its active work count.
     */
    fun observeRecentlyDeletedCollections(): Flow<List<WorkCollection>> {
        return collectionDao.observeDeleted().map { entities ->
            entities.map { it.toDomain() }
        }
    }

    /** Saved works currently in [collectionId], newest library-add first. */
    suspend fun worksForCollection(collectionId: String): List<SavedWork> {
        return collectionDao.getWorksForCollection(collectionId).map { it.toDomain() }
    }

    /**
     * Creates an empty named shelf, or returns the existing case-insensitive match.
     * Does not attach a work — use [addToCollection] / [addWorkToCollection] for membership.
     */
    suspend fun createCollection(name: String): WorkCollection {
        val trimmed = name.trim()
        require(trimmed.isNotEmpty()) { "Collection name must not be blank." }
        val existing = collectionDao.getAll().firstOrNull {
            it.name.equals(trimmed, ignoreCase = true)
        }
        if (existing != null) {
            return existing.toDomain(collectionDao.getActiveWorkIdsForCollection(existing.id))
        }
        val now = clock()
        val entity = CollectionEntity(
            id = uuidFactory(),
            name = trimmed,
            dateAdded = now,
            description = null,
            sortOrder = null,
            lastModifiedAt = now
        )
        collectionDao.upsert(entity)
        return entity.toDomain(emptyList())
    }

    /**
     * Renames an existing collection in place (same id / membership / metadata).
     * Does **not** delete+recreate — that would drop work memberships and history.
     * Soft-deleted collections cannot be renamed here; restore first.
     * Returns null if the id is missing or soft-deleted.
     */
    suspend fun renameCollection(collectionId: String, newName: String): WorkCollection? {
        val trimmed = newName.trim()
        require(trimmed.isNotEmpty()) { "Collection name must not be blank." }
        val entity = collectionDao.getById(collectionId) ?: return null
        if (entity.isDeleted) return null
        if (entity.name == trimmed) {
            return entity.toDomain(collectionDao.getActiveWorkIdsForCollection(entity.id))
        }
        val updated = entity.copy(name = trimmed, lastModifiedAt = clock())
        // @Upsert is an in-place UPDATE — memberships stay on the same row id.
        collectionDao.upsert(updated)
        return updated.toDomain(collectionDao.getActiveWorkIdsForCollection(updated.id))
    }

    suspend fun addToCollection(workId: String, name: String): List<WorkCollection> {
        val collection = createCollection(name)
        return addWorkToCollection(workId, collection.id)
    }

    /**
     * Adds [workId] to an existing collection by id (checklist membership toggle).
     * No-ops if the collection is missing or soft-deleted.
     */
    suspend fun addWorkToCollection(workId: String, collectionId: String): List<WorkCollection> {
        val entity = collectionDao.getById(collectionId) ?: return collectionsForWork(workId)
        if (entity.isDeleted) return collectionsForWork(workId)
        collectionDao.addWork(CollectionWorkCrossRef(collectionId, workId))
        touchCollection(collectionId)
        // Retract any tombstone from a prior removal of this same pairing — a
        // stale one here would make a later backup restore silently drop this
        // work back out of the collection despite the user just re-adding it.
        val xorId = membershipRecordId(collectionId, workId)
        tombstoneDao.deleteByRecord(
            xorId,
            SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP
        )
        // android-v0.2.1-alpha wrote colon-form rows; retract those too so a
        // re-add is not suppressed by a legacy tombstone that only the dual-form
        // merge path would still honor.
        tombstoneDao.deleteByRecord(
            legacyCollectionMembershipRecordId(collectionId, workId),
            SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP
        )
        return collectionsForWork(workId)
    }

    suspend fun removeFromCollection(workId: String, collectionId: String): List<WorkCollection> {
        collectionDao.removeWork(collectionId, workId)
        touchCollection(collectionId)
        val now = clock()
        // Without a tombstone, restoring a backup that still lists this membership
        // silently resurrects it — same reasoning as reading-queue removeWork.
        tombstoneDao.upsert(
            SyncTombstoneEntity(
                id = uuidFactory(),
                recordID = membershipRecordId(collectionId, workId),
                recordTypeRaw = SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP,
                createdAt = now,
                lastModifiedAt = now,
                deletedOnDeviceID = "",
                deletionReason = "collectionMembershipRemoved"
            )
        )
        return collectionsForWork(workId)
    }

    /**
     * [CollectionWorkCrossRef] has no id of its own (plain composite key), unlike
     * [io.github.cidy02.kudos.library.ReadingQueueMembership] — build a stable
     * tombstone record id from the pairing instead. Must match iOS
     * `collectionMembershipID` (XOR of the two UUIDs' RFC 4122 bytes) so
     * cross-device restores suppress the same membership.
     */
    private fun membershipRecordId(collectionId: String, workId: String): String =
        collectionMembershipRecordId(collectionId, workId)

    private suspend fun touchCollection(collectionId: String) {
        val entity = collectionDao.getById(collectionId) ?: return
        collectionDao.upsert(entity.copy(lastModifiedAt = clock()))
    }

    /**
     * Moves a collection to Recently Deleted for [RECOVERY_WINDOW] (Apple
     * `PreservedWorkService.softDelete(_ collection:)`). The works inside stay in
     * the Library untouched; only the shelf itself is deleted and recoverable.
     */
    suspend fun softDeleteCollection(collectionId: String): WorkCollection? {
        val entity = collectionDao.getById(collectionId) ?: return null
        val now = clock()
        val updated = entity.copy(
            isDeleted = true,
            deletedAt = now,
            permanentDeletionScheduledAt = now.plus(RECOVERY_WINDOW),
            lastModifiedAt = now
        )
        collectionDao.upsert(updated)
        recordCollectionTombstone(updated.id, now, deletionReason = "collectionDeleted")
        return updated.toDomain(collectionDao.getWorkIdsForCollection(collectionId))
    }

    /** Restores a soft-deleted collection and retracts its tombstone. */
    suspend fun restoreCollectionFromRecentlyDeleted(collectionId: String): WorkCollection? {
        val entity = collectionDao.getById(collectionId) ?: return null
        val now = clock()
        val restored = entity.copy(
            isDeleted = false,
            deletedAt = null,
            permanentDeletionScheduledAt = null,
            lastModifiedAt = now
        )
        collectionDao.upsert(restored)
        tombstoneDao.deleteByRecord(collectionId, SyncTombstoneRecordType.WORK_COLLECTION)
        return restored.toDomain(collectionDao.getActiveWorkIdsForCollection(collectionId))
    }

    /**
     * Permanently deletes the collection shelf. Works remain in Library (Apple
     * parity). Cross-ref rows cascade via FK when the collection row is removed.
     */
    suspend fun hardDeleteCollection(collectionId: String) {
        collectionDao.removeAllWorks(collectionId)
        collectionDao.deleteById(collectionId)
        recordCollectionTombstone(collectionId, clock(), deletionReason = "collectionDeleted")
    }

    /** Permanently deletes soft-deleted collections past their recovery window. */
    suspend fun sweepExpiredCollectionSoftDeletes(): Int {
        val now = clock()
        val expired = collectionDao.getExpiredSoftDeletes(now)
        for (entity in expired) {
            hardDeleteCollection(entity.id)
        }
        return expired.size
    }

    private suspend fun recordCollectionTombstone(
        collectionId: String,
        now: Instant,
        deletionReason: String
    ) {
        tombstoneDao.upsert(
            SyncTombstoneEntity(
                id = uuidFactory(),
                recordID = collectionId,
                recordTypeRaw = SyncTombstoneRecordType.WORK_COLLECTION,
                createdAt = now,
                lastModifiedAt = now,
                deletedOnDeviceID = "",
                deletionReason = deletionReason
            )
        )
    }

    companion object {
        /** Apple `PreservedWorkService.recoveryWindow` — 90 days. */
        val RECOVERY_WINDOW: Duration = Duration.ofDays(90)
    }
}
