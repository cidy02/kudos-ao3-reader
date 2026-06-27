package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.library.LibraryFilterState
import io.github.cidy02.kudos.library.LibraryQuery
import io.github.cidy02.kudos.library.LibrarySnapshot
import io.github.cidy02.kudos.library.LibrarySort

data class HomeDashboardState(
    val loading: Boolean = true,
    val totalSaved: Int = 0,
    val hiddenByPrivacyCount: Int = 0,
    val continueReading: List<LibraryDisplayItem> = emptyList(),
    val favorites: List<LibraryDisplayItem> = emptyList(),
    val recentlyOpened: List<LibraryDisplayItem> = emptyList(),
    val recentlyAdded: List<LibraryDisplayItem> = emptyList()
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
        return HomeDashboardState(
            loading = false,
            totalSaved = library.totalSaved,
            hiddenByPrivacyCount = library.hiddenByPrivacyCount,
            continueReading = library.continueReading,
            favorites = library.favorites,
            recentlyOpened = library.readingHistory,
            recentlyAdded = library.recentlyAdded
        )
    }
}
