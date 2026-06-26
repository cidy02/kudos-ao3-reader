package io.github.cidy02.kudos.data.local.entity

import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
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
        lastUpdateCheck = lastUpdateCheck
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
        lastUpdateCheck = lastUpdateCheck
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
        description = description,
        sortOrder = sortOrder
    )
}

fun CollectionEntity.toDomain(workIds: List<String> = emptyList()): WorkCollection {
    return WorkCollection(
        id = id,
        name = name,
        dateAdded = dateAdded,
        workIds = workIds,
        description = description,
        sortOrder = sortOrder
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
