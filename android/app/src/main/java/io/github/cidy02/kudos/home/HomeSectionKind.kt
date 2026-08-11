package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant

/**
 * A Home dashboard section, and the rule for which works belong in it.
 *
 * Direct port of iOS `HomeSectionKind` (`Features/Home/HomeSections.swift`).
 * The dashboard carousels cap the result; [works] itself is uncapped so the
 * "See all" screen can show the whole section.
 *
 * Subscriptions is deliberately not here: it is remote AO3 data, not SavedWorks,
 * and already has its own full list.
 */
enum class HomeSectionKind(val id: String, val title: String, val emptyMessage: String) {
    ReadingNow(
        id = "readingNow",
        title = "Reading Now",
        emptyMessage = "You're not reading anything right now. Start exploring in Browse " +
            "or open something from your Library."
    ),
    RecentlyUpdated(
        id = "recentlyUpdated",
        title = "Recently Updated",
        // iOS says "from your subscriptions", but the section filters saved works
        // by hasUpdate, not subscriptions. Deliberate divergence — see
        // docs/iOS_Issues_Found_While_Porting.md #1.
        emptyMessage = "No recent updates from your library works yet."
    ),
    Favorites(
        id = "favorites",
        title = "Favorites",
        emptyMessage = "No favorites yet. Mark works as favorites to see them here."
    ),
    RecentlyOpened(
        id = "recentlyOpened",
        title = "Recently Opened",
        emptyMessage = "Nothing opened recently. Start reading to see your history here."
    );

    /**
     * This section's works — filtered and ordered, uncapped. [visible] is the
     * privacy predicate. Ordering matches iOS exactly, because the "See all"
     * screen keeps the section's own order whenever no filter is active.
     */
    fun works(from: List<SavedWork>, visible: (SavedWork) -> Boolean): List<SavedWork> = when (this) {
        // In progress (started, not finished, file present) — most recently read first.
        ReadingNow -> from
            .filter { it.isInProgress && !it.isQueueOnlyWork && visible(it) }
            .sortedByDescending { it.recency }

        Favorites -> from
            .filter { it.isFavorite && visible(it) }
            .sortedByDescending { it.recency }

        // Works AO3 has added chapters to since the user last saw them.
        RecentlyUpdated -> from
            .filter { it.hasUpdate && !it.isQueueOnlyWork && visible(it) }
            .sortedByDescending { it.lastUpdateCheck ?: Instant.EPOCH }

        // Anything actually opened, newest first.
        RecentlyOpened -> from
            .filter { it.lastReadDate != null && !it.isQueueOnlyWork && visible(it) }
            .sortedByDescending { it.lastReadDate ?: Instant.EPOCH }
    }

    private val SavedWork.recency: Instant
        get() = lastReadDate ?: dateAdded

    companion object {
        fun fromId(id: String?): HomeSectionKind? = entries.firstOrNull { it.id == id }
    }
}
