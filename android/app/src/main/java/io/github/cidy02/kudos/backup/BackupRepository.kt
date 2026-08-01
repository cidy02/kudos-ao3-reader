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

    suspend fun exportV2ZipBytes(): ByteArray = withContext(Dispatchers.IO) {
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

    /**
     * Import a ZIP archive (bytes from SAF). Merge-only restore; never deletes
     * existing local works. Returns a human-readable summary.
     */
    suspend fun importV2ZipBytes(bytes: ByteArray): BackupRestoreSummary = withContext(Dispatchers.IO) {
        val pack = BackupImporter.importV2Zip(bytes)
        val current = captureLibrarySnapshot()
        val merge = BackupMergeService.merge(current, pack)
        applyMergeResult(merge)
        merge.summary
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
            collection.workIds.forEach { workId ->
                database.collectionDao().addWork(
                    CollectionWorkCrossRef(collectionId = collection.id, workId = workId)
                )
            }
        }

        snapshot.savedSearches.forEach { database.savedSearchDao().upsert(it.toEntity()) }

        snapshot.tombstones.forEach { database.syncTombstoneDao().upsert(it.toEntity()) }

        // Queues before memberships (FK).
        snapshot.readingQueues.forEach { database.readingQueueDao().upsertQueue(it.toEntity()) }
        snapshot.readingQueueMemberships.forEach {
            database.readingQueueDao().upsertMembership(it.toEntity())
        }

        snapshot.annotations.forEach { database.annotationDao().upsert(it.toEntity()) }

        settingsRepository.replaceAll(snapshot.settings.toSettings())
    }
}

fun BackupRestoreSummary.toUserMessage(): String {
    val parts = buildList {
        if (worksCreated > 0) add("$worksCreated work(s) added")
        if (worksUpdated > 0) add("$worksUpdated work(s) updated")
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
