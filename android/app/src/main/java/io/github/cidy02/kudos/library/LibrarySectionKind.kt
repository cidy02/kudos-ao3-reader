package io.github.cidy02.kudos.library

enum class LibrarySectionKind(
    val id: String,
    val title: String,
    val emptyMessage: String
) {
    ReadingNow(
        "readingNow",
        "Reading Now",
        "You aren't reading anything yet. Open a work from your Library or find one in Browse."
    ),
    SavedForLater(
        "savedForLater",
        "Saved for Later",
        "You haven't saved any works for later. Add a work to Saved for Later to see it here."
    ),
    Finished("finished", "Finished", "Works you mark as finished will appear here."),
    Collections(
        "collections",
        "Collections",
        "You have no collections yet. Create one from your Library to group works together."
    ),
    Downloaded(
        "downloaded",
        "Downloaded",
        "Download a work to read it without an internet connection."
    ),
    History(
        "history",
        "Reading History",
        "Works you open appear here with your reading time, reread count, and any new chapters."
    ),
    Favorites(
        "favorites",
        "Favorites",
        "To add a favorite, swipe a work in your Library or tap the star on its page."
    );

    /**
     * The label over the rows (iOS `LibrarySectionKind.groupTitle`): Reading Now's list is headed
     * "In progress"; the other sections keep their title.
     */
    val groupTitle: String
        get() = if (this == ReadingNow) "In progress" else title

    fun items(state: LibraryUiState): List<LibraryDisplayItem> = when (this) {
        ReadingNow -> state.continueReading
        SavedForLater -> state.savedForLater
        Finished -> state.finished
        Collections -> emptyList()
        Downloaded -> state.downloaded
        History -> state.readingHistory
        Favorites -> state.favorites
    }

    /** iOS `items`: section membership after privacy, before the filter panel. */
    fun unfilteredItems(state: LibraryUiState): List<LibraryDisplayItem> = when (this) {
        ReadingNow -> LibraryQuery.continueReading(state.collectionMembers)
        SavedForLater -> LibraryQuery.savedForLater(state.collectionMembers)
        Finished -> LibraryQuery.finished(state.collectionMembers)
        Downloaded -> LibraryQuery.downloaded(state.collectionMembers)
        History -> LibraryQuery.readingHistory(state.collectionMembers)
        Favorites -> state.collectionMembers.filter { it.item.work.isFavorite }
        Collections -> emptyList()
    }

    companion object {
        fun fromId(id: String?): LibrarySectionKind? = entries.firstOrNull { it.id == id }
    }
}
