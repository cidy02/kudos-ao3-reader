package io.github.cidy02.kudos.account

/**
 * Read-only AO3 account work-list kinds.
 *
 * Static hub rows under Account → My AO3 use [hubEntries].
 * [Collection] is opened from the separate "My Collections (AO3)" index.
 */
sealed class AccountListType {
    abstract val title: String
    abstract val emptyTitle: String
    abstract val emptyMessage: String
    /** Stable ViewModel / list key (not a display string). */
    abstract val listKey: String

    data object MarkedForLater : AccountListType() {
        override val title = "Marked for Later"
        override val emptyTitle = "Nothing marked for later"
        override val emptyMessage = "Works you mark for later on AO3 show up here."
        override val listKey = "MarkedForLater"
    }

    data object Bookmarks : AccountListType() {
        override val title = "My AO3 Bookmarks"
        override val emptyTitle = "No bookmarks yet"
        override val emptyMessage = "Works you bookmark on AO3 show up here."
        override val listKey = "Bookmarks"
    }

    data object History : AccountListType() {
        override val title = "My AO3 History"
        override val emptyTitle = "No reading history"
        override val emptyMessage = "Works you read on AO3 show up here."
        override val listKey = "History"
    }

    data object Subscriptions : AccountListType() {
        override val title = "My Subscriptions"
        override val emptyTitle = "No subscriptions"
        override val emptyMessage = "Works you subscribe to on AO3 show up here."
        override val listKey = "Subscriptions"
    }

    data object MyWorks : AccountListType() {
        override val title = "My Works"
        override val emptyTitle = "No works yet"
        override val emptyMessage = "Works you post on AO3 show up here."
        override val listKey = "MyWorks"
    }

    /**
     * Works in a named AO3 collection (`/collections/<name>/works`).
     * [name] is the URL slug; [displayTitle] is the human collection title.
     */
    data class Collection(
        val name: String,
        val displayTitle: String
    ) : AccountListType() {
        override val title: String get() = displayTitle
        override val emptyTitle = "No works in this collection"
        override val emptyMessage = "This collection has no works yet."
        override val listKey: String get() = "Collection:$name"
    }

    companion object {
        /** Hub destinations under "My AO3" (excludes [Collection]). */
        val hubEntries: List<AccountListType> = listOf(
            MarkedForLater,
            Bookmarks,
            History,
            Subscriptions,
            MyWorks
        )
    }
}
