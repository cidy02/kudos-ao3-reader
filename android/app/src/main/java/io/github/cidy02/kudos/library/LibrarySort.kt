package io.github.cidy02.kudos.library

/**
 * The Library's sorts, the same on iOS (`LibrarySort` in LibraryFilters.swift). `Natural` keeps
 * each section's own order (Reading Now and History most recently read first); the main list's own
 * order is date added, newest first, as iOS's `@Query` sorts it. Last Read and Kudos are the
 * owner's additions (2026-10-03), on both apps.
 */
enum class LibrarySort(val label: String) {
    Natural("Default"),
    RecentlyAdded("Date Added"),
    DateDownloaded("Date Downloaded"),
    LastRead("Last Read"),
    Title("Title"),
    Author("Author"),
    WordCount("Word Count"),
    Kudos("Kudos")
}
