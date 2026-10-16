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

    @Synchronized
    fun get(kind: AccountListType, authenticationScope: String): Count? {
        val key = key(kind, authenticationScope)
        val entry = entries[key] ?: return null
        if (entry.expiresAt < System.currentTimeMillis()) {
            entries.remove(key)
            return null
        }
        return entry.count
    }

    @Synchronized
    fun put(kind: AccountListType, authenticationScope: String, count: Count) {
        val key = key(kind, authenticationScope)
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
    }

    private fun key(kind: AccountListType, scope: String): String =
        "${scope.lowercase()}|${kind.listKey}"
}
