package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.BackupSettings as CoreBackupSettings
import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import java.time.Instant
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject

fun BackupLibrarySnapshot.toV2Manifest(
    exportedAt: Instant,
    appVersion: String = "0.1.0"
): KudosBackupManifest {
    val collectionIdsByWork = collections
        .flatMap { collection -> collection.workIds.map { workId -> workId to collection.id } }
        .groupBy({ BackupPaths.normalizeIdForComparison(it.first) }, { it.second })

    return KudosBackupManifest(
        version = BackupVersion.ZIP_V2,
        exportedAt = BackupValidator.formatInstant(exportedAt),
        exportedBy = BackupExportedBy(
            platform = "android",
            appVersion = appVersion,
            schemaVersion = 1
        ),
        works = works
            .sortedBy { BackupPaths.normalizeIdForComparison(it.id) }
            .map { work ->
                val normalizedWorkId = BackupPaths.normalizeIdForComparison(work.id)
                work.toBackupWork(
                    userTags = userTagsByWorkId[work.id]
                        ?: userTagsByWorkId[normalizedWorkId].orEmpty(),
                    collectionIds = collectionIdsByWork[normalizedWorkId].orEmpty()
                )
            },
        bookmarks = bookmarks.sortedBy { it.urlString }.map { it.toBackupBookmark() },
        fonts = fonts.sortedBy { it.fileName }.map { it.toBackupFont() },
        collections = collections
            .sortedBy { BackupPaths.normalizeIdForComparison(it.id) }
            .map { it.toBackupCollection() },
        savedSearches = savedSearches
            .sortedBy { BackupPaths.normalizeIdForComparison(it.id) }
            .map { it.toBackupSavedSearch() },
        settings = settings.toBackupSettingsPayload()
    )
}

fun SavedWork.toBackupWork(
    userTags: List<String> = emptyList(),
    collectionIds: List<String> = emptyList()
): BackupWork {
    return BackupWork(
        id = BackupPaths.canonicalUuid(id, "work.id"),
        title = title,
        author = author,
        summary = summary,
        sourceURL = sourceUrl,
        dateAdded = BackupValidator.formatInstant(dateAdded),
        isFavorite = isFavorite,
        isSaved = isSaved,
        isFinished = isFinished,
        hasEPUB = hasEpub,
        isComplete = isComplete,
        rating = rating,
        language = language,
        wordCount = wordCount,
        chapters = chapters,
        kudos = kudos,
        comments = comments,
        hits = hits,
        workWarnings = workWarnings,
        workCategories = workCategories,
        seriesTitle = seriesTitle,
        seriesPosition = seriesPosition,
        seriesURL = seriesUrl,
        lastSpineIndex = lastSpineIndex,
        lastScrollFraction = lastScrollFraction,
        lastReadDate = lastReadDate?.let(BackupValidator::formatInstant),
        knownChapterCount = knownChapterCount,
        lastUpdateCheck = lastUpdateCheck?.let(BackupValidator::formatInstant),
        workTags = workTags,
        workFandoms = workFandoms,
        workCharacters = workCharacters,
        workRelationships = workRelationships,
        workFreeforms = workFreeforms,
        workTagsFetched = workTagsFetched,
        userTags = userTags.normalizedNames(),
        collectionIDs = collectionIds.map { BackupPaths.canonicalUuid(it, "collection.id") },
        readiumLocator = readiumLocator
    )
}

fun BackupWork.toSavedWork(hasEpub: Boolean): SavedWork {
    return SavedWork(
        id = BackupPaths.canonicalUuid(id, "work.id"),
        title = title,
        author = author,
        summary = summary,
        sourceUrl = sourceURL,
        dateAdded = BackupValidator.parseInstant(dateAdded, "work.dateAdded"),
        isFavorite = isFavorite,
        isSaved = isSaved,
        isFinished = isFinished,
        hasEpub = hasEpub,
        isComplete = isComplete,
        rating = rating,
        language = language,
        wordCount = wordCount,
        chapters = chapters,
        kudos = kudos,
        seriesTitle = seriesTitle,
        seriesPosition = seriesPosition,
        seriesUrl = seriesURL,
        lastSpineIndex = lastSpineIndex,
        lastScrollFraction = lastScrollFraction,
        lastReadDate = BackupValidator.parseNullableInstant(lastReadDate, "work.lastReadDate"),
        workWarnings = workWarnings,
        workCategories = workCategories,
        workTags = workTags,
        workFandoms = workFandoms,
        workCharacters = workCharacters,
        workRelationships = workRelationships,
        workFreeforms = workFreeforms,
        workTagsFetched = workTagsFetched,
        readiumLocator = readiumLocator,
        comments = comments,
        hits = hits,
        knownChapterCount = knownChapterCount,
        lastUpdateCheck = BackupValidator.parseNullableInstant(lastUpdateCheck, "work.lastUpdateCheck")
    )
}

fun Bookmark.toBackupBookmark(): BackupBookmark {
    return BackupBookmark(
        title = title,
        urlString = urlString,
        dateAdded = BackupValidator.formatInstant(dateAdded)
    )
}

fun BackupBookmark.toBookmark(): Bookmark {
    return Bookmark(
        title = title,
        urlString = urlString,
        dateAdded = BackupValidator.parseInstant(dateAdded, "bookmark.dateAdded")
    )
}

fun CustomFont.toBackupFont(): BackupFont {
    return BackupFont(
        name = name,
        fileName = fileName,
        dateAdded = BackupValidator.formatInstant(dateAdded)
    )
}

fun BackupFont.toCustomFont(fileNameOverride: String = fileName): CustomFont {
    return CustomFont(
        name = name,
        fileName = fileNameOverride,
        dateAdded = BackupValidator.parseInstant(dateAdded, "font.dateAdded")
    )
}

fun WorkCollection.toBackupCollection(): BackupCollection {
    return BackupCollection(
        id = BackupPaths.canonicalUuid(id, "collection.id"),
        name = name,
        dateAdded = BackupValidator.formatInstant(dateAdded),
        workIDs = workIds.map { BackupPaths.canonicalUuid(it, "collection.workId") },
        description = description,
        sortOrder = sortOrder
    )
}

fun BackupCollection.toWorkCollection(nameOverride: String = name): WorkCollection {
    return WorkCollection(
        id = BackupPaths.canonicalUuid(id, "collection.id"),
        name = nameOverride,
        dateAdded = BackupValidator.parseInstant(dateAdded, "collection.dateAdded"),
        workIds = workIDs.map { BackupPaths.canonicalUuid(it, "collection.workId") },
        description = description,
        sortOrder = sortOrder
    )
}

fun SavedSearch.toBackupSavedSearch(): BackupSavedSearch {
    return BackupSavedSearch(
        id = BackupPaths.canonicalUuid(id, "savedSearch.id"),
        name = name,
        dateAdded = BackupValidator.formatInstant(dateAdded),
        filters = filtersJson.toJsonObjectOrEmpty()
    )
}

fun BackupSavedSearch.toSavedSearch(nameOverride: String = name): SavedSearch {
    return SavedSearch(
        id = BackupPaths.canonicalUuid(id, "savedSearch.id"),
        name = nameOverride,
        dateAdded = BackupValidator.parseInstant(dateAdded, "savedSearch.dateAdded"),
        filtersJson = filters.toString()
    )
}

fun CoreBackupSettings.toBackupSettingsPayload(): BackupSettingsPayload {
    return BackupSettingsPayload(
        readerFontID = readerFontID,
        readerMode = readerMode,
        readerTwoPage = readerTwoPage,
        readerCustomize = readerCustomize,
        readerBoldText = readerBoldText,
        readerFontPt = readerFontPt,
        readerLineHeight = readerLineHeight,
        readerLetterSpacing = readerLetterSpacing,
        readerWordSpacing = readerWordSpacing,
        readerMargin = readerMargin,
        readerJustify = readerJustify,
        confirmBeforeDelete = confirmBeforeDelete,
        hideMatureContent = hideMatureContent,
        matureContentMode = matureContentMode,
        requireBiometricToReveal = requireBiometricToReveal,
        appTheme = appTheme,
        readerTheme = readerTheme,
        matchAppReaderTheme = matchAppReaderTheme,
        accentColorHex = accentColorHex
    )
}

fun BackupSettingsPayload.toCoreBackupSettings(): CoreBackupSettings {
    return CoreBackupSettings(
        readerFontID = readerFontID,
        readerMode = readerMode,
        readerTwoPage = readerTwoPage,
        readerCustomize = readerCustomize,
        readerBoldText = readerBoldText,
        readerFontPt = readerFontPt,
        readerLineHeight = readerLineHeight,
        readerLetterSpacing = readerLetterSpacing,
        readerWordSpacing = readerWordSpacing,
        readerMargin = readerMargin,
        readerJustify = readerJustify,
        confirmBeforeDelete = confirmBeforeDelete,
        hideMatureContent = hideMatureContent,
        matureContentMode = matureContentMode,
        requireBiometricToReveal = requireBiometricToReveal,
        appTheme = appTheme,
        readerTheme = readerTheme,
        matchAppReaderTheme = matchAppReaderTheme,
        accentColorHex = accentColorHex
    )
}

internal fun List<String>.normalizedNames(): List<String> {
    val seen = linkedSetOf<String>()
    forEach { raw ->
        val trimmed = raw.trim()
        if (trimmed.isNotEmpty()) seen += trimmed
    }
    return seen.toList()
}

private fun String.toJsonObjectOrEmpty(): JsonObject {
    return try {
        BackupJson.parseToJsonElement(this).jsonObject
    } catch (_: IllegalArgumentException) {
        buildJsonObject {}
    }
}
