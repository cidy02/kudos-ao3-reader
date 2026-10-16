package io.github.cidy02.kudos.account

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
        for (action in actions) {
            val path = runCatching { java.net.URI(action.url).path }.getOrNull()?.lowercase() ?: continue
            if (!path.startsWith(base)) continue
            val listKey = when (path.removePrefix(base)) {
                "works" -> AccountListType.MyWorks.listKey
                "series" -> SERIES
                "bookmarks" -> AccountListType.Bookmarks.listKey
                "collections" -> COLLECTIONS
                else -> continue
            }
            put(listKey, authenticationScope, Count(exact = action.listCount ?: continue))
        }
    }

    @Synchronized
    fun put(listKey: String, authenticationScope: String, count: Count) {
        val key = key(listKey, authenticationScope)
        val existing = entries[key]?.takeIf { it.expiresAt >= System.currentTimeMillis() }
        if (existing != null && !count.isAtLeastAsStrongAs(existing.count)) return
        entries[key] = Entry(count, System.currentTimeMillis() + ttlMillis)
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

        /** Lists with no [AccountListType] whose size only the dashboard nav gives. */
        const val SERIES = "Series"
        const val COLLECTIONS = "Collections"
    }

    private fun key(listKey: String, scope: String): String =
        "${scope.lowercase()}|$listKey"
}
