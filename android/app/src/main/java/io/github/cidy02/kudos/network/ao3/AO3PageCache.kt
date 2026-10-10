package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.net.URI

/** iOS AO3AuthorPageCache: process memory only, 5 minutes fresh / 24 hours fallback, 128 pages. */
class AO3PageCache(
    private val now: () -> Long = System::currentTimeMillis,
    private val ttlMillis: Long = 5 * 60 * 1000L,
    private val staleMillis: Long = 24 * 60 * 60 * 1000L,
    private val maxEntries: Int = 128
) {
    enum class Kind { Dashboard, About, Works, AuthorSeries, Bookmarks, SeriesDetail, Inbox }
    data class Scope(val viewer: String?, val generation: Int?)
    data class Key(val url: String, val scope: Scope, val kind: Kind)
    private data class Entry(val response: AO3HttpResponse, val freshUntil: Long, val staleUntil: Long)
    private val entries = mutableMapOf<Key, Entry>()
    private var revision = 0L

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
    fun remove(key: Key) { revision++; entries.remove(key) }

    /** Every filter/page variant; a write changes totals and row state across the Inbox. */
    @Synchronized
    fun removePages(path: String, scope: Scope) {
        revision++
        entries.keys.removeAll { it.scope == scope && URI(it.url).path == path }
    }

    @Synchronized
    fun removeAuthorDashboards(username: String, scope: Scope) {
        revision++
        entries.keys.removeAll {
            it.scope == scope && it.kind == Kind.Dashboard &&
                URI(it.url).path.split('/').getOrNull(2)?.equals(username, true) == true
        }
    }

    @Synchronized
    fun clear() { revision++; entries.clear() }

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
            if (scope(auth) != viewerScope || version != revision()) throw CancellationException()
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
            if (cached is AO3Result.Failure) remove(key)
            return cached
        }
        currentCoroutineContext().ensureActive()
        requireCurrent()
        if (!bypassCache) value(key)?.let {
            val cached = parsed(it, false)
            if (cached is AO3Result.Failure) remove(key)
            return cached
        }
        val result = fetch()
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
                    else -> { remove(key); loaded }
                }
            }
            is AO3Result.Failure -> {
                if (result.error.allowsPageFallback()) {
                    fallback(result)
                } else {
                    remove(key)
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
