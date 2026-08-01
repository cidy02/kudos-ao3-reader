package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.app.PrivacyRevealState
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

/**
 * Session reveal flips Obscured → Visible for a work [reveal] covers — shared by
 * every screen's ViewModel (Library, Home) that folds `PrivacyGate` state into its
 * own `LibraryQuery.buildState`-derived items, so the rule can't drift between them.
 */
fun LibraryDisplayItem.withReveal(reveal: PrivacyRevealState): LibraryDisplayItem {
    if (privacyVisibility != LibraryPrivacyVisibility.Obscured) return this
    if (!reveal.isRevealed(item.work.id)) return this
    return copy(privacyVisibility = LibraryPrivacyVisibility.Visible)
}

data class LibrarySection(
    val title: String,
    val items: List<LibraryDisplayItem>,
    val emptyMessage: String
)

/** Compact queue row for the Library dashboard shelf. */
data class LibraryQueuePreview(
    val id: String,
    val name: String,
    val workCount: Int
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
    /** iOS Library dashboard shelves (Reading Now / Saved for Later / Finished / Downloaded). */
    val savedForLater: List<LibraryDisplayItem> = emptyList(),
    val finished: List<LibraryDisplayItem> = emptyList(),
    val downloaded: List<LibraryDisplayItem> = emptyList(),
    /** Top fandom labels for the quick-filter chip bar (most frequent first). */
    val topFandoms: List<String> = emptyList(),
    val userTags: List<Tag> = emptyList(),
    val collections: List<WorkCollection> = emptyList(),
    /** Local reading queues for the Library “Reading Queues” shelf. */
    val readingQueues: List<LibraryQueuePreview> = emptyList(),
    /** True while multi-select is active (Select toolbar). */
    val selectionMode: Boolean = false,
    /** Selected work ids while [selectionMode] is true. */
    val selectedWorkIds: Set<String> = emptySet(),
    /** Session-only mature reveals (Tap to reveal). */
    val revealedWorkIds: Set<String> = emptySet(),
    /**
     * Persisted "Hide mature content" setting — what actually drives Obscure/Hide for
     * every item above (`LibraryQuery.buildState` reads it from `snapshot.privacy`).
     * NOT what the toolbar reveal icon reflects; see [revealAllActive] for that.
     */
    val hideMatureContent: Boolean = true,
    /**
     * `PrivacyGate.revealAll` — session-only, what the toolbar eye icon actually
     * reflects and what tapping it flips. Deliberately separate from
     * [hideMatureContent]: the persisted setting still defaults back on at next
     * launch even while this is true for the rest of the current session (Apple
     * `MatureRevealToggle` / `gate.revealAll`).
     */
    val revealAllActive: Boolean = false,
    val matureWorkCount: Int = 0
) {
    val hasSavedWorks: Boolean
        get() = totalSaved > 0

    val hasActiveQueryOrFilters: Boolean
        get() = searchQuery.isNotBlank() || filters.hasActiveFilters

    val selectedCount: Int
        get() = selectedWorkIds.size

    val hasSelection: Boolean
        get() = selectedWorkIds.isNotEmpty()

    /** Show privacy toolbar affordance when mature works exist. */
    val showPrivacyToggle: Boolean
        get() = matureWorkCount > 0
}
