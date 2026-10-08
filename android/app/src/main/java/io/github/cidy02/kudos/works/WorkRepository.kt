package io.github.cidy02.kudos.works

import androidx.room.withTransaction
import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.collectionMembershipRecordId
import io.github.cidy02.kudos.core.model.legacyCollectionMembershipRecordId
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.dao.CollectionWorkLink
import io.github.cidy02.kudos.data.local.dao.WorkKeeperName
import io.github.cidy02.kudos.data.local.dao.WorkTagLink
import io.github.cidy02.kudos.data.local.entity.CollectionEntity
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkEntity
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
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
    private val queueDao = database.readingQueueDao()
    private val annotationDao = database.annotationDao()

    internal fun currentInstant(): Instant = clock()

    fun observeSavedWorks(): Flow<List<SavedWork>> {
        return workDao.observeAll().decorated().map { works ->
            works.filter { it.isProtected && !it.isQueueOnlyWork }
        }.distinctUntilChanged()
    }

    /**
     * All active library works (excludes soft-deleted). Used by Browse category
     * enrichment for saved counts and recently-read chips — not only `isSaved`.
     */
    fun observeLibraryWorks(): Flow<List<SavedWork>> = workDao.observeAll().decorated()

    /** One-shot list of active saved library works (excludes soft-deleted). */
    suspend fun listSavedWorks(): List<SavedWork> {
        return decorate(workDao.getAll().map { it.toDomain() })
            .filter { it.isProtected && !it.isQueueOnlyWork }
    }

    /** Active work IDs in the system Saved for Later queue. */
    suspend fun savedForLaterWorkIds(): Set<String> {
        val queue = queueDao.getActiveQueueByKind(ReadingQueueKind.SAVED_FOR_LATER) ?: return emptySet()
        return queueDao.getMembershipsForQueue(queue.id).mapTo(mutableSetOf()) { it.workID }
    }

    /** Re-emits when the Saved for Later queue or its memberships change. */
    fun observeSavedForLaterWorkIds(): Flow<Set<String>> {
        return combine(
            queueDao.observeActiveQueues().conflate(),
            queueDao.observeAllMemberships().conflate()
        ) { queues, memberships ->
            val queue = queues.firstOrNull { it.kindRaw == ReadingQueueKind.SAVED_FOR_LATER }
            if (queue == null) {
                emptySet()
            } else {
                memberships.mapNotNullTo(mutableSetOf()) { row ->
                    row.workID.takeIf { row.queueID == queue.id }
                }
            }
        }.distinctUntilChanged()
    }

    /**
     * Tags, collection membership, and Saved for Later for the whole library,
     * loaded with one query each instead of one query per work.
     */
    fun observeLibraryIndex(): Flow<WorkLibraryIndex> {
        return combine(
            tagDao.observeAllWorkTagLinks().conflate(),
            collectionDao.observeAllActive().conflate(),
            collectionDao.observeActiveMembershipLinks().conflate(),
            tagDao.observeAll().conflate(),
            observeSavedForLaterWorkIds()
        ) { links, collections, memberships, tags, savedForLaterIds ->
            val grouped = groupCollections(collections, memberships)
            WorkLibraryIndex(
                tagsByWork = groupTags(links),
                collectionsByWork = grouped.byWork,
                userTags = tags.map { it.toDomain() },
                collections = grouped.all,
                savedForLaterIds = savedForLaterIds
            )
        }.distinctUntilChanged().flowOn(Dispatchers.Default)
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
     * iOS `PrivacyDataView.freedHistory`: works that only remain in the reading history. No
     * copy on this device and nothing the reader chose to keep (`isProtected`: saved,
     * favourited, kept offline, imported, or gone from AO3). Also not in a queue, which iOS
     * does not ask: a queued work is not "only in the history", and the confirmation
     * promises to take nothing else.
     *
     * Settings › Clear reading history used to take every finished work, saved and downloaded
     * ones included, under a message saying they were not affected (audit A14).
     */
    private fun isHistoryOnly(work: SavedWork): Boolean =
        !work.hasEpub && !work.isProtected && !work.isQueuedForLater && !work.isDeleted

    fun observeHistoryOnlyWorks(): Flow<List<SavedWork>> =
        observeLibraryWorks().map { works -> works.filter(::isHistoryOnly) }

    /** Moves those works to Recently Deleted for [RECOVERY_WINDOW]. Returns how many. */
    suspend fun softDeleteHistoryOnly(): Int {
        val history = decorate(workDao.getAll().map { it.toDomain() }).filter(::isHistoryOnly)
        for (work in history) softDelete(work.id)
        return history.size
    }

    /** iOS `LocalDataClearing.hasReadingPosition`: either reader's resume point, or the Mac's percent. */
    private fun hasReadingPosition(work: SavedWork): Boolean =
        !work.readiumLocator.isNullOrEmpty() || work.lastSpineIndex > 0 || work.lastScrollFraction > 0.0 ||
            work.legacyReaderProgress != null

    fun observePositionedWorks(): Flow<List<SavedWork>> =
        observeLibraryWorks().map { works -> works.filter { hasReadingPosition(it) && !it.isDeleted } }

    /**
     * iOS `LocalDataClearing.clearReadingPositions`: forgets the place in every work and keeps
     * the works. `lastReadDate` stays: it is Continue Reading's order, a fact about the shelf.
     */
    suspend fun clearReadingPositions(): Int {
        val positioned = workDao.getAll().map { it.toDomain() }.filter { hasReadingPosition(it) && !it.isDeleted }
        val now = clock()
        for (work in positioned) {
            upsert(work.copy(readiumLocator = "", lastSpineIndex = 0, lastScrollFraction = 0.0,
                legacyReaderProgress = null, progressModifiedAt = now, lastModifiedAt = now))
        }
        return positioned.size
    }


    /** Soft-deleted works in Recently Deleted (newest first). */
    fun observeRecentlyDeleted(): Flow<List<SavedWork>> = workDao.observeDeleted().decorated()

    suspend fun listRecentlyDeleted(): List<SavedWork> {
        return decorate(workDao.getDeleted().map { it.toDomain() })
    }

    fun observeHeldCopies(): Flow<List<SavedWork>> = workDao.observeHeldCopies().decorated()
        .map { works -> works.filter(::qualifiesForHold) }
        .distinctUntilChanged()

    /** Settings' iOS `LocalDataClearing.selectFreeableDownloads` rule. */
    fun observeFreeableCopies(): Flow<List<SavedWork>> = observeLibraryWorks()
        .map { works -> works.filter(::qualifiesForHold) }

    suspend fun getWork(id: String): SavedWork? = workDao.getById(id)?.toDomain()?.let { decorate(it) }

    suspend fun updateDownloadedAt(workId: String, downloadedAt: Instant): SavedWork? {
        val work = getWork(workId) ?: return null
        return upsert(work.copy(downloadedAt = downloadedAt, lastModifiedAt = clock()))
    }

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
        return workDao.getBySourceUrl(sourceUrl)?.toDomain()?.let { decorate(it) }
    }

    suspend fun upsert(work: SavedWork): SavedWork {
        // Keep searchText derived and current without bumping lastModifiedAt.
        val userTags = runCatching { userTagsForWork(work.id).map { it.name } }.getOrDefault(emptyList())
        val indexed = WorkSearchIndex.reindex(work, userTags)
        workDao.upsert(indexed.toEntity())
        return decorate(indexed)
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
        return upsert(
            work.copy(
                hasEpub = hasEpub,
                remoteEpubPending = false,
                freedAt = if (hasEpub) work.freedAt else null,
                lastModifiedAt = clock()
            )
        )
    }

    suspend fun toggleFavorite(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        return setFavorite(workId, !work.isFavorite)
    }

    /** Sets favorite flag without toggling (Library bulk favorite / unfavorite). */
    suspend fun setFavorite(workId: String, favorite: Boolean): SavedWork? {
        val work = getWork(workId) ?: return null
        if (work.isFavorite == favorite && (!favorite || work.freedAt == null)) return work
        return upsert(
            work.copy(
                isFavorite = favorite,
                freedAt = if (favorite) null else work.freedAt,
                lastModifiedAt = clock()
            )
        )
    }

    /**
     * Apple `WorkLifecycle.setSaved` — keep (protect EPUB) or un-save a work.
     * Library observe path only surfaces [SavedWork.isSaved] works.
     */
    suspend fun setSaved(workId: String, saved: Boolean): SavedWork? {
        val work = getWork(workId) ?: return null
        if (work.isSaved == saved && (!saved || work.freedAt == null)) return work
        return upsert(
            work.copy(
                isSaved = saved,
                freedAt = if (saved) null else work.freedAt,
                lastModifiedAt = clock()
            )
        )
    }

    suspend fun toggleFinished(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        return setFinished(workId, !work.isFinished)
    }

    /**
     * Apple `WorkLifecycle.markFinished` / `markStillReading` parity:
     * - Mark finished: set flag; if the work is un-kept, hold its EPUB for 60 days.
     * - Mark unfinished: clear the hold; never auto-restore an already-freed EPUB.
     */
    suspend fun setFinished(workId: String, finished: Boolean): SavedWork? {
        val work = getWork(workId) ?: return null
        if (work.isFinished == finished) return work
        val now = clock()
        return if (finished) {
            upsert(
                work.copy(
                    isFinished = true,
                    freedAt = if (!work.isProtected && work.hasEpub) work.freedAt ?: now else null,
                    lastModifiedAt = now
                )
            )
        } else {
            upsert(work.copy(isFinished = false, freedAt = null, lastModifiedAt = now))
        }
    }

    /** History's local undo: stored override and the flag/metadata merge clock together. */
    suspend fun keepInProgress(workId: String): SavedWork? = database.withTransaction {
        val work = getWork(workId) ?: return@withTransaction null
        upsert(work.copy(keepInProgressOverride = true, lastModifiedAt = clock()))
    }

    /** Recently Deleted's Restore for a held copy: keep it as a Download. */
    suspend fun restoreHeldCopy(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        return upsert(work.copy(isSaved = true, freedAt = null, lastModifiedAt = clock()))
    }

    /** Reader-close parity with iOS `freeEPUBIfFinished`; safe to call repeatedly. */
    suspend fun holdFinishedCopy(workId: String, now: Instant = clock()): SavedWork? {
        val work = getWork(workId) ?: return null
        if (!qualifiesForHold(work) || work.freedAt != null) return work
        return upsert(work.copy(freedAt = now, lastModifiedAt = now))
    }

    /** Recently Deleted's Remove Copy: free the file now, retain reading history. */
    suspend fun freeHeldCopy(workId: String): SavedWork? = deleteLocalEpub(workId)

    /** Reading a held work again removes it from Recently Deleted. */
    suspend fun releaseHeldCopy(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        if (work.freedAt == null) return work
        return upsert(work.copy(freedAt = null, lastModifiedAt = clock()))
    }

    /** Frees expired held copies and clears stale holds. Runs beside the 90-day sweep. */
    suspend fun sweepHeldCopies(everything: Boolean = false): Int {
        val now = clock()
        var freed = 0
        for (entity in workDao.getHeldCopies()) {
            val work = decorate(entity.toDomain())
            if (!qualifiesForHold(work)) {
                upsert(work.copy(freedAt = null, lastModifiedAt = now))
            } else if (everything || !now.isBefore(work.freedAt!!.plus(FREED_COPY_WINDOW))) {
                deleteLocalEpub(work.id)
                freed += 1
            }
        }
        return freed
    }

    /** Settings › Free up space also catches pre-port finished copies without a hold stamp. */
    suspend fun freeFinishedCopies(): Int {
        val freeable = decorate(workDao.getAll().map { it.toDomain() }).filter(::qualifiesForHold)
        freeable.forEach { deleteLocalEpub(it.id) }
        return freeable.size
    }

    suspend fun deleteLocalEpub(workId: String): SavedWork? {
        val work = getWork(workId) ?: return null
        fileStore.deleteWorkEpub(workId)
        return upsert(work.copy(hasEpub = false, remoteEpubPending = false, freedAt = null, lastModifiedAt = clock()))
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
        retractWorkTombstone(work)
        return restored
    }

    /**
     * Permanently removes the work row and local EPUB, and records a sync
     * tombstone so a later backup import does not resurrect it by UUID.
     * Used by "Delete forever" and [sweepExpiredSoftDeletes].
     */
    suspend fun hardDelete(workId: String) {
        database.withTransaction {
            val work = getWork(workId)
            if (work != null) recordWorkTombstone(work, clock(), deletionReason = "workDeleted")
            deleteDependents(workId)
            workDao.deleteById(workId)
        }
        // Files cannot roll back with Room. Remove only after the rows and every
        // deletion marker commit; a failed DAO write must leave the reader's EPUB.
        fileStore.deleteWorkEpub(workId)
    }

    /**
     * Queue memberships and annotations have no foreign key to `works`, so they
     * would outlive the work: orphaned, and resurrectable by an older backup.
     * Tombstone each and delete it, as iOS `WorkLifecycle.hardDelete` does, in
     * the same shapes `ReadingQueueRepository.removeWork` and
     * `AnnotationRepository.deleteAnnotation` write.
     */
    private suspend fun deleteDependents(workId: String) {
        val now = clock()
        for (membership in queueDao.getMembershipsForWork(workId)) {
            upsertSignedTombstone(
                SyncTombstone(
                    id = uuidFactory(),
                    recordID = membership.id,
                    recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP,
                    createdAt = now,
                    lastModifiedAt = now,
                    deletedOnDeviceID = "",
                    deletionReason = "queueMembershipRemoved"
                )
            )
            queueDao.deleteMembershipById(membership.id)
        }
        for (annotation in annotationDao.getAllForWork(workId)) {
            upsertSignedTombstone(
                SyncTombstone(
                    id = uuidFactory(),
                    recordID = annotation.id.lowercase(),
                    recordTypeRaw = SyncTombstoneRecordType.READING_ANNOTATION,
                    createdAt = now,
                    lastModifiedAt = now,
                    deletionReason = "annotationDeleted"
                )
            )
            annotationDao.deleteById(annotation.id)
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

    /**
     * Hard-deletes all pending deleted works and collections, matching iOS
     * `PreservedWorkService.hardDeleteAllPending`.
     */
    suspend fun hardDeleteAllPending(): Int {
        val deletedWorks = workDao.getDeleted()
        for (entity in deletedWorks) {
            hardDelete(entity.id)
        }
        val deletedCollections = collectionDao.getDeleted()
        for (entity in deletedCollections) {
            hardDeleteCollection(entity.id)
        }
        return deletedWorks.size + deletedCollections.size
    }

    /**
     * Returns the count of active (non-pending-deletion) highlights and bookmarks for [workId].
     */
    suspend fun getAnnotationCounts(workId: String): Pair<Int, Int> {
        val annotations = annotationDao.getAllForWork(workId).filter { !it.isPendingDeletion }
        val highlights = annotations.count { it.kindRaw.equals("highlight", ignoreCase = true) }
        val bookmarks = annotations.count { it.kindRaw.equals("bookmark", ignoreCase = true) }
        return highlights to bookmarks
    }

    private suspend fun recordWorkTombstone(
        work: SavedWork,
        now: Instant,
        deletionReason: String
    ) {
        val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
            ?.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }
            ?.toInt()
        val canonical = WorkTags.canonicalAO3WorkURL(work.sourceUrl).orEmpty()
        upsertSignedTombstone(
            SyncTombstone(
                id = uuidFactory(),
                recordID = work.id.lowercase(),
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = now,
                lastModifiedAt = now,
                sourceURL = canonical,
                ao3WorkID = ao3Id,
                deletedOnDeviceID = "",
                deletionReason = deletionReason
            )
        )
    }

    /**
     * Delete local savedWork tombstones matching record UUID, ao3WorkID, or
     * canonical source URL — not UUID-only.
     */
    suspend fun retractWorkTombstone(
        recordId: String,
        ao3WorkId: Int? = null,
        sourceUrl: String = ""
    ) {
        // Same identity-aware retraction as a snapshot File Merge. Canonicalize
        // both addresses, as iOS does, including old tombstones with chapter URLs.
        val held = tombstoneDao.getAll().map { it.toDomain() }
        val retainedIds = retractWorkTombstone(held, recordId, ao3WorkId, sourceUrl).mapTo(mutableSetOf()) { it.id }
        for (tombstone in held) {
            if (tombstone.id !in retainedIds) tombstoneDao.deleteById(tombstone.id)
        }
    }

    private suspend fun retractWorkTombstone(work: SavedWork) {
        val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
            ?.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }
            ?.toInt()
        retractWorkTombstone(
            recordId = work.id,
            ao3WorkId = ao3Id,
            sourceUrl = work.sourceUrl
        )
    }

    private suspend fun upsertSignedTombstone(tombstone: SyncTombstone) {
        tombstoneDao.upsert(TombstoneSigning.sign(tombstone).toEntity())
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
        val entities = collectionDao.getCollectionsForWork(workId)
        if (entities.isEmpty()) return emptyList()
        val workIds = activeWorkIdsByCollection()
        return entities.map { it.toDomain(workIds[it.id].orEmpty()) }
    }

    suspend fun allCollections(): List<WorkCollection> {
        return groupCollections(collectionDao.getAll(), collectionDao.getActiveMembershipLinks()).all
    }

    suspend fun getCollection(collectionId: String): WorkCollection? {
        val entity = collectionDao.getById(collectionId) ?: return null
        return entity.toDomain(collectionDao.getActiveWorkIdsForCollection(entity.id))
    }

    /** Soft-deleted collections in Recently Deleted (newest deletion first). */
    suspend fun listRecentlyDeletedCollections(): List<WorkCollection> {
        val workIds = activeWorkIdsByCollection()
        return collectionDao.getDeleted().map { entity ->
            entity.toDomain(workIds[entity.id].orEmpty())
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
                    hasGivenKudos = work.hasGivenKudos || meta.kudosGivenByCurrentUser,
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
    suspend fun createCollection(
        name: String,
        hue: Double? = null,
        colorHex: String? = null,
        description: String? = null,
        keepsWorksOffline: Boolean? = false,
        showsOnHome: Boolean = false
    ): WorkCollection {
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
            description = description?.trim()?.ifBlank { null },
            sortOrder = null,
            lastModifiedAt = now,
            hue = hue,
            colorHex = colorHex,
            keepsWorksOffline = keepsWorksOffline,
            showsOnHome = showsOnHome
        )
        collectionDao.upsert(entity)
        return entity.toDomain(emptyList())
    }

    /**
     * Updates an existing collection's properties, stamping [lastModifiedAt].
     * If [clearColor] is true, resets both [hue] and [colorHex] to null.
     */
    suspend fun updateCollection(
        collectionId: String,
        name: String? = null,
        description: String? = null,
        hue: Double? = null,
        colorHex: String? = null,
        clearColor: Boolean = false,
        keepsWorksOffline: Boolean? = null,
        showsOnHome: Boolean? = null,
        workOrderRaw: String? = null
    ): WorkCollection? {
        val entity = collectionDao.getById(collectionId) ?: return null
        if (entity.isDeleted) return null
        val now = clock()
        val nextName = name?.trim()?.takeIf { it.isNotEmpty() } ?: entity.name
        val nextDesc = if (description != null) description.trim().ifBlank { null } else entity.description
        val nextHue = if (clearColor) null else (hue ?: entity.hue)
        val nextColorHex = if (clearColor) null else (colorHex ?: entity.colorHex)
        val nextKeeps = keepsWorksOffline ?: entity.keepsWorksOffline
        val nextHome = showsOnHome ?: entity.showsOnHome
        val nextOrder = workOrderRaw ?: entity.workOrderRaw
        val updated = entity.copy(
            name = nextName,
            description = nextDesc,
            hue = nextHue,
            colorHex = nextColorHex,
            keepsWorksOffline = nextKeeps,
            showsOnHome = nextHome,
            workOrderRaw = nextOrder,
            lastModifiedAt = now
        )
        collectionDao.upsert(updated)
        return updated.toDomain(collectionDao.getActiveWorkIdsForCollection(updated.id))
    }

    /**
     * Updates a collection's reading order from an ordered list of work IDs,
     * stamping [lastModifiedAt].
     */
    suspend fun setCollectionReadingOrder(collectionId: String, orderedWorkIds: List<String>): WorkCollection? {
        val entity = collectionDao.getById(collectionId) ?: return null
        if (entity.isDeleted) return null
        val now = clock()
        val raw = orderedWorkIds.joinToString(",")
        val updated = entity.copy(
            workOrderRaw = raw,
            lastModifiedAt = now
        )
        collectionDao.upsert(updated)
        return updated.toDomain(collectionDao.getActiveWorkIdsForCollection(updated.id))
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
        if (entity.keepsWorksOffline == true) releaseHeldCopy(workId)
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
        database.withTransaction {
            val now = clock()
            // Without a tombstone, restoring a backup that still lists this membership
            // silently resurrects it — same reasoning as reading-queue removeWork.
            upsertSignedTombstone(
                SyncTombstone(
                    id = uuidFactory(),
                    recordID = membershipRecordId(collectionId, workId),
                    recordTypeRaw = SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP,
                    createdAt = now,
                    lastModifiedAt = now,
                    deletedOnDeviceID = "",
                    deletionReason = "collectionMembershipRemoved"
                )
            )
            collectionDao.removeWork(collectionId, workId)
            touchCollection(collectionId)
        }
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
        upsertSignedTombstone(
            SyncTombstone(
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
        /** PreservedWorkService.retractTombstone, shared by live restore and backup snapshots. */
        fun retractWorkTombstone(
            tombstones: List<SyncTombstone>,
            recordId: String,
            ao3WorkId: Int? = null,
            sourceUrl: String = ""
        ): List<SyncTombstone> {
            val canonical = WorkTags.canonicalAO3WorkURL(sourceUrl)
            return tombstones.filterNot { tombstone ->
                tombstone.recordTypeRaw == SyncTombstoneRecordType.SAVED_WORK && (
                    tombstone.recordID.equals(recordId, ignoreCase = true) ||
                        (ao3WorkId != null && tombstone.ao3WorkID == ao3WorkId) ||
                        (canonical != null && WorkTags.canonicalAO3WorkURL(tombstone.sourceURL) == canonical)
                    )
            }
        }

        /** Apple `PreservedWorkService.recoveryWindow` — 90 days. */
        val RECOVERY_WINDOW: Duration = Duration.ofDays(90)
        /** Apple `WorkLifecycle.freedCopyWindow` — 60 days. */
        val FREED_COPY_WINDOW: Duration = Duration.ofDays(60)
    }

    private fun Flow<List<WorkEntity>>.decorated(): Flow<List<SavedWork>> {
        return conflate()
            .map { entities -> decorate(entities.map { it.toDomain() }) }
            .distinctUntilChanged()
            .flowOn(Dispatchers.IO)
    }

    private suspend fun decorate(works: List<SavedWork>): List<SavedWork> {
        if (works.isEmpty()) return emptyList()
        val keptIds = workDao.getKeptOfflineWorkIds().toSet()
        val queueKeepers = firstKeeperNames(queueDao.getActiveKeepingQueueNames())
        val collectionKeepers = firstKeeperNames(collectionDao.getActiveKeepingCollectionNames())
        return works.map { work ->
            val kept = work.id in keptIds
            work.copy(
                isKeptOffline = kept,
                keptOfflineBy = if (kept) queueKeepers[work.id] ?: collectionKeepers[work.id] else null,
                hasAo3WorkId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) != null
            )
        }
    }

    private suspend fun decorate(work: SavedWork): SavedWork {
        val kept = workDao.isKeptOffline(work.id)
        val keeper = if (kept) {
            queueDao.getActiveKeepingQueueName(work.id)
                ?: collectionDao.getActiveKeepingCollectionName(work.id)
        } else {
            null
        }
        return work.copy(
            isKeptOffline = kept,
            keptOfflineBy = keeper,
            hasAo3WorkId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) != null
        )
    }

    private suspend fun activeWorkIdsByCollection(): Map<String, List<String>> {
        return workIdsByCollection(collectionDao.getActiveMembershipLinks())
    }

    private fun groupTags(links: List<WorkTagLink>): Map<String, List<Tag>> {
        val grouped = LinkedHashMap<String, MutableList<Tag>>()
        for (link in links) {
            grouped.getOrPut(link.workId) { mutableListOf() }.add(
                Tag(id = link.id, name = link.name, dateCreated = link.dateCreated)
            )
        }
        return grouped.mapValues { it.value.toList() }
    }

    private fun groupCollections(
        entities: List<CollectionEntity>,
        memberships: List<CollectionWorkLink>
    ): GroupedCollections {
        val workIds = workIdsByCollection(memberships)
        val all = entities.map { it.toDomain(workIds[it.id].orEmpty()) }
        val byWork = LinkedHashMap<String, MutableList<WorkCollection>>()
        for (collection in all) {
            for (workId in collection.workIds) {
                byWork.getOrPut(workId) { mutableListOf() }.add(collection)
            }
        }
        return GroupedCollections(
            all = all,
            byWork = byWork.mapValues { it.value.toList() }
        )
    }

    private fun workIdsByCollection(links: List<CollectionWorkLink>): Map<String, List<String>> {
        val grouped = LinkedHashMap<String, MutableList<String>>()
        for (link in links) {
            grouped.getOrPut(link.collectionId) { mutableListOf() }.add(link.workId)
        }
        return grouped.mapValues { it.value.toList() }
    }

    /** First row per work wins. Callers pass rows in the same order as the per-work LIMIT 1 query. */
    private fun firstKeeperNames(rows: List<WorkKeeperName>): Map<String, String> {
        val names = LinkedHashMap<String, String>(rows.size)
        for (row in rows) {
            if (row.workId !in names) names[row.workId] = row.name
        }
        return names
    }

    private fun qualifiesForHold(work: SavedWork): Boolean =
        work.isFinished && !work.isProtected && !work.isDeleted && work.hasEpub
}

/** Batched library relations used to build a [io.github.cidy02.kudos.library.LibrarySnapshot]. */
data class WorkLibraryIndex(
    val tagsByWork: Map<String, List<Tag>> = emptyMap(),
    val collectionsByWork: Map<String, List<WorkCollection>> = emptyMap(),
    val userTags: List<Tag> = emptyList(),
    val collections: List<WorkCollection> = emptyList(),
    val savedForLaterIds: Set<String> = emptySet()
)

private data class GroupedCollections(
    val all: List<WorkCollection>,
    val byWork: Map<String, List<WorkCollection>>
)
