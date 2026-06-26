package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection

object BackupMergeService {
    fun merge(
        current: BackupLibrarySnapshot,
        backup: KudosBackupPackage
    ): BackupMergeResult {
        val manifest = BackupValidator.validateManifest(backup.manifest)
        val epubFilesById = backup.epubFilesByWorkId.normalizedWorkFileMap()
        val currentEpubIds = current.epubWorkIds.map(BackupPaths::normalizeIdForComparison).toSet()

        var summary = BackupRestoreSummary()
        val epubFilesToWrite = linkedMapOf<String, ByteArray>()

        val worksById = current.works
            .associateByTo(linkedMapOf()) { BackupPaths.normalizeIdForComparison(it.id) }
        val userTagsByWorkId = current.userTagsByWorkId
            .mapKeys { BackupPaths.normalizeIdForComparison(it.key) }
            .mapValues { it.value.normalizedNames() }
            .toMutableMap()

        manifest.works.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "work.id")
            val existing = worksById[id]
            val incomingEpub = epubFilesById[id]
            val existingHasEpub = id in currentEpubIds || existing?.hasEpub == true
            val restoredHasEpub = incomingEpub != null || existingHasEpub

            val restored = archived.toSavedWork(hasEpub = restoredHasEpub)
            worksById[id] = if (existing == null) {
                summary = summary.copy(worksCreated = summary.worksCreated + 1)
                restored
            } else {
                summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
                mergeWork(existing, restored, archived)
            }

            if (incomingEpub != null) {
                epubFilesToWrite[id] = incomingEpub
            }

            val mergedTags = (userTagsByWorkId[id].orEmpty() + archived.userTags).normalizedNames()
            if (mergedTags.isNotEmpty()) userTagsByWorkId[id] = mergedTags
        }

        val bookmarks = mergeBookmarks(current.bookmarks, manifest.bookmarks).also {
            summary = summary.copy(
                bookmarksCreated = it.created,
                bookmarksUpdated = it.updated
            )
        }.items

        val fontMerge = mergeFonts(
            currentFonts = current.fonts,
            currentFontFiles = current.fontFilesByFileName,
            manifestFonts = manifest.fonts,
            backupFontFiles = backup.fontFilesByFileName
        )
        summary = summary.copy(
            fontsCreated = fontMerge.created,
            fontsUpdated = fontMerge.updated
        )

        val collections = mergeCollections(current.collections, manifest.collections).also {
            summary = summary.copy(
                collectionsCreated = it.created,
                collectionsUpdated = it.updated
            )
        }.items

        val savedSearches = mergeSavedSearches(current.savedSearches, manifest.savedSearches).also {
            summary = summary.copy(
                savedSearchesCreated = it.created,
                savedSearchesUpdated = it.updated
            )
        }.items

        val settingsPayload = manifest.settings.retargetRenamedFont(fontMerge.renamedFonts)
        val settings = BackupValidator
            .normalizeSettings(settingsPayload, fontMerge.items.map { it.fileName }.toSet())
            .toCoreBackupSettings()

        return BackupMergeResult(
            snapshot = BackupLibrarySnapshot(
                works = worksById.values.sortedByDescending { it.dateAdded },
                userTagsByWorkId = userTagsByWorkId,
                bookmarks = bookmarks,
                fonts = fontMerge.items,
                collections = collections,
                savedSearches = savedSearches,
                settings = settings,
                epubWorkIds = currentEpubIds + epubFilesToWrite.keys,
                fontFilesByFileName = current.fontFilesByFileName + fontMerge.filesToWrite
            ),
            summary = summary,
            epubFilesToWriteByWorkId = epubFilesToWrite,
            fontFilesToWriteByFileName = fontMerge.filesToWrite
        )
    }

    private fun mergeWork(
        existing: SavedWork,
        restored: SavedWork,
        archived: BackupWork
    ): SavedWork {
        return restored.copy(
            comments = archived.comments ?: existing.comments,
            hits = archived.hits ?: existing.hits,
            knownChapterCount = archived.knownChapterCount ?: existing.knownChapterCount,
            lastUpdateCheck = if (archived.lastUpdateCheck == null) {
                existing.lastUpdateCheck
            } else {
                restored.lastUpdateCheck
            },
            readiumLocator = archived.readiumLocator ?: existing.readiumLocator
        )
    }

    private fun mergeBookmarks(
        current: List<Bookmark>,
        incoming: List<BackupBookmark>
    ): MergeItems<Bookmark> {
        val byUrl = current.associateByTo(linkedMapOf()) { it.urlString }
        var created = 0
        var updated = 0
        incoming.forEach { archived ->
            val existing = byUrl[archived.urlString]
            byUrl[archived.urlString] = if (existing == null) {
                created += 1
                archived.toBookmark()
            } else {
                updated += 1
                existing.copy(
                    title = archived.title,
                    dateAdded = BackupValidator.parseInstant(archived.dateAdded, "bookmark.dateAdded")
                )
            }
        }
        return MergeItems(byUrl.values.sortedByDescending { it.dateAdded }, created, updated)
    }

    private fun mergeFonts(
        currentFonts: List<CustomFont>,
        currentFontFiles: Map<String, ByteArray>,
        manifestFonts: List<BackupFont>,
        backupFontFiles: Map<String, ByteArray>
    ): FontMerge {
        val fontsByName = currentFonts.associateByTo(linkedMapOf()) { it.fileName }
        val filesToWrite = linkedMapOf<String, ByteArray>()
        val renamedFonts = mutableMapOf<String, String>()
        var created = 0
        var updated = 0

        manifestFonts.forEach { archived ->
            val incomingBytes = backupFontFiles[archived.fileName] ?: return@forEach
            val existing = fontsByName[archived.fileName]
            if (existing == null) {
                val font = archived.toCustomFont()
                fontsByName[font.fileName] = font
                filesToWrite[font.fileName] = incomingBytes
                created += 1
                return@forEach
            }

            val existingBytes = currentFontFiles[archived.fileName]
            if (existingBytes != null &&
                BackupPaths.sha256(existingBytes) == BackupPaths.sha256(incomingBytes)
            ) {
                fontsByName[archived.fileName] = existing.copy(
                    name = archived.name,
                    dateAdded = BackupValidator.parseInstant(archived.dateAdded, "font.dateAdded")
                )
                updated += 1
            } else {
                // Filename collision with different or unknown bytes: keep local file and suffix restore.
                val newFileName = BackupPaths.uniqueSuffixedFontFileName(
                    archived.fileName,
                    fontsByName.keys + filesToWrite.keys
                )
                fontsByName[newFileName] = archived.toCustomFont(fileNameOverride = newFileName)
                filesToWrite[newFileName] = incomingBytes
                renamedFonts[archived.fileName] = newFileName
                created += 1
            }
        }

        return FontMerge(
            items = fontsByName.values.sortedBy { it.fileName },
            filesToWrite = filesToWrite,
            renamedFonts = renamedFonts,
            created = created,
            updated = updated
        )
    }

    private fun mergeCollections(
        current: List<WorkCollection>,
        incoming: List<BackupCollection>
    ): MergeItems<WorkCollection> {
        val collectionsById = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        val names = current.mapTo(mutableSetOf()) { it.name }
        var created = 0
        var updated = 0

        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "collection.id")
            val existing = collectionsById[id]
            if (existing == null) {
                val restoredName = archived.name.uniqueName(names)
                val restored = archived.toWorkCollection(nameOverride = restoredName)
                collectionsById[id] = restored
                names += restoredName
                created += 1
            } else {
                val mergedWorkIds = (existing.workIds + archived.workIDs)
                    .map { BackupPaths.normalizeIdForComparison(it) }
                    .distinct()
                collectionsById[id] = existing.copy(
                    name = archived.name,
                    dateAdded = BackupValidator.parseInstant(archived.dateAdded, "collection.dateAdded"),
                    workIds = mergedWorkIds,
                    description = archived.description ?: existing.description,
                    sortOrder = archived.sortOrder ?: existing.sortOrder
                )
                names += archived.name
                updated += 1
            }
        }

        return MergeItems(collectionsById.values.sortedBy { it.name.lowercase() }, created, updated)
    }

    private fun mergeSavedSearches(
        current: List<SavedSearch>,
        incoming: List<BackupSavedSearch>
    ): MergeItems<SavedSearch> {
        val searchesById = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        val names = current.mapTo(mutableSetOf()) { it.name }
        var created = 0
        var updated = 0

        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "savedSearch.id")
            val existing = searchesById[id]
            if (existing == null) {
                val restoredName = archived.name.uniqueName(names)
                searchesById[id] = archived.toSavedSearch(nameOverride = restoredName)
                names += restoredName
                created += 1
            } else {
                searchesById[id] = existing.copy(
                    name = archived.name,
                    dateAdded = BackupValidator.parseInstant(archived.dateAdded, "savedSearch.dateAdded"),
                    filtersJson = archived.filters.toString()
                )
                names += archived.name
                updated += 1
            }
        }

        return MergeItems(searchesById.values.sortedBy { it.name.lowercase() }, created, updated)
    }

    private fun Map<String, ByteArray>.normalizedWorkFileMap(): Map<String, ByteArray> {
        return mapKeys { BackupPaths.normalizeIdForComparison(it.key) }
    }

    private fun BackupSettingsPayload.retargetRenamedFont(
        renamedFonts: Map<String, String>
    ): BackupSettingsPayload {
        if (!readerFontID.startsWith("custom:")) return this
        val fileName = readerFontID.removePrefix("custom:")
        val newFileName = renamedFonts[fileName] ?: return this
        return copy(readerFontID = "custom:$newFileName")
    }

    private fun String.uniqueName(existingNames: Set<String>): String {
        if (this !in existingNames) return this
        var index = 1
        while (true) {
            val candidate = "$this (Restored${if (index == 1) "" else " $index"})"
            if (candidate !in existingNames) return candidate
            index += 1
        }
    }

    private data class MergeItems<T>(
        val items: List<T>,
        val created: Int,
        val updated: Int
    )

    private data class FontMerge(
        val items: List<CustomFont>,
        val filesToWrite: Map<String, ByteArray>,
        val renamedFonts: Map<String, String>,
        val created: Int,
        val updated: Int
    )
}
