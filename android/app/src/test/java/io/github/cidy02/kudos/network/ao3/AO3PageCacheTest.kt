package io.github.cidy02.kudos.network.ao3

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class AO3PageCacheTest {
    private val scope = AO3PageCache.Scope("Reader", 1)
    private fun key(path: String = "/users/Writer", viewer: AO3PageCache.Scope = scope,
        kind: AO3PageCache.Kind = AO3PageCache.Kind.Dashboard) =
        AO3PageCache.Key("https://archiveofourown.org$path", viewer, kind)
    private fun response(key: AO3PageCache.Key, text: String = "saved") =
        AO3HttpResponse(key.url, 200, emptyMap(), text)

    @Test fun lifetimesAreMeasuredFromInsertionNotReading() {
        var clock = 0L
        val cache = AO3PageCache(now = { clock })
        val key = key()
        cache.insert(key, response(key))
        clock = 299_999L
        assertNotNull(cache.value(key))
        clock = 300_000L
        assertNull(cache.value(key))
        assertNotNull(cache.value(key, stale = true))
        clock = 86_399_999L
        assertNotNull(cache.value(key, stale = true))
        clock = 86_400_000L
        assertNull(cache.value(key, stale = true))
    }

    @Test fun limitEvictsEarliestDeadlineEvenIfRecentlyRead() {
        var clock = 0L
        val cache = AO3PageCache(now = { clock })
        repeat(128) { i -> clock = i.toLong(); val key = key("/series/$i"); cache.insert(key, response(key)) }
        assertNotNull(cache.value(key("/series/0")))
        clock++
        val last = key("/series/128")
        cache.insert(last, response(last))
        assertNull(cache.value(key("/series/0"), stale = true))
        assertNotNull(cache.value(key("/series/1")))
        assertNotNull(cache.value(last))
    }

    @Test fun scopeAndKindAndFullUrlAreIndependent() {
        val cache = AO3PageCache()
        val first = key()
        cache.insert(first, response(first))
        for (viewer in listOf(AO3PageCache.Scope("Reader", 2), AO3PageCache.Scope("Other", 1),
            AO3PageCache.Scope(null, 1), AO3PageCache.Scope(null, 2))) {
            assertNull(cache.value(key(viewer = viewer), stale = true))
        }
        assertNull(cache.value(key(kind = AO3PageCache.Kind.Works), stale = true))
        assertNull(cache.value(key("/users/Writer?page=2"), stale = true))
        val anonymous = key(viewer = AO3PageCache.Scope(null, 1))
        cache.insert(anonymous, response(anonymous, "public"))
        assertEquals("public", cache.value(anonymous)?.body)
        assertEquals("saved", cache.value(first)?.body)
    }

    @Test fun pathRemovalCoversEveryInboxVariantOnlyInThisSession() {
        val cache = AO3PageCache()
        val keys = listOf(key("/users/Reader/inbox"), key("/users/Reader/inbox?page=2"),
            key("/users/Reader/inbox?unread=true"))
        keys.forEach { cache.insert(it, response(it)) }
        val other = key("/users/Reader/inbox", AO3PageCache.Scope("Reader", 2))
        val different = key("/users/Reader")
        cache.insert(other, response(other)); cache.insert(different, response(different))
        cache.removePages("/users/Reader/inbox", scope)
        keys.forEach { assertNull(cache.value(it, stale = true)) }
        assertNotNull(cache.value(other)); assertNotNull(cache.value(different))
    }

    @Test fun dashboardRemovalIncludesPseudsButLeavesIndexesAndOtherViewers() {
        val cache = AO3PageCache()
        val dashboards = listOf(key("/users/Writer"), key("/users/Writer/pseuds/Pen"))
        val works = key("/users/Writer/works", kind = AO3PageCache.Kind.Works)
        val other = key(viewer = AO3PageCache.Scope("Other", 1))
        (dashboards + listOf(works, other)).forEach { cache.insert(it, response(it)) }
        cache.removeAuthorDashboards("writer", scope)
        dashboards.forEach { assertNull(cache.value(it, stale = true)) }
        assertNotNull(cache.value(works)); assertNotNull(cache.value(other))
    }

    @Test fun clearCannotBeUndoneByAnInFlightRead() = runBlocking<Unit> {
        val cache = AO3PageCache()
        val started = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        val job = async {
            cache.read(key().url, key().kind, null,
                fetch = { started.complete(Unit); finish.await(); AO3Result.Success(response(key())) },
                parse = { AO3Result.Success(it.body) })
        }
        started.await()
        cache.clear()
        finish.complete(Unit)
        try { job.await(); fail("Old continuation must be cancelled") }
        catch (_: kotlinx.coroutines.CancellationException) { }
        assertNull(cache.value(key(viewer = AO3PageCache.Scope(null, null)), stale = true))
    }

    @Test fun anotherPagesFailureOrRemovalDoesNotStopThisRead() = runBlocking<Unit> {
        // A37 F4: one page's 404, or one page's removal, stopped every read in flight, and an
        // unrelated screen stayed loading.
        val cache = AO3PageCache()
        val anon = AO3PageCache.Scope(null, null)
        val series = key("/series/7", anon, AO3PageCache.Kind.SeriesDetail)
        val author = key("/users/Gone", anon)
        val started = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        val reading = async {
            cache.read(series.url, series.kind, null,
                fetch = { started.complete(Unit); finish.await(); AO3Result.Success(response(series)) },
                parse = { AO3Result.Success(it.body) })
        }
        started.await()
        cache.read(author.url, author.kind, null, fetch = { AO3Result.Failure(AO3Error.NotFound) },
            parse = { AO3Result.Success(it.body) })
        cache.removePages("/users/Somebody", anon)
        finish.complete(Unit)
        assertEquals(AO3Result.Success("saved"), reading.await())
    }

    @Test fun anOwnWorkWriteForgetsEveryPageUnderTheWritersAddressOnly() {
        // A37 F1, iOS removeAuthorPages: works, pseuds, series, stats and the dashboard, any viewer.
        val cache = AO3PageCache()
        val other = AO3PageCache.Scope("Someone", 2)
        val mine = listOf(key("/users/Writer"), key("/users/Writer/works?page=2", kind = AO3PageCache.Kind.Works),
            key("/users/writer/pseuds/Pen/works", other, AO3PageCache.Kind.Works), key("/users/Writer/stats", kind = AO3PageCache.Kind.Stats))
        val kept = listOf(key("/users/Writerly"), key("/users/Other/works", kind = AO3PageCache.Kind.Works),
            key("/series/7", kind = AO3PageCache.Kind.SeriesDetail))
        (mine + kept).forEach { cache.insert(it, response(it)) }
        cache.removeAuthorPages("Writer")
        mine.forEach { assertNull(it.url, cache.value(it, stale = true)) }
        kept.forEach { assertNotNull(it.url, cache.value(it, stale = true)) }
    }

    @Test fun aSeriesWriteForgetsTheSeriesAndItsCreatorsSeriesLists() {
        // A37 F2, iOS removeSeries.
        val cache = AO3PageCache()
        val gone = listOf(key("/series/7", kind = AO3PageCache.Kind.SeriesDetail),
            key("/users/Writer/series", kind = AO3PageCache.Kind.AuthorSeries),
            key("/users/Writer/pseuds/Pen/series", kind = AO3PageCache.Kind.AuthorSeries))
        val kept = listOf(key("/series/70", kind = AO3PageCache.Kind.SeriesDetail),
            key("/users/Writer/works", kind = AO3PageCache.Kind.Works), key("/users/Other/series", kind = AO3PageCache.Kind.AuthorSeries))
        (gone + kept).forEach { cache.insert(it, response(it)) }
        cache.removeSeries(7, "Writer")
        gone.forEach { assertNull(it.url, cache.value(it, stale = true)) }
        kept.forEach { assertNotNull(it.url, cache.value(it, stale = true)) }
    }

    @Test fun parserFailureRemovesOnlyTheFailedCopyAndDoesNotFallback() = runBlocking<Unit> {
        val cache = AO3PageCache()
        val key = key(viewer = AO3PageCache.Scope(null, null))
        cache.insert(key, response(key))
        val result = cache.read(key.url, key.kind, null, bypassCache = true,
            fetch = { AO3Result.Success(response(key, "unexpected markup")) },
            parse = { AO3Result.Failure(AO3Error.Parse("markup changed")) })
        assertTrue(result is AO3Result.Failure)
        assertNull(cache.value(key, stale = true))
    }

    @Test fun cacheReadAndRemovalLeaveTemporaryDirectoryEmpty() = runBlocking<Unit> {
        val directory = Files.createTempDirectory("kudos-page-cache-test").toFile()
        try {
            val cache = AO3PageCache()
            val key = key(viewer = AO3PageCache.Scope(null, null))
            cache.read(key.url, key.kind, null,
                fetch = { AO3Result.Success(response(key)) }, parse = { AO3Result.Success(it.body) })
            cache.removePages("/users/Writer", key.scope)
            cache.clear()
            assertTrue(directory.listFiles().orEmpty().isEmpty())
            assertNull(AO3PageCache().value(key, stale = true)) // a new process cache starts empty
        } finally { directory.deleteRecursively() }
    }
}
