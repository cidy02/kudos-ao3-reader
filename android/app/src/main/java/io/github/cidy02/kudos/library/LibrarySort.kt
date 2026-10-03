package io.github.cidy02.kudos.library

/**
 * The Library's sorts, exactly iOS's `LibrarySort` (LibraryFilters.swift): `Natural` keeps each
 * section's own order (Reading Now and History most recently read first); the main list's own
 * order is date added, newest first, as iOS's `@Query` sorts it.
 */
enum class LibrarySort(val label: String) {
    Natural("Default"),
    RecentlyAdded("Date Added"),
    DateDownloaded("Date Downloaded"),
    Title("Title"),
    Author("Author"),
    WordCount("Word Count")
}
