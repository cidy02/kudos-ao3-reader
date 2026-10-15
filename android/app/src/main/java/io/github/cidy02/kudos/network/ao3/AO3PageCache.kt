package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.net.URI

/** iOS AO3AuthorPageCache: process memory only, 5 minutes fresh / 24 hours fallback, 128 pages. */
class AO3PageCache(
    private val now: () -> Long = System::currentTimeMillis,
    private val ttlMillis: Long = 5 * 60 * 1000L,
    private val staleMillis: Long = 24 * 60 * 60 * 1000L,
    private val maxEntries: Int = 128
) {
    enum class Kind { Dashboard, About, Works, AuthorSeries, Bookmarks, SeriesDetail, Inbox, Stats }
    data class Scope(val viewer: String?, val generation: Int?)
    data class Key(val url: String, val scope: Scope, val kind: Kind)
    private data class Entry(val response: AO3HttpResponse, val freshUntil: Long, val staleUntil: Long)
    private val entries = mutableMapOf<Key, Entry>()
    private var revision = 0L
    /**
     * What each removal took, so a read in flight is stopped only when its own page was
     * removed after it began. Every removal used to stop every read: one page's 404 left an
     * unrelated page loading for good (A37 F4). The last 64 are kept; a read older than the
     * oldest kept is stopped, to be safe.
     */
    private class Removal(val at: Long, val matches: (Key) -> Boolean)
    private val removals = ArrayDeque<Removal>()
    private var forgottenThrough = 0L

    private fun removed(matches: (Key) -> Boolean) {
        removals.addLast(Removal(++revision, matches))
        while (removals.size > 64) forgottenThrough = removals.removeFirst().at
    }

    @Synchronized
    private fun removedSince(key: Key, version: Long): Boolean =
        forgottenThrough > version || removals.any { it.at > version && it.matches(key) }

    @Synchronized
    fun value(key: Key, stale: Boolean = false): AO3HttpResponse? {
        val entry = entries[key] ?: return null
        val time = now()
        if (entry.staleUntil <= time) { entries.remove(key); return null }
        return entry.response.takeIf { stale || entry.freshUntil > time }
    }

    @Synchronized
    fun insert(key: Key, response: AO3HttpResponse) {
        val time = now()
        entries.entries.removeAll { it.value.staleUntil <= time }
        if (key !in entries && entries.size >= maxEntries.coerceAtLeast(1)) {
            entries.minByOrNull { it.value.staleUntil }?.key?.let(entries::remove)
        }
        entries[key] = Entry(response.copy(headers = emptyMap()), time + ttlMillis, time + maxOf(ttlMillis, staleMillis))
    }

    @Synchronized
    fun remove(key: Key) { removed { it == key }; entries.remove(key) }

    /** A page that would not parse is dropped; that is no write, so no read is stopped for it. */
    @Synchronized
    private fun evict(key: Key) { entries.remove(key) }

    /** Every filter/page variant; a write changes totals and row state across the Inbox. */
    @Synchronized
    fun removePages(path: String, scope: Scope) {
        val matches = { key: Key -> key.scope == scope && URI(key.url).path == path }
        removed(matches)
        entries.keys.removeAll(matches)
    }

    @Synchronized
    fun removeAuthorDashboards(username: String, scope: Scope) {
        val matches = { key: Key ->
            key.scope == scope && key.kind == Kind.Dashboard &&
                URI(key.url).path.split('/').getOrNull(2)?.equals(username, true) == true
        }
        removed(matches)
        entries.keys.removeAll(matches)
    }

    /**
     * iOS `removeAuthorPages` (T-379): one of this account's own works, chapters or drafts was
     * written to, so every kept page under its address (works, series, bookmarks, stats, the
     * dashboard, any pseud, any viewer) may list what is no longer so (A37 F1).
     */
    @Synchronized
    fun removeAuthorPages(username: String) {
        val prefix = "/users/${username.lowercase()}/"
        val dashboard = "/users/${username.lowercase()}"
        val matches = { key: Key -> URI(key.url).path.lowercase().let { it.startsWith(prefix) || it == dashboard } }
        removed(matches)
        entries.keys.removeAll(matches)
    }

    /** iOS `removeSeries` (T-378): a series' own pages and its creator's series lists, any viewer (A37 F2). */
    @Synchronized
    fun removeSeries(id: Long, creator: String?) {
        val listPrefix = creator?.let { "/users/${it.lowercase()}/" }
        val matches = { key: Key ->
            val path = URI(key.url).path.lowercase()
            path == "/series/$id" || listPrefix != null && path.startsWith(listPrefix) && path.endsWith("/series")
        }
        removed(matches)
        entries.keys.removeAll(matches)
    }

    @Synchronized
    fun clear() { removed { true }; entries.clear() }

    @Synchronized
    private fun revision(): Long = revision

    /** Parsing stays in the repository. Only a correctly parsed page can become a saved copy. */
    suspend fun <T> read(
        url: String,
        kind: Kind,
        auth: AO3AuthenticatedClient?,
        bypassCache: Boolean = false,
        fetch: suspend () -> AO3Result<AO3HttpResponse>,
        parse: suspend (AO3HttpResponse) -> AO3Result<T>
    ): AO3Result<T> {
        val viewerScope = scope(auth)
        val key = Key(url, viewerScope, kind)
        val version = revision()
        fun requireCurrent() {
            if (scope(auth) != viewerScope || removedSince(key, version)) throw CancellationException()
        }
        suspend fun parsed(response: AO3HttpResponse, stale: Boolean): AO3Result<T> {
            val result = parse(response)
            currentCoroutineContext().ensureActive()
            requireCurrent()
            return when (result) {
                is AO3Result.Success -> AO3Result.Success(result.value, isStale = stale)
                is AO3Result.Failure -> result
            }
        }
        suspend fun fallback(failure: AO3Result.Failure): AO3Result<T> {
            val copy = value(key, stale = true) ?: return failure
            val cached = parsed(copy, true)
            if (cached is AO3Result.Failure) evict(key)
            return cached
        }
        currentCoroutineContext().ensureActive()
        requireCurrent()
        if (!bypassCache) value(key)?.let {
            val cached = parsed(it, false)
            if (cached is AO3Result.Failure) evict(key)
            return cached
        }
        val result = if (bypassCache) withContext(AO3UncoalescedRead()) { fetch() } else fetch()
        currentCoroutineContext().ensureActive()
        requireCurrent()
        return when (result) {
            is AO3Result.Success -> {
                val loaded = if (AO3OverloadDetector.isOverloadPage(result.value.body)) {
                    AO3Result.Failure(AO3Error.Overloaded(result.value.statusCode, null))
                } else parsed(result.value, false)
                when {
                    loaded is AO3Result.Success -> synchronized(this) {
                        requireCurrent()
                        insert(key, result.value)
                        loaded
                    }
                    loaded is AO3Result.Failure && loaded.error.allowsPageFallback() ->
                        fallback(loaded)
                    else -> { evict(key); loaded }
                }
            }
            is AO3Result.Failure -> {
                if (result.error.allowsPageFallback()) {
                    fallback(result)
                } else {
                    evict(key)
                    result
                }
            }
        }
    }

    companion object {
        val shared = AO3PageCache()
        fun scope(auth: AO3AuthenticatedClient?) = Scope(auth?.username(), auth?.sessionGeneration())
    }
}

internal fun AO3Error.allowsPageFallback(): Boolean = when (this) {
    is AO3Error.Network, is AO3Error.Overloaded -> true
    is AO3Error.Server -> statusCode in 500..599
    is AO3Error.Http -> statusCode in 500..599
    else -> false
}
