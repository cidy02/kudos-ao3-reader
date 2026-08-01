package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.library.LibraryFilterState
import io.github.cidy02.kudos.library.LibraryQuery
import io.github.cidy02.kudos.library.LibrarySnapshot
import io.github.cidy02.kudos.library.LibrarySort
import java.time.Instant

data class HomeDashboardState(
    val loading: Boolean = true,
    val totalSaved: Int = 0,
    val hiddenByPrivacyCount: Int = 0,
    val continueReading: List<LibraryDisplayItem> = emptyList(),
    val recentlyUpdated: List<LibraryDisplayItem> = emptyList(),
    val favorites: List<LibraryDisplayItem> = emptyList(),
    val recentlyOpened: List<LibraryDisplayItem> = emptyList()
) {
    val hasSavedWorks: Boolean
        get() = totalSaved > 0
}

object HomeDashboard {
    fun buildState(snapshot: LibrarySnapshot): HomeDashboardState {
        val library = LibraryQuery.buildState(
            snapshot = snapshot,
            searchQuery = "",
            filters = LibraryFilterState(),
            sort = LibrarySort.RecentlyAdded
        )
        // Empty search + filters → `items` is the full privacy-visible set.
        return HomeDashboardState(
            loading = false,
            totalSaved = library.totalSaved,
            hiddenByPrivacyCount = library.hiddenByPrivacyCount,
            continueReading = library.continueReading,
            recentlyUpdated = recentlyUpdated(library.items),
            favorites = library.favorites,
            recentlyOpened = library.readingHistory
        )
    }

    /**
     * Works AO3 has added chapters to since the user last saw them.
     * Sorted by [io.github.cidy02.kudos.core.model.SavedWork.lastUpdateCheck] desc.
     * Apple `HomeSectionKind.recentlyUpdated` parity.
     */
    fun recentlyUpdated(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> {
        return items
            .filter { it.item.work.hasUpdate }
            .sortedWith(
                compareByDescending<LibraryDisplayItem> {
                    it.item.work.lastUpdateCheck ?: Instant.EPOCH
                }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.item.work.title }
                    .thenBy { it.item.work.id }
            )
    }
}
