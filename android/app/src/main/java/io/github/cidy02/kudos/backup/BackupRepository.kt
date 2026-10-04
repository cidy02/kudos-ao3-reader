package io.github.cidy02.kudos.backup

import androidx.room.withTransaction
import io.github.cidy02.kudos.core.model.BackupSettings
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.QueueTagCrossRef
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FileWriteResult
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkIdentityIndex
import io.github.cidy02.kudos.works.WorkRepository
import java.io.IOException
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Captures the local library into a `.kudosbackup` ZIP and restores merge-only
 * from SAF-picked archives. Session/cookie stores are never read or written.
 */
class BackupRepository(
    private val database: KudosDatabase,
    private val workFileStore: WorkFileStore,
    private val fontFileStore: FontFileStore,
    private val settingsRepository: SettingsRepository,
    private val persistenceGate: PersistenceGate,
    private val clock: () -> Instant = { Instant.now() },
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() },
    private val appVersion: String = "0.1.0"
) {
    fun suggestedExportFileName(now: Instant = clock()): String {
        val day = DateTimeFormatter.ofPattern("yyyy-MM-dd")
            .withZone(ZoneOffset.systemDefault())
            .format(now)
        return "Kudos-$day.kudosbackup"
    }

    // Gated so a manual export/import can never race a background folder sync
    // (SyncRepository.runSync -> this) writing the same local state.
    suspend fun exportV2ZipBytes(): ByteArray = persistenceGate.withLock {
        withContext(Dispatchers.IO) {
            val snapshot = captureLibrarySnapshot()
            val epubFiles = linkedMapOf<String, ByteArray>()
            snapshot.works.forEach { work ->
                if (!work.hasEpub) return@forEach
                val path = workFileStore.workEpubPath(work.id)
                if (Files.isRegularFile(path)) {
                    val bytes = Files.readAllBytes(path)
                    if (bytes.isNotEmpty()) {
                        epubFiles[BackupPaths.normalizeIdForComparison(work.id)] = bytes
                    }
                }
            }
            val fontFiles = linkedMapOf<String, ByteArray>()
            snapshot.fonts.forEach { font ->
                val bytes = fontFileStore.readFont(font.fileName) ?: return@forEach
                if (bytes.isNotEmpty()) fontFiles[font.fileName] = bytes
            }
            val originalFiles = linkedMapOf<String, ByteArray>()
            snapshot.works.forEach { work -> originalFiles += originalFilesOf(work.id) }
            val pack = KudosBackupPackage(
                manifest = snapshot.toV2Manifest(exportedAt = clock(), appVersion = appVersion),
                epubFilesByWorkId = epubFiles,
                fontFilesByFileName = fontFiles,
                originalFilesByName = originalFiles
            )
            BackupExporter.exportV2(pack)
        }
    }

    /**
     * Import a ZIP archive (bytes from SAF). Default is [BackupImportMode.RECONCILE]
     * (folder-sync LWW). File Merge uses [BackupImportMode.MERGE] (add-only).
     * [BackupImportMode.REPLACE_LIBRARY] makes this device's library match the
     * snapshot without persisting the file's tombstones.
     */
    suspend fun importV2ZipBytes(
        bytes: ByteArray,
        mode: BackupImportMode = BackupImportMode.RECONCILE
    ): BackupRestoreSummary = persistenceGate.withLock {
        withContext(Dispatchers.IO) {
            val pack = BackupImporter.importV2Zip(bytes)
            TombstoneLocalMigration.runIfNeeded(database, settingsRepository)
            val current = captureLibrarySnapshot(pack.fontFilesByFileName.keys)
            val merge = mergePackage(current, pack, mode)
            applyMergeResult(merge)
            restoreOriginals(pack.originalFilesByName, merge.workIdRemap)
            merge.summary
        }
    }

    suspend fun importPackage(
        pack: KudosBackupPackage,
        mode: BackupImportMode = BackupImportMode.RECONCILE,
        normalizeQueuePreservation: Boolean = true
    ): BackupRestoreSummary = persistenceGate.withLock {
        withContext(Dispatchers.IO) {
            BackupFontValidator.validate(pack.fontFilesByFileName)
            TombstoneLocalMigration.runIfNeeded(database, settingsRepository)
            val current = captureLibrarySnapshot(pack.fontFilesByFileName.keys)
            val merge = mergePackage(current, pack, mode, normalizeQueuePreservation)
            applyMergeResult(merge)
            restoreOriginals(pack.originalFilesByName, merge.workIdRemap)
            merge.summary
        }
    }

    /**
     * A work's original and its conversion record under the names iOS gives them (iOS
     * `KudosBackupService.makeContents`). An original over the per-entry limit stays behind:
     * it must not fail the export of everything else.
     */
    suspend fun originalFilesOf(workId: String): Map<String, ByteArray> = withContext(Dispatchers.IO) {
        val file = workFileStore.originalFile(workId) ?: return@withContext emptyMap()
        val size = runCatching { Files.size(file) }.getOrDefault(0L)
        if (size == 0L || size > BackupLimits.MAX_ENTRY_BYTES) return@withContext emptyMap()
        val extension = file.fileName.toString().substringAfterLast('.', "")
        buildMap {
            put(BackupPaths.iosOriginalFileName(workId, extension), Files.readAllBytes(file))
            workFileStore.readConversionRecord(workId)?.let {
                put(BackupPaths.iosConversionRecordFileName(workId), it)
            }
        }
    }

    /**
     * Originals and conversion records from the sync folder, without merging [manifest] again:
     * the sync has merged it already, or it is this device's own. [manifest] only says which
     * work here each file's name means.
     */
    internal suspend fun importOriginalFiles(manifest: KudosBackupManifest, files: Map<String, ByteArray>) =
        persistenceGate.withLock {
            val identity = WorkIdentityIndex.snapshot(database.workDao().getAllIncludingDeleted().map { it.toDomain() })
            val remap = manifest.works.mapNotNull { archived ->
                identity.existingWork(archived.ao3WorkID?.toLong(), archived.sourceURL, archived.id)
                    ?.let { BackupPaths.normalizeIdForComparison(archived.id) to it.id }
            }.toMap()
            restoreOriginals(files, remap)
        }

    /**
     * iOS `KudosBackupService.restore`, the originals loop. A file belongs to the work its name
     * gives, and is written under the id that work has here. Never over an original already
     * here and never beside one: a local original is the file the reader imported on this
     * device, and a work has one, whatever its extension.
     *
     * A conversion record this device lacks is taken with the original it describes: one this
     * restore has just written, or one already here that is the same file as the incoming
     * original (same size, then same SHA-256). A cloud folder delivers files in any order, so
     * a record can arrive after its original. iOS takes a late record without that check,
     * which can attach one device's record to another device's different original.
     */
    private suspend fun restoreOriginals(files: Map<String, ByteArray>, workIdRemap: Map<String, String>) {
        val matchingOriginals = mutableSetOf<String>()
        files.entries.sortedBy { BackupPaths.parseOriginalFileName(it.key)?.second == true }.forEach { (name, bytes) ->
            val (archivedId, isRecord) = BackupPaths.parseOriginalFileName(name) ?: return@forEach
            val workId = workIdRemap[archivedId] ?: return@forEach
            if (isRecord) {
                if (archivedId in matchingOriginals && !workFileStore.conversionRecordExists(workId) &&
                    !workFileStore.writeConversionRecord(workId, bytes)
                ) throw IOException("Could not write conversion record for $workId")
            } else {
                val local = workFileStore.originalFile(workId)
                if (local == null) {
                    workFileStore.writeOriginal(workId, name.substringAfterLast('.', ""), bytes).orThrow()
                    matchingOriginals += archivedId
                } else if (!workFileStore.conversionRecordExists(workId) && runCatching {
                    Files.size(local) == bytes.size.toLong() &&
                        BackupPaths.sha256(Files.readAllBytes(local)) == BackupPaths.sha256(bytes)
                }.getOrDefault(false)) {
                    matchingOriginals += archivedId
                }
            }
        }
    }

    private fun FileWriteResult.orThrow() {
        if (this is FileWriteResult.Failure) throw IOException(message, cause)
    }

    private suspend fun mergePackage(
        current: BackupLibrarySnapshot,
        pack: KudosBackupPackage,
        mode: BackupImportMode,
        normalizeQueuePreservation: Boolean = true
    ): BackupMergeResult {
        val trusted = TombstoneTrustStore(settingsRepository).trustedPublicKeys()
        val result = BackupMergeService.merge(
            current = current,
            backup = pack,
            mode = mode,
            trustedPublicKeys = trusted,
            normalizeQueuePreservation = normalizeQueuePreservation
        )
        // Feeds the pairing sheet's count-only unknown-signer badge. See
        // SettingsRepository.recordUnknownSignerTombstoneIds.
        settingsRepository.recordUnknownSignerTombstoneIds(
            newIds = result.unknownSignerTombstoneIds,
            adoptedIds = result.adoptedIncomingTombstoneIds
        )
        return result
    }

    suspend fun previewImport(pack: KudosBackupPackage): BackupImportPreview {
        val current = captureLibrarySnapshot()
        return BackupMergeService.preview(current, pack)
    }

    fun suggestedSafetyBackupFileName(now: Instant = clock()): String {
        val stamp = DateTimeFormatter.ofPattern("yyyy-MM-dd-HHmmss")
            .withZone(ZoneOffset.systemDefault())
            .format(now)
        return "Kudos-before-replace-$stamp.kudosbackup"
    }

    suspend fun captureLibrarySnapshot(
        incomingFontFileNames: Set<String> = emptySet()
    ): BackupLibrarySnapshot = withContext(Dispatchers.IO) {
        // Include soft-deleted works so export carries Recently Deleted state.
        val works = database.workDao().getAllIncludingDeleted().map { it.toDomain() }
        val userTagsByWorkId = works.associate { work ->
            work.id to database.tagDao().getTagsForWork(work.id).map { it.name }
        }
        val bookmarks = database.bookmarkDao().getAll().map { it.toDomain() }
        val fonts = database.customFontDao().getAll().map { it.toDomain() }
        val collections = database.collectionDao().getAllIncludingDeleted().map { entity ->
            entity.toDomain(database.collectionDao().getWorkIdsForCollection(entity.id))
        }
        val savedSearches = database.savedSearchDao().getAll().map { it.toDomain() }
        val tombstones = database.syncTombstoneDao().getAll().map { it.toDomain() }
        val readingQueues = database.readingQueueDao().getAllQueues().map { it.toDomain() }
        val memberships = database.readingQueueDao().getAllMemberships().map { it.toDomain() }
        val annotations = database.annotationDao().getAll().map { it.toDomain() }
        val readingSessions = database.readingLogDao().getAllSessions()
        val readingFavorites = database.readingLogDao().getAllFavorites()
        val fandomReadWatermarks = database.readingLogDao().getAllWatermarks()
        val tagNamesById = database.tagDao().getAll().associate { it.id to it.name }
        val queueTagNamesByQueueId = database.readingLogDao().getAllQueueTags()
            .groupBy({ it.queueId }, { tagNamesById[it.tagId] })
            .mapValues { (_, names) -> names.filterNotNull() }
        val settings = BackupSettings.fromSettings(settingsRepository.snapshot())
        // iOS `KudosBackupService.mayReplaceEPUB` protects preserved local files;
        // a stale false flag must not hide real bytes from that protection.
        val epubWorkIds = works
            .map { BackupPaths.normalizeIdForComparison(it.id) }
            .filter { id ->
                runCatching { Files.isRegularFile(workFileStore.workEpubPath(id)) }.getOrDefault(false)
            }
            .toSet()
        // Include orphan-but-valid local filenames in the collision set. Restore
        // must never overwrite bytes merely because their DB row is missing.
        val fontFiles = fontFileStore.readAllFontFiles(incomingFontFileNames)

        BackupLibrarySnapshot(
            works = works,
            userTagsByWorkId = userTagsByWorkId,
            bookmarks = bookmarks,
            fonts = fonts,
            collections = collections,
            savedSearches = savedSearches,
            settings = settings,
            epubWorkIds = epubWorkIds,
            fontFilesByFileName = fontFiles,
            tombstones = tombstones,
            readingQueues = readingQueues,
            readingQueueMemberships = memberships,
            annotations = annotations,
            readingSessions = readingSessions,
            readingFavorites = readingFavorites,
            fandomReadWatermarks = fandomReadWatermarks,
            queueTagNamesByQueueId = queueTagNamesByQueueId
        )
    }

    internal suspend fun applyMergeResult(merge: BackupMergeResult) {
        val snapshot = merge.snapshot

        if (merge.mode == BackupImportMode.REPLACE_LIBRARY) {
            removeRecordsAbsentFromReplaceSnapshot(snapshot)
        }

        // Works first so cross-refs have targets.
        snapshot.works.forEach { work ->
            database.workDao().upsert(work.toEntity())
        }

        merge.epubFilesToWriteByWorkId.forEach { (workId, bytes) ->
            val write = workFileStore.writeWorkEpub(workId, bytes)
            // The flag follows the file on disk, whatever the write did.
            val hasFile = workFileStore.workEpubExists(workId)
            database.workDao().getById(workId)?.let { entity ->
                database.workDao().upsert(entity.copy(
                    hasEpub = hasFile,
                    remoteEpubPending = when {
                        write is FileWriteResult.Success -> false
                        !hasFile -> true // Failed installation still owes the promised bytes.
                        else -> entity.remoteEpubPending
                    }
                ))
            }
            // A write that failed kept the old bytes, under a row that now carries the
            // incoming clock. Reported as a success, as it was, the next sync uploaded
            // those old bytes as the newest copy and every other device took them. Failing
            // here stops that upload; the same EPUB is offered again on the next import,
            // and an equal clock still lets it in.
            write.orThrow()
        }

        // User tags (merge-add only).
        snapshot.userTagsByWorkId.forEach { (workId, tagNames) ->
            tagNames.forEach { name ->
                val trimmed = name.trim()
                if (trimmed.isEmpty()) return@forEach
                val tag = database.tagDao().getByNameCaseInsensitive(trimmed)
                    ?: TagEntity(
                        id = uuidFactory(),
                        name = trimmed,
                        dateCreated = clock()
                    ).also { database.tagDao().upsert(it) }
                database.tagDao().addToWork(WorkTagCrossRef(workId = workId, tagId = tag.id))
            }
        }

        snapshot.bookmarks.forEach { database.bookmarkDao().upsert(it.toEntity()) }

        snapshot.fonts.forEach { database.customFontDao().upsert(it.toEntity()) }
        merge.fontFilesToWriteByFileName.forEach { (fileName, bytes) ->
            fontFileStore.writeFont(fileName, bytes).orThrow()
        }

        snapshot.collections.forEach { collection ->
            database.collectionDao().upsert(collection.toEntity())
            if (merge.mode == BackupImportMode.REPLACE_LIBRARY) {
                val desired = collection.workIds
                    .map(BackupPaths::normalizeIdForComparison)
                    .toSet()
                database.collectionDao().getWorkIdsForCollection(collection.id).forEach { workId ->
                    if (BackupPaths.normalizeIdForComparison(workId) !in desired) {
                        database.collectionDao().removeWork(collection.id, workId)
                    }
                }
            }
            collection.workIds.forEach { workId ->
                database.collectionDao().addWork(
                    CollectionWorkCrossRef(collectionId = collection.id, workId = workId)
                )
            }
        }

        // iOS `KudosBackupService.applyTombstonesToExisting` removes captured targets,
        // not anything missing from an earlier snapshot. Ordinary search saves do not
        // take PersistenceGate, so protect later-created/changed rows at apply time.
        database.withTransaction {
            merge.removedSavedSearches.forEach { captured ->
                val held = database.savedSearchDao().getById(captured.id)?.toDomain()
                if (held == captured) database.savedSearchDao().deleteById(captured.id)
            }
        }
        snapshot.savedSearches.forEach { database.savedSearchDao().upsert(it.toEntity()) }

        // Snapshot tombstones are the pre-import local set plus any incoming
        // rows that verified and were already trusted. Unsigned / untrusted
        // incoming never reach here. File import does not write the trust store.
        // WP-F (M2b): additionally refuse to persist an unrecognised record
        // type rather than letting it through to the DAO.
        val knownTombstoneTypes = setOf(
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.SAVED_WORK,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.WORK_COLLECTION,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.READING_QUEUE,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.READING_ANNOTATION,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.BOOKMARK,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.SAVED_SEARCH,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.READING_SESSION,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.READING_FAVORITE,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.FANDOM_READ_WATERMARK
        )
        snapshot.tombstones.forEach { tombstone ->
            if (tombstone.recordTypeRaw in knownTombstoneTypes) {
                database.syncTombstoneDao().upsert(tombstone.toEntity())
            }
        }

        // Queues before memberships (FK).
        snapshot.readingQueues.forEach { database.readingQueueDao().upsertQueue(it.toEntity()) }
        snapshot.queueTagNamesByQueueId.forEach { (queueId, tagNames) ->
            val desiredTagIds = tagNames.normalizedNames().mapTo(mutableSetOf()) { name ->
                val tag = database.tagDao().getByName(name)
                    ?: TagEntity(
                        id = uuidFactory(),
                        name = name,
                        dateCreated = clock()
                    ).also { database.tagDao().upsert(it) }
                database.readingLogDao().upsertQueueTag(
                    QueueTagCrossRef(queueId = queueId, tagId = tag.id)
                )
                tag.id
            }
            if (merge.mode == BackupImportMode.REPLACE_LIBRARY) {
                database.readingLogDao().getQueueTags(queueId).forEach { ref ->
                    if (ref.tagId !in desiredTagIds) {
                        database.readingLogDao().deleteQueueTag(queueId, ref.tagId)
                    }
                }
            }
        }
        snapshot.readingQueueMemberships.forEach {
            database.readingQueueDao().upsertMembership(it.toEntity())
        }
        if (merge.mode == BackupImportMode.REPLACE_LIBRARY) {
            val keepMemberships = snapshot.readingQueueMemberships
                .map { BackupPaths.normalizeIdForComparison(it.id) }
                .toSet()
            // Omitted queues remain recoverable with their memberships. The system
            // queue is never cleared by Replace's absence cleanup either.
            val replacedQueueIds = snapshot.readingQueues
                .filter { it.kindRaw != ReadingQueueKind.SAVED_FOR_LATER }
                .mapTo(HashSet()) { BackupPaths.normalizeIdForComparison(it.id) }
            database.readingQueueDao().getAllMemberships().forEach { membership ->
                if (BackupPaths.normalizeIdForComparison(membership.queueID) in replacedQueueIds &&
                    BackupPaths.normalizeIdForComparison(membership.id) !in keepMemberships
                ) {
                    database.readingQueueDao().deleteMembershipById(membership.id)
                }
            }
        }

        snapshot.annotations.forEach { database.annotationDao().upsert(it.toEntity()) }

        // As for saved searches: only the rows the merge removed from the snapshot it was
        // given, and only if they are unchanged. Reading does not take the persistence gate,
        // so a session, favorite or watermark can be made while an import runs. Swept
        // because it was absent from the merged set, as it was, it was deleted.
        database.withTransaction {
            val heldSessions = database.readingLogDao().getAllSessions().associateBy { it.id }
            merge.removedReadingSessions.forEach { captured ->
                if (heldSessions[captured.id] == captured) database.readingLogDao().deleteSession(captured.id)
            }
            val heldFavorites = database.readingLogDao().getAllFavorites().associateBy { it.id }
            merge.removedReadingFavorites.forEach { captured ->
                if (heldFavorites[captured.id] == captured) database.readingLogDao().deleteFavorite(captured.id)
            }
            val heldWatermarks = database.readingLogDao().getAllWatermarks().associateBy { it.id }
            merge.removedFandomReadWatermarks.forEach { captured ->
                if (heldWatermarks[captured.id] == captured) database.readingLogDao().deleteWatermark(captured.id)
            }
        }
        snapshot.readingSessions.forEach { database.readingLogDao().upsertSession(it) }
        snapshot.readingFavorites.forEach { database.readingLogDao().upsertFavorite(it) }
        snapshot.fandomReadWatermarks.forEach { database.readingLogDao().upsertWatermark(it) }

        if (merge.mode != BackupImportMode.REPLACE_LIBRARY) {
            settingsRepository.replaceAll(snapshot.settings.toSettings())
        }
    }

    /**
     * Replace is this-device-only. Works omitted from the snapshot go to
     * Recently Deleted (no EPUB delete, no SyncTombstone). Bookmarks and
     * saved searches are hard-deleted after merge has minted immediate-delete
     * tombstones. Omitted collections and custom queues keep their memberships
     * for 90 days; annotations keep their rows marked pending deletion (iOS).
     */
    private suspend fun removeRecordsAbsentFromReplaceSnapshot(snapshot: BackupLibrarySnapshot) {
        val now = clock()
        val keepWorks = snapshot.works
            .map { BackupPaths.normalizeIdForComparison(it.id) }
            .toSet()
        database.workDao().getAllIncludingDeleted().forEach { entity ->
            if (BackupPaths.normalizeIdForComparison(entity.id) !in keepWorks) {
                if (!entity.isDeleted) {
                    database.workDao().upsert(
                        entity.copy(
                            isDeleted = true,
                            deletedAt = now,
                            permanentDeletionScheduledAt = now.plus(WorkRepository.RECOVERY_WINDOW)
                        )
                    )
                }
            }
        }

        val keepBookmarkUrls = snapshot.bookmarks.mapTo(mutableSetOf()) { it.urlString }
        database.bookmarkDao().getAll().forEach { entity ->
            if (entity.urlString !in keepBookmarkUrls) {
                database.bookmarkDao().deleteById(entity.id)
            }
        }

        val keepSavedSearches = snapshot.savedSearches
            .map { BackupPaths.normalizeIdForComparison(it.id) }
            .toSet()
        database.savedSearchDao().getAll().forEach { entity ->
            if (BackupPaths.normalizeIdForComparison(entity.id) !in keepSavedSearches) {
                database.savedSearchDao().deleteById(entity.id)
            }
        }

        val keepCollections = snapshot.collections
            .map { BackupPaths.normalizeIdForComparison(it.id) }
            .toSet()
        database.collectionDao().getAllIncludingDeleted().forEach { entity ->
            if (BackupPaths.normalizeIdForComparison(entity.id) !in keepCollections) {
                if (!entity.isDeleted) {
                    database.collectionDao().upsert(entity.copy(
                        isDeleted = true,
                        deletedAt = now,
                        permanentDeletionScheduledAt = now.plus(WorkRepository.RECOVERY_WINDOW)
                    ))
                }
            }
        }

        val keepQueues = snapshot.readingQueues
            .map { BackupPaths.normalizeIdForComparison(it.id) }
            .toSet()
        database.readingQueueDao().getAllQueues().forEach { entity ->
            if (entity.kindRaw != ReadingQueueKind.SAVED_FOR_LATER &&
                BackupPaths.normalizeIdForComparison(entity.id) !in keepQueues && !entity.isDeleted
            ) {
                database.readingQueueDao().upsertQueue(entity.copy(
                    isDeleted = true,
                    deletedAt = now,
                    permanentDeletionScheduledAt = now.plus(WorkRepository.RECOVERY_WINDOW)
                ))
            }
        }

        val keepAnnotations = snapshot.annotations
            .map { BackupPaths.normalizeIdForComparison(it.id) }
            .toSet()
        database.annotationDao().getAll().forEach { entity ->
            if (BackupPaths.normalizeIdForComparison(entity.id) !in keepAnnotations && !entity.isPendingDeletion) {
                database.annotationDao().upsert(entity.copy(isPendingDeletion = true, deletedAt = now))
            }
        }
    }
}

fun BackupRestoreSummary.toUserMessage(): String {
    val parts = buildList {
        if (worksCreated > 0) add("$worksCreated work(s) added")
        if (worksUpdated > 0) add("$worksUpdated work(s) updated")
        if (worksRemoved > 0) add("$worksRemoved work(s) removed from this library")
        if (worksSuppressed > 0) add("$worksSuppressed previously deleted work(s) skipped")
        if (bookmarksCreated + bookmarksUpdated > 0) {
            add("${bookmarksCreated + bookmarksUpdated} bookmark(s)")
        }
        if (fontsCreated + fontsUpdated > 0) {
            add("${fontsCreated + fontsUpdated} font(s)")
        }
        if (collectionsCreated + collectionsUpdated > 0) {
            add("${collectionsCreated + collectionsUpdated} collection(s)")
        }
        if (savedSearchesCreated + savedSearchesUpdated > 0) {
            add("${savedSearchesCreated + savedSearchesUpdated} saved search(es)")
        }
        if (queuesCreated + queuesUpdated > 0) {
            add("${queuesCreated + queuesUpdated} queue(s)")
        }
        if (membershipsCreated + membershipsUpdated > 0) {
            add("${membershipsCreated + membershipsUpdated} queue membership(s)")
        }
        if (annotationsCreated + annotationsUpdated > 0) {
            add("${annotationsCreated + annotationsUpdated} annotation(s)")
        }
        if (annotationsSuppressed > 0) {
            add("$annotationsSuppressed deleted annotation(s) skipped")
        }
    }
    return if (parts.isEmpty()) {
        "Import finished — nothing new to merge."
    } else {
        "Import finished: ${parts.joinToString(", ")}."
    }
}
