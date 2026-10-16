package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.account.AO3AccountListCountsCache.Count
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `AO3AccountListCountsTests` (A59). */
class AO3AccountListCountsCacheTest {
    @Test fun sameUsernameDifferentSessionGenerationDoesNotReuseAStaleCount() {
        val cache = AO3AccountListCountsCache()
        cache.put(AccountListType.History, AO3AccountListCountsCache.scope("alice", 1), Count(exact = 41))
        assertNull(cache.get(AccountListType.History, AO3AccountListCountsCache.scope("alice", 2)))
        assertEquals(41, cache.get(AccountListType.History, AO3AccountListCountsCache.scope("alice", 1))?.exact)
    }

    @Test fun aPageThatMayOmitRowsIsAFloorNotATotal() {
        val single = Count(itemsOnPage = 7, totalPages = 1, mayOmitRows = true)
        assertNull(single.exact)
        assertEquals(7, single.lowerBound)
        assertEquals("7+", single.displayText)
        assertEquals(Count(itemsOnPage = 20, totalPages = 3), Count(itemsOnPage = 20, totalPages = 3, mayOmitRows = true))
        assertEquals(7, Count(itemsOnPage = 7, totalPages = 1, mayOmitRows = false).exact)
    }

    @Test fun openingBookmarksKeepsAO3sExactCount() {
        val cache = AO3AccountListCountsCache()
        val scope = AO3AccountListCountsCache.scope("astolat", 1)
        cache.put(AccountListType.Bookmarks, scope, Count(exact = 10))
        cache.put(AccountListType.Bookmarks, scope, Count(itemsOnPage = 7, totalPages = 1, mayOmitRows = true))
        assertEquals(10, cache.get(AccountListType.Bookmarks, scope)?.exact)
    }

    /** A loaded list records its count under the session that read it, Bookmarks as a floor. */
    @Test fun aLoadedBookmarksPageIsRecordedForItsSessionAsAFloor() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val html = javaClass.classLoader!!.getResource("ao3/account/bookmarks.html")!!.readText()
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
        }
        val cache = AO3AccountListCountsCache()
        val page = (AccountListRepository(client, auth, countsCache = cache)
            .load(AccountListType.Bookmarks) as AO3Result.Success).value
        assertEquals(1, page.totalPages)
        assertTrue(page.works.isNotEmpty())
        val scope = AO3AccountListCountsCache.scope("AO3_Reader", auth.generation.value)
        assertEquals(Count(lowerBound = page.works.size), cache.get(AccountListType.Bookmarks, scope))
        assertNull(cache.get(AccountListType.Bookmarks, AO3AccountListCountsCache.scope("AO3_Reader", auth.generation.value + 1)))
    }

    @Test fun dashboardNavSeedsCountsWithoutOpeningAnyList() {
        fun action(label: String, path: String) = io.github.cidy02.kudos.network.ao3.author.AO3AuthorWebAction(
            label, "https://archiveofourown.org$path", io.github.cidy02.kudos.network.ao3.author.AO3AuthorWebAction.Kind.Other)
        val cache = AO3AccountListCountsCache()
        val scope = AO3AccountListCountsCache.scope("astolat", 1)
        cache.recordDashboard(listOf(
            action("Works (535)", "/users/astolat/works"),
            action("Series (40)", "/users/astolat/series"),
            action("Bookmarks (1,022)", "/users/astolat/bookmarks"),
            action("Collections (33)", "/users/astolat/collections"),
            action("Gifts (131)", "/users/astolat/gifts"),
            action("Works (7)", "/users/astolat/pseuds/other/works"),
            action("Works (some)", "/users/astolat/works")
        ), "astolat", scope)
        assertEquals(535, cache.get(AccountListType.MyWorks, scope)?.exact)
        assertEquals(1022, cache.get(AccountListType.Bookmarks, scope)?.exact)
        assertEquals(33, cache.get(AO3AccountListCountsCache.COLLECTIONS, scope)?.exact)
        assertEquals(40, cache.get(AO3AccountListCountsCache.SERIES, scope)?.exact)
        assertNull(cache.get(AccountListType.Subscriptions, scope))
        assertNull(cache.get(AccountListType.History, scope))
    }
}
