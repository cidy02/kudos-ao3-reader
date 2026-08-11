package io.github.cidy02.kudos.library

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
    val freeforms: Set<String> = emptySet()
) {
    val hasActiveFilters: Boolean
        get() = favoriteOnly ||
            finished != LibraryFinishedFilter.Any ||
            download != LibraryDownloadFilter.Any ||
            completion != LibraryCompletionFilter.Any ||
            userTagIds.isNotEmpty() ||
            collectionIds.isNotEmpty() ||
            ratings.isNotEmpty() ||
            warnings.isNotEmpty() ||
            categories.isNotEmpty() ||
            fandoms.isNotEmpty() ||
            relationships.isNotEmpty() ||
            characters.isNotEmpty() ||
            freeforms.isNotEmpty()
}
