package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.author.*
import io.github.cidy02.kudos.network.ao3.inbox.*
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.net.SocketTimeoutException

/** Local fixture clients only; every assertion exercises the production repositories/cache. */
class CachedAO3PagesRepositoryTest {
    private class Client : AO3Client, AO3AuthenticatedClient {
        var viewer: String? = "tester"
        var generation = 1
        var reads = 0
        var error: AO3Error? = null
        var htmlOverride: String? = null
        var postBody = "<div class='flash notice'>Updated.</div>"
        override fun username() = viewer
        override fun sessionGeneration() = generation
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            reads++
            error?.let { return AO3Result.Failure(it) }
            val fixtureName = when {
                url.contains("/inbox") -> "ao3_inbox_manage"
                url.contains("/series/55") -> null
                url.contains("/bookmarks") -> "ao3_author_bookmarks"
                url.contains("/profile") -> "ao3_author_profile"
                url.contains("/works") -> "ao3_author_works"
                url.contains("/series") -> "ao3_author_series"
                else -> "ao3_author_dashboard_demo"
            }
            val html = htmlOverride ?: if (fixtureName == null) {
                checkNotNull(javaClass.classLoader?.getResource("ao3/series/series_page.html")).readText()
            } else fixture(fixtureName)
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
        }
        override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>) = AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), postBody))
    }

    private class Pages(val client: Client = Client()) {
        var clock = 0L
        val cache = AO3PageCache(now = { clock })
        val author = AO3AuthorRepository(client, client, parseDispatcher = Dispatchers.Unconfined, pageCache = cache)
        val inbox = AO3InboxRepository(client, pageCache = cache)
        val series = AO3SeriesRepository(client, authenticatedClient = client, pageCache = cache)
        suspend fun load(screen: String, bypass: Boolean = false): AO3Result<*> = when (screen) {
            "Inbox" -> inbox.load(bypassCache = bypass)
            "Account profile" -> author.loadDashboard(AO3AuthorRoute("tester"), bypass)
            "Author profile" -> author.loadDashboard(AO3AuthorRoute("Avery_Archive"), bypass)
            "Author works" -> author.loadWorks(AO3AuthorRoute("Avery_Archive"), bypassCache = bypass)
            "Author about" -> author.loadAbout(AO3AuthorRoute("Avery_Archive"), bypass)
            "Author series" -> author.loadSeries(AO3AuthorRoute("Avery_Archive"), bypassCache = bypass)
            "Author bookmarks" -> author.loadBookmarks(AO3AuthorRoute("Avery_Archive"), bypassCache = bypass)
            else -> series.detailPage("https://archiveofourown.org/series/55", bypassCache = bypass)
        }
    }
    private val screens = listOf("Inbox", "Account profile", "Author profile", "Series",
        "Author works", "Author about", "Author series", "Author bookmarks")

    @Test fun firstSecondExpiredAndRefreshCountsForEveryPage() = runBlocking<Unit> {
        for (screen in screens) {
            val pages = Pages()
            assertTrue(pages.load(screen) is AO3Result.Success)
            assertEquals(screen, 1, pages.client.reads)
            assertTrue(pages.load(screen) is AO3Result.Success)
            assertEquals(screen, 1, pages.client.reads)
            pages.clock = 300_000L
            assertTrue(pages.load(screen) is AO3Result.Success)
            assertEquals(screen, 2, pages.client.reads)
            assertTrue(pages.load(screen, bypass = true) is AO3Result.Success)
            assertEquals(screen, 3, pages.client.reads)
        }
    }

    @Test fun authorHeaderAndSelectedWorksEachSaveTheirOwnRequest() = runBlocking<Unit> {
        val pages = Pages()
        val route = AO3AuthorRoute("Avery_Archive")
        pages.author.loadDashboard(route); pages.author.loadWorks(route)
        assertEquals(2, pages.client.reads)
        pages.author.loadDashboard(route); pages.author.loadWorks(route)
        assertEquals(2, pages.client.reads)
        pages.clock = 300_000L
        pages.author.loadDashboard(route); pages.author.loadWorks(route)
        assertEquals(4, pages.client.reads)
        pages.author.loadDashboard(route, true); pages.author.loadWorks(route, bypassCache = true)
        assertEquals(6, pages.client.reads)
    }

    @Test fun inboxNewModelActivationBypassesFreshCacheLikeIOS() = runBlocking<Unit> {
        val pages = Pages()
        pages.inbox.load(bypassCache = true)
        pages.inbox.load(bypassCache = true)
        assertEquals(2, pages.client.reads)
        pages.inbox.load() // ordinary same-session pagination can hit fresh memory
        assertEquals(2, pages.client.reads)
    }

    @Test fun everyAllowedFailureShowsItsOwnOldCopyAndFreshSuccessClearsFlag() = runBlocking<Unit> {
        val failures = listOf(AO3Error.Network("offline", offline = true),
            AO3Error.networkFromTransport(SocketTimeoutException("timeout")),
            AO3Error.Network("connection dropped"), AO3Error.Server(500), AO3Error.Server(503),
            AO3Error.Http(502), AO3Error.Overloaded(200, null))
        for (screen in screens) for (failure in failures) {
            val pages = Pages()
            val original = pages.load(screen) as AO3Result.Success
            pages.clock = 300_000L
            pages.client.error = failure
            val cached = pages.load(screen) as AO3Result.Success
            assertEquals("$screen $failure", original.value, cached.value)
            assertTrue("$screen $failure", cached.isStale)
            pages.client.error = null
            val fresh = pages.load(screen, bypass = true) as AO3Result.Success
            assertFalse(fresh.isStale)
        }
    }

    @Test fun everyRefusalReplacesTheCopyAndCannotResurrectItOffline() = runBlocking<Unit> {
        val failures = listOf(AO3Error.AuthenticationRequired, AO3Error.Forbidden, AO3Error.NotFound,
            AO3Error.BadRequest, AO3Error.Http(403), AO3Error.Http(404), AO3Error.RateLimited(null),
            AO3Error.Parse("changed"), AO3Error.Validation("refused"))
        for (screen in screens) for (failure in failures) {
            val pages = Pages()
            pages.load(screen)
            pages.client.error = failure
            assertEquals("$screen $failure", AO3Result.Failure(failure), pages.load(screen, bypass = true))
            pages.client.error = AO3Error.Network("offline")
            assertTrue(pages.load(screen) is AO3Result.Failure)
        }
    }

    @Test fun busyHTMLFallsBackButParserDriftDoesNot() = runBlocking<Unit> {
        for (screen in screens) {
            val pages = Pages()
            pages.load(screen)
            pages.client.htmlOverride = "<html><h2>Archive of Our Own is temporarily overloaded</h2></html>"
            assertTrue((pages.load(screen, bypass = true) as AO3Result.Success).isStale)
            pages.client.htmlOverride = "<html><p>Markup without a page landmark</p></html>"
            assertTrue(pages.load(screen, bypass = true) is AO3Result.Failure)
            pages.client.error = AO3Error.Network("offline")
            assertTrue(pages.load(screen) is AO3Result.Failure)
        }
    }

    @Test fun copiesNeverCrossSessionsAccountsOrSignedOut() = runBlocking<Unit> {
        for (screen in screens) {
            val pages = Pages()
            pages.load(screen)
            pages.client.error = AO3Error.Network("offline")
            pages.client.generation++
            assertTrue(pages.load(screen) is AO3Result.Failure)
            pages.client.viewer = "another"
            assertTrue(pages.load(screen) is AO3Result.Failure)
            pages.client.viewer = null
            assertTrue(pages.load(screen) is AO3Result.Failure)
        }
    }

    @Test fun eachConfirmedInboxWriteRemovesAllPageAndFilterVariants() = runBlocking<Unit> {
        for (action in AO3InboxBulkAction.entries) {
            val pages = Pages()
            val loaded = (pages.inbox.load() as AO3Result.Success).value
            pages.inbox.load(page = 2)
            val scope = AO3PageCache.scope(pages.client)
            val path = "/users/tester/inbox"
            val variant = AO3PageCache.Key("https://archiveofourown.org$path?unread=true", scope, AO3PageCache.Kind.Inbox)
            pages.cache.insert(variant, AO3HttpResponse(variant.url, 200, emptyMap(), "filter copy"))
            val outcome = pages.inbox.performBulkAction(action, checkNotNull(loaded.bulkForm),
                loaded.items.filter { it.bulkSelectionField != null }.take(1), checkNotNull(loaded.pageUrl))
            assertTrue("$action", outcome is AO3Result.Success)
            assertNull(pages.cache.value(variant, stale = true))
            pages.client.error = AO3Error.Network("offline")
            assertTrue(pages.inbox.load() is AO3Result.Failure)
            assertTrue(pages.inbox.load(page = 2) is AO3Result.Failure)
        }
    }

    @Test fun unconfirmedInboxWriteKeepsTheCopy() = runBlocking<Unit> {
        val pages = Pages()
        val loaded = (pages.inbox.load() as AO3Result.Success).value
        pages.client.postBody = "<html>No notice.</html>"
        val result = pages.inbox.performBulkAction(AO3InboxBulkAction.MarkRead, checkNotNull(loaded.bulkForm),
            loaded.items.filter { it.bulkSelectionField != null }.take(1), checkNotNull(loaded.pageUrl))
        assertTrue(result is AO3Result.Failure)
        pages.client.error = AO3Error.Network("offline")
        assertTrue((pages.inbox.load(bypassCache = true) as AO3Result.Success).isStale)
    }

    companion object {
        private fun fixture(name: String): String = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.first(File::isFile).readText()
    }
}
