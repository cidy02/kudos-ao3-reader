package io.github.cidy02.kudos.account

import java.util.concurrent.CopyOnWriteArrayList

/**
 * In-session cache of account-list sizes for Overview cards.
 * Port of iOS `AO3AccountListCountsCache` — never fetches; only stores counts
 * derived from list pages the user already loaded.
 */
class AO3AccountListCountsCache(
    private val ttlMillis: Long = 30 * 60 * 1000L
) {
    data class Count(
        val exact: Int? = null,
        val lowerBound: Int? = null
    ) {
        val displayText: String?
            get() = when {
                exact != null -> exact.toString()
                lowerBound != null && lowerBound > 0 -> "$lowerBound+"
                else -> null
            }

        /**
         * Returns a known count only when [exact] is present (including `0`) or
         * [lowerBound] proves the list is non-empty (`> 0`). A weak zero lower
         * bound without [exact] is unknown (`null`), never zero.
         */
        val knownCount: Int?
            get() = when {
                exact != null -> exact
                lowerBound != null && lowerBound > 0 -> lowerBound
                else -> null
            }

        /**
         * [mayOmitRows]: a list whose page keeps fewer rows than AO3 counts (Bookmarks keeps only
         * work bookmarks). One page of it is then a floor, so it never replaces AO3's own exact
         * figure with a smaller one (iOS `AO3AccountListCount(mayOmitRows:)`; A59).
         */
        constructor(itemsOnPage: Int, totalPages: Int, mayOmitRows: Boolean = false) : this(
            exact = if (totalPages <= 1 && !mayOmitRows) itemsOnPage else null,
            lowerBound = when {
                totalPages > 1 -> itemsOnPage * (totalPages - 1)
                mayOmitRows -> itemsOnPage
                else -> null
            }
        )

        fun isAtLeastAsStrongAs(other: Count): Boolean {
            if (exact != null) return true
            if (other.exact != null) return false
            return (lowerBound ?: 0) >= (other.lowerBound ?: 0)
        }
    }

    private data class Entry(val count: Count, val expiresAt: Long)

    private val entries = mutableMapOf<String, Entry>()
    private val writingCountListeners = CopyOnWriteArrayList<(String) -> Unit>()

    fun addWritingCountListener(listener: (String) -> Unit) {
        writingCountListeners += listener
    }

    fun removeWritingCountListener(listener: (String) -> Unit) {
        writingCountListeners -= listener
    }

    fun get(kind: AccountListType, authenticationScope: String): Count? = get(kind.listKey, authenticationScope)

    @Synchronized
    fun get(listKey: String, authenticationScope: String): Count? {
        val key = key(listKey, authenticationScope)
        val entry = entries[key] ?: return null
        if (entry.expiresAt < System.currentTimeMillis()) {
            entries.remove(key)
            return null
        }
        return entry.count
    }

    fun put(kind: AccountListType, authenticationScope: String, count: Count) = put(kind.listKey, authenticationScope, count)

    /**
     * The exact sizes AO3 prints in the dashboard nav of the page the profile header came from:
     * Works, Series, Bookmarks, Collections. No request of its own (iOS `record(dashboardActions:)`).
     * Exact tails only, so a pseud's own "/pseuds/<name>/works" never lands here.
     */
    fun recordDashboard(actions: List<io.github.cidy02.kudos.network.ao3.author.AO3AuthorWebAction>,
        username: String, authenticationScope: String) {
        val base = "/users/${username.lowercase()}/"
        var writingChanged = false
        for (action in actions) {
            val path = runCatching { java.net.URI(action.url).path }.getOrNull()?.lowercase() ?: continue
            if (!path.startsWith(base)) continue
            val listKey = when (path.removePrefix(base)) {
                "works" -> AccountListType.MyWorks.listKey
                "series" -> SERIES
                "bookmarks" -> AccountListType.Bookmarks.listKey
                "collections" -> COLLECTIONS
                "drafts", "works/drafts" -> DRAFTS
                else -> continue
            }
            if (put(listKey, authenticationScope, Count(exact = action.listCount ?: continue), notify = false) &&
                isWritingKey(listKey)
            ) {
                writingChanged = true
            }
        }
        // One notification per dashboard load: each listener re-reads the disk.
        if (writingChanged) notifyWritingCount(authenticationScope)
    }

    private fun isWritingKey(listKey: String) =
        listKey == AccountListType.MyWorks.listKey || listKey == SERIES || listKey == DRAFTS

    private fun notifyWritingCount(authenticationScope: String) {
        for (listener in writingCountListeners) {
            listener(authenticationScope)
        }
    }

    /** True when the count was stored. */
    fun put(listKey: String, authenticationScope: String, count: Count, notify: Boolean = true): Boolean {
        synchronized(this) {
            val key = key(listKey, authenticationScope)
            val existing = entries[key]?.takeIf { it.expiresAt >= System.currentTimeMillis() }
            if (existing != null && !count.isAtLeastAsStrongAs(existing.count)) return false
            entries[key] = Entry(count, System.currentTimeMillis() + ttlMillis)
        }
        if (notify && isWritingKey(listKey)) notifyWritingCount(authenticationScope)
        return true
    }

    @Synchronized
    fun clearScope(authenticationScope: String) {
        val prefix = "${authenticationScope.lowercase()}|"
        entries.keys.removeAll { it.startsWith(prefix) }
    }

    companion object {
        /**
         * A session's counts are its own: the same name signed in again is another session, as
         * iOS's `sessionScopedCacheScope` (A59).
         */
        fun scope(username: String, generation: Int): String = "$username#session-$generation"

        /** Lists with no [AccountListType] whose size only the dashboard nav or drafts index gives. */
        const val SERIES = "Series"
        const val COLLECTIONS = "Collections"
        const val DRAFTS = "Drafts"
    }

    private fun key(listKey: String, scope: String): String =
        "${scope.lowercase()}|$listKey"
}
