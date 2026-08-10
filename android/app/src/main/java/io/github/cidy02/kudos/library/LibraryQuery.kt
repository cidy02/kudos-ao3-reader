package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant

object LibraryQuery {
    fun buildState(
        snapshot: LibrarySnapshot,
        searchQuery: String,
        filters: LibraryFilterState,
        sort: LibrarySort,
        reveal: PrivacyRevealState = PrivacyRevealState()
    ): LibraryUiState {
        // A queue-only work (isQueueOnlyWork) is intentionally not on the main saved
        // shelves - it's excluded upstream too (WorkRepository.observeSavedWorks()
        // filters on isSaved), but LibraryQuery is a general-purpose, reusable
        // computation over whatever LibrarySnapshot it's given, so it shouldn't rely
        // on an undocumented precondition about the caller's pre-filtering. Enforcing
        // it here, alongside the other "what's visible on Library shelves" rules
        // (privacy, mature content) already computed in this function, is where a
        // reader would expect to find it.
        val savedItems = snapshot.items.filter { !it.work.isQueueOnlyWork }
        val visible = savedItems.mapNotNull { item ->
            when (
                val visibility = LibraryPrivacy.visibility(item.work, snapshot.privacy, reveal)
            ) {
                LibraryPrivacyVisibility.Hidden -> null
                LibraryPrivacyVisibility.Visible,
                LibraryPrivacyVisibility.Obscured -> LibraryDisplayItem(item, visibility)
            }
        }
        val hiddenCount = savedItems.size - visible.size
        val filtered = apply(visible, searchQuery, filters, sort)
        // Fandom chips / facet filters narrow every shelf (Apple LibraryView).
        val shelfSource = filterOnly(visible, searchQuery, filters)
        val matureCount = savedItems.count { isMatureWork(it.work) }
        return LibraryUiState(
            loading = false,
            searchQuery = searchQuery,
            filters = filters,
            sort = sort,
            totalSaved = savedItems.size,
            hiddenByPrivacyCount = hiddenCount,
            items = filtered,
            continueReading = continueReading(shelfSource),
            readingHistory = readingHistory(shelfSource),
            recentlyAdded = sortDisplayItems(shelfSource, LibrarySort.RecentlyAdded),
            favorites = sortDisplayItems(
                shelfSource.filter { it.item.work.isFavorite },
                LibrarySort.LastRead
            ),
            savedForLater = savedForLater(shelfSource),
            finished = finished(shelfSource),
            downloaded = downloaded(shelfSource),
            topFandoms = topFandoms(visible),
            userTags = snapshot.userTags.sortedBy { it.normalizedName.lowercase() },
            collections = snapshot.collections.sortedWith(
                compareBy(String.CASE_INSENSITIVE_ORDER) { it.name }
            ),
            hideMatureContent = snapshot.privacy.hideMatureContent,
            matureWorkCount = matureCount,
            confirmBeforeDelete = snapshot.confirmBeforeDelete
        )
    }

    /** Most frequent fandoms among privacy-visible works (chip bar). */
    fun topFandoms(items: List<LibraryDisplayItem>, limit: Int = 10): List<String> {
        val counts = linkedMapOf<String, Int>()
        for (display in items) {
            for (raw in display.item.work.workFandoms) {
                val name = raw.trim()
                if (name.isEmpty()) continue
                counts[name] = (counts[name] ?: 0) + 1
            }
        }
        return counts.entries
            .sortedWith(
                compareByDescending<Map.Entry<String, Int>> { it.value }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.key }
            )
            .take(limit)
            .map { it.key }
    }

    /** Filter + search without reordering (section builders apply their own sort). */
    fun filterOnly(
        items: List<LibraryDisplayItem>,
        searchQuery: String = "",
        filters: LibraryFilterState = LibraryFilterState()
    ): List<LibraryDisplayItem> {
        val query = searchQuery.trim()
        return items.filter { display ->
            matchesFilters(display.item, filters) && matchesSearch(display, query)
        }
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

    /** Apple `LibrarySectionKind.savedForLater`: explicitly saved works. */
    fun savedForLater(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter { it.item.work.isSaved }
            .sortedWith(recencyComparator())
    }

    /** Apple `LibrarySectionKind.finished`. */
    fun finished(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter { it.item.work.isFinished }
            .sortedWith(lastReadComparator())
    }

    /** Apple `LibrarySectionKind.downloaded`: EPUB on disk. */
    fun downloaded(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter { it.item.work.hasEpub }
            .sortedWith(
                compareByDescending<LibraryDisplayItem> { it.item.work.dateAdded }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
            )
    }

    fun readingHistory(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter { it.item.work.lastReadDate != null }
            .sortedWith(lastReadComparator())
    }

    private fun isMatureWork(work: SavedWork): Boolean {
        val rating = work.rating.lowercase()
        return rating.contains("explicit") ||
            rating.contains("mature") ||
            rating == "e" ||
            rating == "m"
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
            LibrarySort.Manual -> items
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
        val terms = io.github.cidy02.kudos.works.WorkSearchIndex.terms(query)
        val userTags = display.item.userTags.map { it.normalizedName }
        // Collection membership names aren't on SavedWork; keep them as match extras
        // so "weekend" still finds works in the Weekend collection.
        val collections = display.item.collections.map { it.name }
        return io.github.cidy02.kudos.works.WorkSearchIndex.matches(
            work = display.item.work,
            terms = terms,
            userTags = userTags,
            extraTerms = collections
        )
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
