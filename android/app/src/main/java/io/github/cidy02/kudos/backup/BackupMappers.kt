package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.BackupSettings as CoreBackupSettings
import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.canonicalizeCollectionMembershipRecordId
import io.github.cidy02.kudos.works.WorkRepository
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
        version = BackupVersion.CURRENT,
        exportedAt = BackupValidator.formatInstant(exportedAt),
        exportedBy = BackupExportedBy(
            platform = "android",
            appVersion = appVersion,
            schemaVersion = BackupVersion.CURRENT
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
        readingQueues = readingQueues
            .sortedBy { BackupPaths.normalizeIdForComparison(it.id) }
            .map { it.toBackupReadingQueue() },
        readingQueueMemberships = readingQueueMemberships
            .sortedBy { BackupPaths.normalizeIdForComparison(it.id) }
            .map { it.toBackupReadingQueueMembership() },
        annotations = annotations
            .sortedBy { BackupPaths.normalizeIdForComparison(it.id) }
            .map { it.toBackupAnnotation() },
        tombstones = tombstones
            .sortedBy { BackupPaths.normalizeIdForComparison(it.id) }
            .map { it.toBackupTombstone() },
        settings = settings.toBackupSettingsPayload()
    )
}

data class RestoredDeletionState(
    val isDeleted: Boolean,
    val permanentDeletionScheduledAt: Instant?
)

fun restoredDeletionState(archivedIsDeleted: Boolean?): RestoredDeletionState {
    val deleted = archivedIsDeleted == true
    return RestoredDeletionState(
        isDeleted = deleted,
        permanentDeletionScheduledAt = if (deleted) {
            Instant.now().plus(WorkRepository.RECOVERY_WINDOW)
        } else {
            null
        }
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
        isQueuedForLater = isQueuedForLater,
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
        readiumLocator = readiumLocator,
        lastModifiedAt = (lastModifiedAt ?: dateAdded).let(BackupValidator::formatInstant),
        progressModifiedAt = progressModifiedAt?.let(BackupValidator::formatInstant)
            ?: lastReadDate?.let(BackupValidator::formatInstant),
        ao3Unavailable = ao3Unavailable,
        lastAvailabilityCheck = lastAvailabilityCheck?.let(BackupValidator::formatInstant),
        isDeleted = isDeleted,
        deletedAt = deletedAt?.let(BackupValidator::formatInstant),
        permanentDeletionScheduledAt = permanentDeletionScheduledAt
            ?.let(BackupValidator::formatInstant),
        // Pass-through only — do not default null to "notPreserved" (would rewrite iOS data).
        epubPreservationStatusRaw = epubPreservationStatusRaw,
        preservedAt = preservedAt?.let(BackupValidator::formatInstant),
        lastPreservationAttemptAt = lastPreservationAttemptAt?.let(BackupValidator::formatInstant)
    )
}

fun BackupWork.toSavedWork(hasEpub: Boolean): SavedWork {
    val added = if (dateAdded.isNotBlank()) {
        BackupValidator.parseInstant(dateAdded, "work.dateAdded")
    } else {
        java.time.Instant.now()
    }
    val lastModified = BackupValidator.parseNullableInstant(
        lastModifiedAt?.takeIf { it.isNotBlank() },
        "work.lastModifiedAt"
    ) ?: added
    val deletionState = restoredDeletionState(isDeleted)
    return SavedWork(
        id = BackupPaths.canonicalUuid(id, "work.id"),
        title = title,
        author = author,
        summary = summary,
        sourceUrl = io.github.cidy02.kudos.works.WorkTags.canonicalAO3WorkURL(sourceURL)
            ?: sourceURL,
        dateAdded = added,
        isFavorite = isFavorite,
        // Honour the archive's flag exactly, as iOS does (`KudosBackup.swift`
        // `work.isSaved = incomingWins ? archived.isSaved : work.isSaved`).
        // Forcing saved whenever an EPUB was present destroyed the queue-only
        // state on the way in: a work you had queued but deliberately not saved
        // came back sitting on the Library shelves. Owner decision — Android
        // adopts iOS's queue-only concept rather than the other way round.
        isSaved = isSaved,
        isQueuedForLater = isQueuedForLater ?: false,
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
        lastReadDate = BackupValidator.parseNullableInstant(
            lastReadDate?.takeIf { it.isNotBlank() },
            "work.lastReadDate"
        ),
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
        lastUpdateCheck = BackupValidator.parseNullableInstant(
            lastUpdateCheck?.takeIf { it.isNotBlank() },
            "work.lastUpdateCheck"
        ),
        lastModifiedAt = lastModified,
        progressModifiedAt = BackupValidator.parseNullableInstant(
            progressModifiedAt?.takeIf { it.isNotBlank() },
            "work.progressModifiedAt"
        ),
        ao3Unavailable = ao3Unavailable ?: false,
        lastAvailabilityCheck = BackupValidator.parseNullableInstant(
            lastAvailabilityCheck?.takeIf { it.isNotBlank() },
            "work.lastAvailabilityCheck"
        ),
        isDeleted = deletionState.isDeleted,
        deletedAt = if (deletionState.isDeleted) {
            BackupValidator.parseNullableInstant(
                deletedAt?.takeIf { it.isNotBlank() },
                "work.deletedAt"
            )
        } else null,
        permanentDeletionScheduledAt = deletionState.permanentDeletionScheduledAt,
        // Pass-through: blank/absent stays null (never invent "notPreserved").
        epubPreservationStatusRaw = epubPreservationStatusRaw?.takeIf { it.isNotBlank() },
        preservedAt = BackupValidator.parseNullableInstant(
            preservedAt?.takeIf { it.isNotBlank() },
            "work.preservedAt"
        ),
        lastPreservationAttemptAt = BackupValidator.parseNullableInstant(
            lastPreservationAttemptAt?.takeIf { it.isNotBlank() },
            "work.lastPreservationAttemptAt"
        )
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
        sortOrder = sortOrder,
        lastModifiedAt = lastModifiedAt?.let { BackupValidator.formatInstant(it) },
        deletedAt = deletedAt?.let { BackupValidator.formatInstant(it) },
        isDeleted = isDeleted,
        permanentDeletionScheduledAt = permanentDeletionScheduledAt
            ?.let { BackupValidator.formatInstant(it) }
    )
}

fun BackupCollection.toWorkCollection(nameOverride: String = name): WorkCollection {
    val deletionState = restoredDeletionState(isDeleted)
    return WorkCollection(
        id = BackupPaths.canonicalUuid(id, "collection.id"),
        name = nameOverride,
        dateAdded = BackupValidator.parseInstant(dateAdded, "collection.dateAdded"),
        workIds = workIDs.map { BackupPaths.canonicalUuid(it, "collection.workId") },
        description = description,
        sortOrder = sortOrder,
        lastModifiedAt = lastModifiedAt?.takeIf { it.isNotBlank() }
            ?.let { BackupValidator.parseInstant(it, "collection.lastModifiedAt") },
        isDeleted = deletionState.isDeleted,
        deletedAt = if (deletionState.isDeleted) {
            deletedAt?.takeIf { it.isNotBlank() }?.let { BackupValidator.parseInstant(it, "collection.deletedAt") }
        } else null,
        permanentDeletionScheduledAt = deletionState.permanentDeletionScheduledAt
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

fun ReadingQueue.toBackupReadingQueue(): BackupReadingQueue {
    return BackupReadingQueue(
        id = BackupPaths.canonicalUuid(id, "queue.id"),
        name = name,
        kindRaw = kindRaw,
        sortOrder = sortOrder,
        dateCreated = BackupValidator.formatInstant(dateCreated),
        dateUpdated = BackupValidator.formatInstant(dateUpdated),
        lastMembershipChangedAt = lastMembershipChangedAt?.let(BackupValidator::formatInstant),
        deletedAt = deletedAt?.let(BackupValidator::formatInstant),
        isDeleted = isDeleted,
        permanentDeletionScheduledAt = permanentDeletionScheduledAt
            ?.let(BackupValidator::formatInstant)
    )
}

fun BackupReadingQueue.toReadingQueue(): ReadingQueue {
    val created = if (dateCreated.isNotBlank()) {
        BackupValidator.parseInstant(dateCreated, "queue.dateCreated")
    } else {
        Instant.now()
    }
    val updated = if (dateUpdated.isNotBlank()) {
        BackupValidator.parseInstant(dateUpdated, "queue.dateUpdated")
    } else {
        created
    }
    val deletionState = restoredDeletionState(isDeleted)
    return ReadingQueue(
        id = BackupPaths.canonicalUuid(id, "queue.id"),
        name = name,
        kindRaw = kindRaw.ifBlank { "custom" },
        sortOrder = sortOrder,
        dateCreated = created,
        dateUpdated = updated,
        lastMembershipChangedAt = BackupValidator.parseNullableInstant(
            lastMembershipChangedAt?.takeIf { it.isNotBlank() },
            "queue.lastMembershipChangedAt"
        ),
        deletedAt = if (deletionState.isDeleted) {
            BackupValidator.parseNullableInstant(
                deletedAt?.takeIf { it.isNotBlank() },
                "queue.deletedAt"
            )
        } else null,
        isDeleted = deletionState.isDeleted,
        permanentDeletionScheduledAt = deletionState.permanentDeletionScheduledAt
    )
}

fun ReadingQueueMembership.toBackupReadingQueueMembership(): BackupReadingQueueMembership {
    return BackupReadingQueueMembership(
        id = BackupPaths.canonicalUuid(id, "membership.id"),
        queueID = BackupPaths.canonicalUuid(queueID, "membership.queueID"),
        workID = BackupPaths.canonicalUuid(workID, "membership.workID"),
        queuedAt = BackupValidator.formatInstant(queuedAt),
        lastModifiedAt = lastModifiedAt?.let(BackupValidator::formatInstant),
        sortOrderInQueue = sortOrderInQueue,
        note = note
    )
}

fun BackupReadingQueueMembership.toReadingQueueMembership(): ReadingQueueMembership {
    val queued = if (queuedAt.isNotBlank()) {
        BackupValidator.parseInstant(queuedAt, "membership.queuedAt")
    } else {
        Instant.now()
    }
    return ReadingQueueMembership(
        id = BackupPaths.canonicalUuid(id, "membership.id"),
        queueID = BackupPaths.canonicalUuid(queueID, "membership.queueID"),
        workID = BackupPaths.canonicalUuid(workID, "membership.workID"),
        queuedAt = queued,
        lastModifiedAt = BackupValidator.parseNullableInstant(
            lastModifiedAt?.takeIf { it.isNotBlank() },
            "membership.lastModifiedAt"
        ) ?: queued,
        sortOrderInQueue = sortOrderInQueue,
        note = note
    )
}

fun ReadingAnnotation.toBackupAnnotation(): BackupAnnotation {
    return BackupAnnotation(
        id = BackupPaths.canonicalUuid(id, "annotation.id"),
        workID = BackupPaths.canonicalUuid(workID, "annotation.workID"),
        kindRaw = kindRaw,
        colorRaw = colorRaw,
        locatorString = locatorString,
        selectedText = selectedText,
        note = note,
        progression = progression,
        spineIndex = spineIndex,
        chapterTitle = chapterTitle,
        createdAt = BackupValidator.formatInstant(createdAt),
        lastModifiedAt = lastModifiedAt?.let(BackupValidator::formatInstant),
        deletedAt = deletedAt?.let(BackupValidator::formatInstant),
        isPendingDeletion = isPendingDeletion
    )
}

fun BackupAnnotation.toReadingAnnotation(): ReadingAnnotation {
    val created = if (createdAt.isNotBlank()) {
        BackupValidator.parseInstant(createdAt, "annotation.createdAt")
    } else {
        Instant.now()
    }
    return ReadingAnnotation(
        id = BackupPaths.canonicalUuid(id, "annotation.id"),
        workID = BackupPaths.canonicalUuid(workID, "annotation.workID"),
        kindRaw = kindRaw.ifBlank { "bookmark" },
        colorRaw = colorRaw,
        locatorString = locatorString,
        selectedText = selectedText,
        note = note,
        progression = progression,
        spineIndex = spineIndex,
        chapterTitle = chapterTitle,
        createdAt = created,
        lastModifiedAt = BackupValidator.parseNullableInstant(
            lastModifiedAt?.takeIf { it.isNotBlank() },
            "annotation.lastModifiedAt"
        ) ?: created,
        deletedAt = BackupValidator.parseNullableInstant(
            deletedAt?.takeIf { it.isNotBlank() },
            "annotation.deletedAt"
        ),
        isPendingDeletion = isPendingDeletion
    )
}

fun SyncTombstone.toBackupTombstone(): BackupTombstone {
    return BackupTombstone(
        id = BackupPaths.canonicalUuid(id, "tombstone.id"),
        recordID = BackupPaths.canonicalUuid(
            membershipRecordIdForExport(recordID, recordTypeRaw),
            "tombstone.recordID"
        ),
        recordTypeRaw = recordTypeRaw,
        createdAt = BackupValidator.formatInstant(createdAt),
        lastModifiedAt = BackupValidator.formatInstant(lastModifiedAt),
        sourceURL = sourceURL,
        ao3WorkID = ao3WorkID,
        deletedOnDeviceID = deletedOnDeviceID,
        deletionReason = deletionReason,
        signerPublicKey = signerPublicKey,
        signature = signature
    )
}

fun BackupTombstone.toSyncTombstone(): SyncTombstone {
    val created = if (createdAt.isNotBlank()) {
        BackupValidator.parseInstant(createdAt, "tombstone.createdAt")
    } else {
        Instant.now()
    }
    val modified = if (lastModifiedAt.isNotBlank()) {
        BackupValidator.parseInstant(lastModifiedAt, "tombstone.lastModifiedAt")
    } else {
        created
    }
    val type = recordTypeRaw.ifBlank { "savedWork" }
    return SyncTombstone(
        id = BackupPaths.canonicalUuid(id, "tombstone.id"),
        recordID = BackupPaths.canonicalUuid(
            membershipRecordIdForExport(recordID, type),
            "tombstone.recordID"
        ),
        recordTypeRaw = type,
        createdAt = created,
        lastModifiedAt = modified,
        sourceURL = sourceURL,
        ao3WorkID = ao3WorkID,
        deletedOnDeviceID = deletedOnDeviceID,
        deletionReason = deletionReason,
        signerPublicKey = signerPublicKey,
        signature = signature
    )
}

/**
 * Membership tombstones may still be the android-v0.2.1-alpha colon form on
 * disk; rewrite to the XOR-UUID form before [BackupPaths.canonicalUuid] so
 * export/import does not throw [BackupError.InvalidUuid].
 */
private fun membershipRecordIdForExport(recordId: String, recordTypeRaw: String): String {
    if (recordTypeRaw != SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP) {
        return recordId
    }
    return try {
        canonicalizeCollectionMembershipRecordId(recordId)
    } catch (_: IllegalArgumentException) {
        recordId
    }
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
