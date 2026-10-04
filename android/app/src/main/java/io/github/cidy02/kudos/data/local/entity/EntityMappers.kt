package io.github.cidy02.kudos.data.local.entity

import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection

fun SavedWork.toEntity(): WorkEntity {
    return WorkEntity(
        id = id,
        title = title,
        author = author,
        summary = summary,
        sourceUrl = sourceUrl,
        dateAdded = dateAdded,
        downloadedAt = downloadedAt,
        createdAt = createdAt,
        isFavorite = isFavorite,
        hasGivenKudos = hasGivenKudos,
        isSaved = isSaved,
        isFinished = isFinished,
        hasEpub = hasEpub,
        remoteEpubPending = remoteEpubPending,
        isComplete = isComplete,
        rating = rating,
        language = language,
        wordCount = wordCount,
        chapters = chapters,
        kudos = kudos,
        seriesTitle = seriesTitle,
        seriesPosition = seriesPosition,
        seriesUrl = seriesUrl,
        lastSpineIndex = lastSpineIndex,
        lastScrollFraction = lastScrollFraction,
        lastReadDate = lastReadDate,
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
        lastUpdateCheck = lastUpdateCheck,
        lastModifiedAt = lastModifiedAt,
        progressModifiedAt = progressModifiedAt,
        ao3Unavailable = ao3Unavailable,
        lastAvailabilityCheck = lastAvailabilityCheck,
        isDeleted = isDeleted,
        deletedAt = deletedAt,
        permanentDeletionScheduledAt = permanentDeletionScheduledAt,
        isQueuedForLater = isQueuedForLater,
        searchText = searchText,
        searchIndexVersion = searchIndexVersion,
        lastTagRefreshAttemptAt = lastTagRefreshAttemptAt,
        epubPreservationStatusRaw = epubPreservationStatusRaw,
        metadataSyncStatusRaw = metadataSyncStatusRaw,
        preservedAt = preservedAt,
        lastPreservationAttemptAt = lastPreservationAttemptAt,
        keepInProgressOverride = keepInProgressOverride,
        hiddenFromHistoryAt = hiddenFromHistoryAt,
        freedAt = freedAt,
        datePublished = datePublished,
        dateUpdated = dateUpdated,
        bookmarks = bookmarks,
        ao3SeriesID = ao3SeriesID,
        ao3WorkID = ao3WorkID,
        legacyReaderProgress = legacyReaderProgress,
        authorIdentitiesJSON = authorIdentitiesJSON,
        epubDigest = epubDigest,
        assetIdentifier = assetIdentifier
    )
}

fun WorkEntity.toDomain(): SavedWork {
    return SavedWork(
        id = id,
        title = title,
        author = author,
        summary = summary,
        sourceUrl = sourceUrl,
        dateAdded = dateAdded,
        downloadedAt = downloadedAt,
        createdAt = createdAt,
        isFavorite = isFavorite,
        hasGivenKudos = hasGivenKudos,
        isSaved = isSaved,
        isFinished = isFinished,
        hasEpub = hasEpub,
        remoteEpubPending = remoteEpubPending,
        isComplete = isComplete,
        rating = rating,
        language = language,
        wordCount = wordCount,
        chapters = chapters,
        kudos = kudos,
        seriesTitle = seriesTitle,
        seriesPosition = seriesPosition,
        seriesUrl = seriesUrl,
        lastSpineIndex = lastSpineIndex,
        lastScrollFraction = lastScrollFraction,
        lastReadDate = lastReadDate,
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
        lastUpdateCheck = lastUpdateCheck,
        lastModifiedAt = lastModifiedAt,
        progressModifiedAt = progressModifiedAt,
        ao3Unavailable = ao3Unavailable,
        lastAvailabilityCheck = lastAvailabilityCheck,
        isDeleted = isDeleted,
        deletedAt = deletedAt,
        permanentDeletionScheduledAt = permanentDeletionScheduledAt,
        isQueuedForLater = isQueuedForLater,
        searchText = searchText,
        searchIndexVersion = searchIndexVersion,
        lastTagRefreshAttemptAt = lastTagRefreshAttemptAt,
        epubPreservationStatusRaw = epubPreservationStatusRaw,
        metadataSyncStatusRaw = metadataSyncStatusRaw,
        preservedAt = preservedAt,
        lastPreservationAttemptAt = lastPreservationAttemptAt,
        keepInProgressOverride = keepInProgressOverride,
        hiddenFromHistoryAt = hiddenFromHistoryAt,
        freedAt = freedAt,
        datePublished = datePublished,
        dateUpdated = dateUpdated,
        bookmarks = bookmarks,
        ao3SeriesID = ao3SeriesID,
        ao3WorkID = ao3WorkID,
        legacyReaderProgress = legacyReaderProgress,
        authorIdentitiesJSON = authorIdentitiesJSON,
        epubDigest = epubDigest,
        assetIdentifier = assetIdentifier
    )
}

fun Tag.toEntity(): TagEntity = TagEntity(id = id, name = normalizedName, dateCreated = dateCreated)

fun TagEntity.toDomain(): Tag = Tag(id = id, name = name, dateCreated = dateCreated)

fun Bookmark.toEntity(): BookmarkEntity {
    return BookmarkEntity(id = id, title = title, urlString = urlString, dateAdded = dateAdded)
}

fun BookmarkEntity.toDomain(): Bookmark {
    return Bookmark(id = id, title = title, urlString = urlString, dateAdded = dateAdded)
}

fun WorkCollection.toEntity(): CollectionEntity {
    return CollectionEntity(
        id = id,
        name = name,
        dateAdded = dateAdded,
        createdAt = createdAt,
        description = description,
        sortOrder = sortOrder,
        lastModifiedAt = lastModifiedAt,
        syncStatusRaw = syncStatusRaw,
        isDeleted = isDeleted,
        deletedAt = deletedAt,
        permanentDeletionScheduledAt = permanentDeletionScheduledAt,
        hue = hue,
        colorHex = colorHex,
        keepsWorksOffline = keepsWorksOffline,
        showsOnHome = showsOnHome,
        workOrderRaw = workOrderRaw,
        lastMembershipChangedAt = lastMembershipChangedAt
    )
}

fun CollectionEntity.toDomain(workIds: List<String> = emptyList()): WorkCollection {
    return WorkCollection(
        id = id,
        name = name,
        dateAdded = dateAdded,
        createdAt = createdAt,
        workIds = workIds,
        description = description,
        sortOrder = sortOrder,
        lastModifiedAt = lastModifiedAt,
        syncStatusRaw = syncStatusRaw,
        isDeleted = isDeleted,
        deletedAt = deletedAt,
        permanentDeletionScheduledAt = permanentDeletionScheduledAt,
        hue = hue,
        colorHex = colorHex,
        keepsWorksOffline = keepsWorksOffline,
        showsOnHome = showsOnHome,
        workOrderRaw = workOrderRaw,
        lastMembershipChangedAt = lastMembershipChangedAt
    )
}

fun CustomFont.toEntity(): CustomFontEntity {
    return CustomFontEntity(id = id, name = name, fileName = fileName, dateAdded = dateAdded)
}

fun CustomFontEntity.toDomain(): CustomFont {
    return CustomFont(id = id, name = name, fileName = fileName, dateAdded = dateAdded)
}

fun SavedSearch.toEntity(): SavedSearchEntity {
    return SavedSearchEntity(id = id, name = name, dateAdded = dateAdded, filtersJson = filtersJson)
}

fun SavedSearchEntity.toDomain(): SavedSearch {
    return SavedSearch(id = id, name = name, dateAdded = dateAdded, filtersJson = filtersJson)
}

fun SyncTombstone.toEntity(): SyncTombstoneEntity {
    return SyncTombstoneEntity(
        id = id,
        recordID = recordID,
        recordTypeRaw = recordTypeRaw,
        createdAt = createdAt,
        lastModifiedAt = lastModifiedAt,
        sourceURL = sourceURL,
        ao3WorkID = ao3WorkID,
        deletedOnDeviceID = deletedOnDeviceID,
        deletionReason = deletionReason,
        signerPublicKey = signerPublicKey,
        signature = signature
    )
}

fun SyncTombstoneEntity.toDomain(): SyncTombstone {
    return SyncTombstone(
        id = id,
        recordID = recordID,
        recordTypeRaw = recordTypeRaw,
        createdAt = createdAt,
        lastModifiedAt = lastModifiedAt,
        sourceURL = sourceURL,
        ao3WorkID = ao3WorkID,
        deletedOnDeviceID = deletedOnDeviceID,
        deletionReason = deletionReason,
        signerPublicKey = signerPublicKey,
        signature = signature
    )
}

fun ReadingQueue.toEntity(): ReadingQueueEntity {
    return ReadingQueueEntity(
        id = id,
        name = name,
        kindRaw = kindRaw,
        sortOrder = sortOrder,
        dateCreated = dateCreated,
        dateUpdated = dateUpdated,
        lastMembershipChangedAt = lastMembershipChangedAt,
        deletedAt = deletedAt,
        isDeleted = isDeleted,
        permanentDeletionScheduledAt = permanentDeletionScheduledAt,
        hue = hue,
        colorHex = colorHex,
        isPinned = isPinned,
        keepsWorksOffline = keepsWorksOffline,
        notes = notes
    )
}

fun ReadingQueueEntity.toDomain(): ReadingQueue {
    return ReadingQueue(
        id = id,
        name = name,
        kindRaw = kindRaw,
        sortOrder = sortOrder,
        dateCreated = dateCreated,
        dateUpdated = dateUpdated,
        lastMembershipChangedAt = lastMembershipChangedAt,
        deletedAt = deletedAt,
        isDeleted = isDeleted,
        permanentDeletionScheduledAt = permanentDeletionScheduledAt,
        hue = hue,
        colorHex = colorHex,
        isPinned = isPinned,
        keepsWorksOffline = keepsWorksOffline,
        notes = notes
    )
}

fun ReadingQueueMembership.toEntity(): ReadingQueueMembershipEntity {
    return ReadingQueueMembershipEntity(
        id = id,
        queueID = queueID,
        workID = workID,
        queuedAt = queuedAt,
        lastModifiedAt = lastModifiedAt,
        sortOrderInQueue = sortOrderInQueue,
        note = note
    )
}

fun ReadingQueueMembershipEntity.toDomain(): ReadingQueueMembership {
    return ReadingQueueMembership(
        id = id,
        queueID = queueID,
        workID = workID,
        queuedAt = queuedAt,
        lastModifiedAt = lastModifiedAt,
        sortOrderInQueue = sortOrderInQueue,
        note = note
    )
}

fun ReadingAnnotation.toEntity(): AnnotationEntity {
    return AnnotationEntity(
        id = id,
        workID = workID,
        kindRaw = kindRaw,
        colorRaw = colorRaw,
        locatorString = locatorString,
        selectedText = selectedText,
        note = note,
        progression = progression,
        spineIndex = spineIndex,
        chapterTitle = chapterTitle,
        createdAt = createdAt,
        lastModifiedAt = lastModifiedAt,
        deletedAt = deletedAt,
        isPendingDeletion = isPendingDeletion
    )
}

fun AnnotationEntity.toDomain(): ReadingAnnotation {
    return ReadingAnnotation(
        id = id,
        workID = workID,
        kindRaw = kindRaw,
        colorRaw = colorRaw,
        locatorString = locatorString,
        selectedText = selectedText,
        note = note,
        progression = progression,
        spineIndex = spineIndex,
        chapterTitle = chapterTitle,
        createdAt = createdAt,
        lastModifiedAt = lastModifiedAt,
        deletedAt = deletedAt,
        isPendingDeletion = isPendingDeletion
    )
}
