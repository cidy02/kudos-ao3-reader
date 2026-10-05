package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.browse.FandomDisplayName
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.readingProgress
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import io.github.cidy02.kudos.search.filterWordBound
import io.github.cidy02.kudos.search.matchesFacetText
import io.github.cidy02.kudos.search.matchesRatingText
import io.github.cidy02.kudos.search.matchesWarningText
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
        val visible = snapshot.items.mapNotNull { item ->
            when (
                val visibility = LibraryPrivacy.visibility(item.work, snapshot.privacy, reveal)
            ) {
                LibraryPrivacyVisibility.Hidden -> null
                LibraryPrivacyVisibility.Visible,
                LibraryPrivacyVisibility.Obscured -> LibraryDisplayItem(item, visibility)
            }
        }
        val visibleSaved = visible.filter { !it.item.work.isQueueOnlyWork }
        val savedItems = snapshot.items.filter { !it.work.isQueueOnlyWork }
        val hiddenCount = savedItems.size - visibleSaved.size
        val filtered = apply(visibleSaved, searchQuery, filters, sort)
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
            collectionMembers = visible,
            continueReading = continueReading(shelfSource),
            readingHistory = readingHistory(shelfSource),
            recentlyAdded = sortDisplayItems(
                filterOnly(visibleSaved, searchQuery, filters),
                LibrarySort.RecentlyAdded
            ),
            favorites = sortDisplayItems(
                shelfSource.filter { it.item.work.isFavorite },
                LibrarySort.RecentlyAdded
            ),
            savedForLater = savedForLater(shelfSource),
            finished = finished(shelfSource),
            downloaded = downloaded(shelfSource),
            topFandoms = topFandoms(visibleSaved),
            userTags = snapshot.userTags.sortedBy { it.normalizedName.lowercase() },
            // Newest first, matching iOS's
            // `@Query(sort: \WorkCollection.dateAdded, order: .reverse)`. Sorting
            // alphabetically here meant a collection you just made was buried
            // mid-list on Android and sat at the top on iOS. Name breaks ties so
            // the order stays stable for same-instant imports.
            collections = snapshot.collections.sortedWith(
                compareByDescending<WorkCollection> { it.dateAdded }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.name }
            ),
            hideMatureContent = snapshot.privacy.hideMatureContent,
            matureWorkCount = matureCount,
            confirmBeforeDelete = snapshot.confirmBeforeDelete,
            showsZeroStats = snapshot.showsZeroStats
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
        sort: LibrarySort = LibrarySort.Natural
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
            .filter { it.item.work.isInProgress && !it.item.work.isQueueOnlyWork }
            .sortedWith(recencyComparator())
    }

    /**
     * Apple `LibrarySectionKind.savedForLater`: native Saved for Later queue members
     * (including queue-only) plus legacy isSaved works that predate queues and
     * aren't already queued.
     */
    fun savedForLater(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter {
                val item = it.item
                item.inSavedForLater || (item.work.isSaved && !item.work.isQueuedForLater)
            }
            .sortedWith(recencyComparator())
    }

    /**
     * Apple `LibrarySectionKind.finished`: `readingState == .finished && !isQueueOnlyWork`
     * (LibrarySectionKind.swift:127-129). A finished work held only by a queue lives
     * on that queue, not on this shelf.
     */
    fun finished(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter { it.item.work.isFinished && !it.item.work.isQueueOnlyWork }
            .sortedWith(lastReadComparator())
    }

    /** Apple `LibrarySectionKind.downloaded`: a copy on-device the reader chose to keep. */
    fun downloaded(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter { it.item.work.isDownloaded && !it.item.work.isQueueOnlyWork }
            .sortedWith(
                compareByDescending<LibraryDisplayItem> { it.item.work.dateAdded }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
            )
    }

    fun readingHistory(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter {
                val work = it.item.work
                (work.hasStartedReading || work.isFinished) && work.hiddenFromHistoryAt == null
            }
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
            LibrarySort.Natural, LibrarySort.RecentlyAdded -> items.sortedWith(
                compareByDescending<LibraryDisplayItem> { it.item.work.dateAdded }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
                    .thenBy { it.item.work.id }
            )
            LibrarySort.DateDownloaded -> items.sortedWith(
                compareByDescending<LibraryDisplayItem> {
                    it.item.work.downloadedAt ?: it.item.work.dateAdded
                }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
                    .thenBy { it.item.work.id }
            )
            // Most recently read first; never-read works last (iOS: nil dates last).
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
            LibraryDownloadFilter.Downloaded -> if (!work.isDownloaded) return false
            LibraryDownloadFilter.NotDownloaded -> if (work.isDownloaded) return false
        }
        when (filters.completion) {
            LibraryCompletionFilter.Any -> Unit
            LibraryCompletionFilter.Complete -> if (!work.isComplete) return false
            LibraryCompletionFilter.InProgress -> if (work.isComplete) return false
        }
        if (!containsAllIds(item.userTags.map { it.id }, filters.userTagIds)) return false
        if (!containsAllIds(item.collections.map { it.id }, filters.collectionIds)) return false
        if (!matchesTextSet(listOf(work.rating), filters.ratings)) return false
        if (!filters.rating.matchesRatingText(work.rating)) return false
        val warnings = tagSource(work.workWarnings, work.workTags)
        if (!filters.warnings.all { title ->
                val warning = AO3Warning.entries.firstOrNull { it.title.equals(title, ignoreCase = true) }
                warning?.matchesWarningText(warnings) ?: matchesFacetText(warnings, title)
            }) return false
        if (!filters.categories.all { matchesFacetText(tagSource(work.workCategories, work.workTags), it) }) return false
        // iOS compares fandom families, and other tag categories as exact set members.
        if (filters.fandoms.isNotEmpty()) {
            val fandoms = tagSource(work.workFandoms, work.workTags).map { FandomDisplayName.bareTitle(it) }.toSet()
            if (!filters.fandoms.all { FandomDisplayName.bareTitle(it) in fandoms }) return false
        }
        if (!tagSource(work.workRelationships, work.workTags).containsAll(filters.relationships)) return false
        if (!tagSource(work.workCharacters, work.workTags).containsAll(filters.characters)) return false
        if (!tagSource(work.workFreeforms, work.workTags).containsAll(filters.freeforms)) return false
        if (filters.excludeTags.any { it in work.workTags }) return false
        if (filters.language.isNotEmpty() && !matchesFacetText(listOf(work.language), filters.language)) return false
        // A local count <= 0 is unknown. Bounds must never hide an unrefreshed work.
        if (work.wordCount > 0) {
            val from = filterWordBound(filters.wordsFrom)
            val to = filterWordBound(filters.wordsTo)
            if (from != null && work.wordCount < from) return false
            if (to != null && work.wordCount > to) return false
        }
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

/** Rings and "42%" labels. iOS `SavedWork.readingProgress`, via [readingProgress]. */
fun SavedWork.readingProgressFraction(): Double? = readingProgress
