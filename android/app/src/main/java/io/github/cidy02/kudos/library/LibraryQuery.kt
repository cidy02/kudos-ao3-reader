package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant

object LibraryQuery {
    fun buildState(
        snapshot: LibrarySnapshot,
        searchQuery: String,
        filters: LibraryFilterState,
        sort: LibrarySort
    ): LibraryUiState {
        val visible = snapshot.items.mapNotNull { item ->
            when (val visibility = LibraryPrivacy.visibility(item.work, snapshot.privacy)) {
                LibraryPrivacyVisibility.Hidden -> null
                LibraryPrivacyVisibility.Visible,
                LibraryPrivacyVisibility.Obscured -> LibraryDisplayItem(item, visibility)
            }
        }
        val hiddenCount = snapshot.items.size - visible.size
        val filtered = apply(visible, searchQuery, filters, sort)
        return LibraryUiState(
            loading = false,
            searchQuery = searchQuery,
            filters = filters,
            sort = sort,
            totalSaved = snapshot.items.size,
            hiddenByPrivacyCount = hiddenCount,
            items = filtered,
            continueReading = continueReading(visible),
            readingHistory = readingHistory(visible),
            recentlyAdded = sortDisplayItems(visible, LibrarySort.RecentlyAdded),
            favorites = sortDisplayItems(
                visible.filter { it.item.work.isFavorite },
                LibrarySort.LastRead
            ),
            userTags = snapshot.userTags.sortedBy { it.normalizedName.lowercase() },
            collections = snapshot.collections.sortedWith(
                compareBy(String.CASE_INSENSITIVE_ORDER) { it.name }
            )
        )
    }

    fun apply(
        items: List<LibraryDisplayItem>,
        searchQuery: String = "",
        filters: LibraryFilterState = LibraryFilterState(),
        sort: LibrarySort = LibrarySort.RecentlyAdded
    ): List<LibraryDisplayItem> {
        val query = searchQuery.trim()
        return sortDisplayItems(
            items.filter { display ->
                matchesFilters(display.item, filters) && matchesSearch(display, query)
            },
            sort
        )
    }

    fun continueReading(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter { it.item.work.isInProgress }
            .sortedWith(recencyComparator())
    }

    fun readingHistory(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter { it.item.work.lastReadDate != null }
            .sortedWith(lastReadComparator())
    }

    fun sortDisplayItems(
        items: List<LibraryDisplayItem>,
        sort: LibrarySort
    ): List<LibraryDisplayItem> {
        return when (sort) {
            LibrarySort.RecentlyAdded -> items.sortedWith(
                compareByDescending<LibraryDisplayItem> { it.item.work.dateAdded }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
                    .thenBy { it.item.work.id }
            )
            LibrarySort.LastRead -> items.sortedWith(lastReadComparator())
            LibrarySort.Title -> items.sortedWith(
                compareBy<LibraryDisplayItem, String>(String.CASE_INSENSITIVE_ORDER) {
                    it.item.work.title
                }.thenBy { it.item.work.id }
            )
            LibrarySort.Author -> items.sortedWith(
                compareBy<LibraryDisplayItem, String>(String.CASE_INSENSITIVE_ORDER) {
                    it.item.work.author
                }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
                    .thenBy { it.item.work.id }
            )
            LibrarySort.WordCount -> items.sortedWith(
                compareByDescending<LibraryDisplayItem> { it.item.work.wordCount }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
                    .thenBy { it.item.work.id }
            )
            LibrarySort.Kudos -> items.sortedWith(
                compareByDescending<LibraryDisplayItem> { it.item.work.kudos }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
                    .thenBy { it.item.work.id }
            )
        }
    }

    private fun matchesFilters(item: LibraryWorkListItem, filters: LibraryFilterState): Boolean {
        val work = item.work
        if (filters.favoriteOnly && !work.isFavorite) return false
        when (filters.finished) {
            LibraryFinishedFilter.Any -> Unit
            LibraryFinishedFilter.Finished -> if (!work.isFinished) return false
            LibraryFinishedFilter.Unfinished -> if (work.isFinished) return false
        }
        when (filters.download) {
            LibraryDownloadFilter.Any -> Unit
            LibraryDownloadFilter.Downloaded -> if (!work.hasEpub) return false
            LibraryDownloadFilter.NotDownloaded -> if (work.hasEpub) return false
        }
        when (filters.completion) {
            LibraryCompletionFilter.Any -> Unit
            LibraryCompletionFilter.Complete -> if (!work.isComplete) return false
            LibraryCompletionFilter.InProgress -> if (work.isComplete) return false
        }
        if (!containsAllIds(item.userTags.map { it.id }, filters.userTagIds)) return false
        if (!containsAllIds(item.collections.map { it.id }, filters.collectionIds)) return false
        if (!matchesTextSet(listOf(work.rating), filters.ratings)) return false
        if (!matchesTextSet(tagSource(work.workWarnings, work.workTags), filters.warnings)) return false
        if (!matchesTextSet(tagSource(work.workCategories, work.workTags), filters.categories)) return false
        if (!matchesTextSet(tagSource(work.workFandoms, work.workTags), filters.fandoms)) return false
        if (!matchesTextSet(tagSource(work.workRelationships, work.workTags), filters.relationships)) return false
        if (!matchesTextSet(tagSource(work.workCharacters, work.workTags), filters.characters)) return false
        if (!matchesTextSet(tagSource(work.workFreeforms, work.workTags), filters.freeforms)) return false
        return true
    }

    private fun matchesSearch(display: LibraryDisplayItem, query: String): Boolean {
        if (query.isBlank()) return true
        if (display.privacyVisibility == LibraryPrivacyVisibility.Obscured) return false
        val needle = query.lowercase()
        return searchableText(display.item).any { it.lowercase().contains(needle) }
    }

    private fun searchableText(item: LibraryWorkListItem): List<String> {
        val work = item.work
        return buildList {
            add(work.title)
            add(work.author)
            add(work.summary)
            add(work.rating)
            add(work.language)
            add(work.chapters)
            add(work.seriesTitle)
            addAll(work.workFandoms)
            addAll(work.workRelationships)
            addAll(work.workCharacters)
            addAll(work.workFreeforms)
            addAll(work.workWarnings)
            addAll(work.workCategories)
            addAll(work.workTags)
            addAll(item.userTags.map { it.normalizedName })
            addAll(item.collections.map { it.name })
        }
    }

    private fun containsAllIds(actual: List<String>, required: Set<String>): Boolean {
        if (required.isEmpty()) return true
        return actual.toSet().containsAll(required)
    }

    private fun matchesTextSet(actual: List<String>, required: Set<String>): Boolean {
        if (required.isEmpty()) return true
        val normalizedActual = actual.map { it.trim().lowercase() }.toSet()
        return required.all { it.trim().lowercase() in normalizedActual }
    }

    private fun tagSource(categorized: List<String>, fallback: List<String>): List<String> {
        return categorized.ifEmpty { fallback }
    }

    private fun recencyComparator(): Comparator<LibraryDisplayItem> {
        return compareByDescending<LibraryDisplayItem> {
            it.item.work.lastReadDate ?: it.item.work.dateAdded
        }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
            .thenBy { it.item.work.id }
    }

    private fun lastReadComparator(): Comparator<LibraryDisplayItem> {
        return compareByDescending<LibraryDisplayItem> {
            it.item.work.lastReadDate ?: Instant.MIN
        }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
            .thenBy { it.item.work.id }
    }
}

fun SavedWork.readingProgressFraction(): Double? {
    val posted = chapters.substringBefore('/').trim().toIntOrNull()
    val total = chapters.substringAfter('/', missingDelimiterValue = "").trim().toIntOrNull()
    if (posted != null && total != null && total > 1 && lastSpineIndex >= 0) {
        return ((lastSpineIndex + 1).toDouble() / total.toDouble()).coerceIn(0.0, 1.0)
    }
    if (lastScrollFraction > 0.0) return lastScrollFraction.coerceIn(0.0, 1.0)
    return null
}
