package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection

data class LibraryWorkListItem(
    val work: SavedWork,
    val userTags: List<Tag> = emptyList(),
    val collections: List<WorkCollection> = emptyList()
)

data class LibrarySnapshot(
    val items: List<LibraryWorkListItem>,
    val userTags: List<Tag>,
    val collections: List<WorkCollection>,
    val privacy: PrivacySettings
)

enum class LibraryPrivacyVisibility { Visible, Obscured, Hidden }

data class LibraryDisplayItem(
    val item: LibraryWorkListItem,
    val privacyVisibility: LibraryPrivacyVisibility = LibraryPrivacyVisibility.Visible
)

data class LibrarySection(
    val title: String,
    val items: List<LibraryDisplayItem>,
    val emptyMessage: String
)

data class LibraryUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val searchQuery: String = "",
    val filters: LibraryFilterState = LibraryFilterState(),
    val sort: LibrarySort = LibrarySort.RecentlyAdded,
    val totalSaved: Int = 0,
    val hiddenByPrivacyCount: Int = 0,
    val items: List<LibraryDisplayItem> = emptyList(),
    val continueReading: List<LibraryDisplayItem> = emptyList(),
    val readingHistory: List<LibraryDisplayItem> = emptyList(),
    val recentlyAdded: List<LibraryDisplayItem> = emptyList(),
    val favorites: List<LibraryDisplayItem> = emptyList(),
    val userTags: List<Tag> = emptyList(),
    val collections: List<WorkCollection> = emptyList()
) {
    val hasSavedWorks: Boolean
        get() = totalSaved > 0

    val hasActiveQueryOrFilters: Boolean
        get() = searchQuery.isNotBlank() || filters.hasActiveFilters
}
