package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.BackupSettings
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkRepository
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
            val pack = KudosBackupPackage(
                manifest = snapshot.toV2Manifest(exportedAt = clock(), appVersion = appVersion),
                epubFilesByWorkId = epubFiles,
                fontFilesByFileName = fontFiles
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
            val current = captureLibrarySnapshot()
            val merge = mergePackage(current, pack, mode)
            applyMergeResult(merge)
            merge.summary
        }
    }

    suspend fun importPackage(
        pack: KudosBackupPackage,
        mode: BackupImportMode = BackupImportMode.RECONCILE
    ): BackupRestoreSummary = persistenceGate.withLock {
        withContext(Dispatchers.IO) {
            TombstoneLocalMigration.runIfNeeded(database, settingsRepository)
            val current = captureLibrarySnapshot()
            val merge = mergePackage(current, pack, mode)
            applyMergeResult(merge)
            merge.summary
        }
    }

    private suspend fun mergePackage(
        current: BackupLibrarySnapshot,
        pack: KudosBackupPackage,
        mode: BackupImportMode
    ): BackupMergeResult {
        val trusted = TombstoneTrustStore(settingsRepository).trustedPublicKeys()
        return BackupMergeService.merge(
            current = current,
            backup = pack,
            mode = mode,
            trustedPublicKeys = trusted
        )
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

    suspend fun captureLibrarySnapshot(): BackupLibrarySnapshot = withContext(Dispatchers.IO) {
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
        val settings = BackupSettings.fromSettings(settingsRepository.snapshot())
        val epubWorkIds = works
            .filter { it.hasEpub }
            .map { BackupPaths.normalizeIdForComparison(it.id) }
            .filter { id ->
                runCatching { Files.isRegularFile(workFileStore.workEpubPath(id)) }.getOrDefault(false)
            }
            .toSet()
        val fontFiles = fonts.mapNotNull { font ->
            fontFileStore.readFont(font.fileName)?.let { font.fileName to it }
        }.toMap()

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
            annotations = annotations
        )
    }

    private suspend fun applyMergeResult(merge: BackupMergeResult) {
        val snapshot = merge.snapshot

        if (merge.mode == BackupImportMode.REPLACE_LIBRARY) {
            removeRecordsAbsentFromReplaceSnapshot(snapshot)
        }

        // Works first so cross-refs have targets.
        snapshot.works.forEach { work ->
            database.workDao().upsert(work.toEntity())
        }

        merge.epubFilesToWriteByWorkId.forEach { (workId, bytes) ->
            workFileStore.writeWorkEpub(workId, bytes)
            database.workDao().getById(workId)?.let { entity ->
                if (!entity.hasEpub) {
                    database.workDao().upsert(entity.copy(hasEpub = true))
                }
            }
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
            fontFileStore.writeFont(fileName, bytes)
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

        snapshot.savedSearches.forEach { database.savedSearchDao().upsert(it.toEntity()) }

        // Snapshot tombstones are the pre-import local set plus any incoming
        // rows that verified and were already trusted. Unsigned / untrusted
        // incoming never reach here. File import does not write the trust store.
        snapshot.tombstones.forEach { database.syncTombstoneDao().upsert(it.toEntity()) }

        // Queues before memberships (FK).
        snapshot.readingQueues.forEach { database.readingQueueDao().upsertQueue(it.toEntity()) }
        snapshot.readingQueueMemberships.forEach {
            database.readingQueueDao().upsertMembership(it.toEntity())
        }
        if (merge.mode == BackupImportMode.REPLACE_LIBRARY) {
            val keepMemberships = snapshot.readingQueueMemberships
                .map { BackupPaths.normalizeIdForComparison(it.id) }
                .toSet()
            database.readingQueueDao().getAllMemberships().forEach { membership ->
                if (BackupPaths.normalizeIdForComparison(membership.id) !in keepMemberships) {
                    database.readingQueueDao().deleteMembershipById(membership.id)
                }
            }
        }

        snapshot.annotations.forEach { database.annotationDao().upsert(it.toEntity()) }

        if (merge.mode != BackupImportMode.REPLACE_LIBRARY) {
            settingsRepository.replaceAll(snapshot.settings.toSettings())
        }
    }

    /**
     * Replace is this-device-only. Works omitted from the snapshot go to
     * Recently Deleted (no EPUB delete, no SyncTombstone). Bookmarks / saved
     * searches / collections / queues / annotations without a Recently Deleted
     * persist path are DAO-deleted — do not mint tombstones.
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
                database.collectionDao().removeAllWorks(entity.id)
                database.collectionDao().deleteById(entity.id)
            }
        }

        val keepQueues = snapshot.readingQueues
            .map { BackupPaths.normalizeIdForComparison(it.id) }
            .toSet()
        database.readingQueueDao().getAllQueues().forEach { entity ->
            if (BackupPaths.normalizeIdForComparison(entity.id) !in keepQueues) {
                database.readingQueueDao().deleteQueueById(entity.id)
            }
        }

        val keepAnnotations = snapshot.annotations
            .map { BackupPaths.normalizeIdForComparison(it.id) }
            .toSet()
        database.annotationDao().getAll().forEach { entity ->
            if (BackupPaths.normalizeIdForComparison(entity.id) !in keepAnnotations) {
                database.annotationDao().deleteById(entity.id)
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
