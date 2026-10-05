package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.network.ao3.search.AO3Rating

enum class LibraryFinishedFilter { Any, Finished, Unfinished }

enum class LibraryDownloadFilter { Any, Downloaded, NotDownloaded }

enum class LibraryCompletionFilter { Any, Complete, InProgress }

data class LibraryFilterState(
    val favoriteOnly: Boolean = false,
    val finished: LibraryFinishedFilter = LibraryFinishedFilter.Any,
    val download: LibraryDownloadFilter = LibraryDownloadFilter.Any,
    val completion: LibraryCompletionFilter = LibraryCompletionFilter.Any,
    val userTagIds: Set<String> = emptySet(),
    val collectionIds: Set<String> = emptySet(),
    val ratings: Set<String> = emptySet(),
    val warnings: Set<String> = emptySet(),
    val categories: Set<String> = emptySet(),
    val fandoms: Set<String> = emptySet(),
    val relationships: Set<String> = emptySet(),
    val characters: Set<String> = emptySet(),
    val freeforms: Set<String> = emptySet(),
    val rating: AO3Rating = AO3Rating.ANY,
    val language: String = "",
    val wordsFrom: String = "",
    val wordsTo: String = "",
    val excludeTags: Set<String> = emptySet()
) {
    val activeCount: Int
        get() = listOf(
            favoriteOnly,
            finished != LibraryFinishedFilter.Any,
            download != LibraryDownloadFilter.Any,
            completion != LibraryCompletionFilter.Any,
            rating != AO3Rating.ANY,
            language.isNotEmpty(),
            wordsFrom.isNotBlank() || wordsTo.isNotBlank()
        ).count { it } + userTagIds.size + collectionIds.size + ratings.size + warnings.size +
            categories.size + fandoms.size + relationships.size + characters.size + freeforms.size + excludeTags.size

    val hasActiveFilters: Boolean
        get() = activeCount > 0
}
