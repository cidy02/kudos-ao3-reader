package io.github.cidy02.kudos.author

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorParser
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.network.ao3.author.AO3UserStats
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The writer's own totals: read for the signed-in account's own page and for nothing else. */
class OwnStatsTest {
    private class Client(var viewer: String? = "Tester") : AO3Client, AO3AuthenticatedClient {
        val asked = mutableListOf<String>()
        var error: AO3Error? = null
        override fun username() = viewer
        override fun sessionGeneration() = 1
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            asked += url
            error?.let { return AO3Result.Failure(it) }
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), fixture("ao3_user_stats")))
        }
        override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>) = AO3Result.Failure(AO3Error.NotFound)
    }
    private companion object {
        fun fixture(name: String): String = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.first(File::isFile).readText()
    }
    private fun repository(client: Client) = AO3AuthorRepository(client, client,
        parseDispatcher = Dispatchers.Unconfined, pageCache = AO3PageCache())

    @Test fun theTotalsBlockIsReadAndNotAWorksOwnFigures() {
        assertEquals(
            AO3UserStats(wordCount = 248_400, kudos = 3_812, hits = 28_900, bookmarks = 96,
                commentThreads = 214, subscriptions = 128, userSubscriptions = 57),
            AO3AuthorParser().parseUserStats(fixture("ao3_user_stats"))
        )
        assertTrue("no works posted: no block, and not a failure",
            AO3AuthorParser().parseUserStats(fixture("ao3_user_stats_none")).isEmpty)
    }

    @Test fun onlyTheSignedInAccountsOwnPageAsksForThem() = runBlocking<Unit> {
        val client = Client()
        val repository = repository(client)
        assertNull("another author", repository.loadOwnStats(AO3AuthorRoute("Avery_Archive")))
        assertNull("a pseud of the account", repository.loadOwnStats(AO3AuthorRoute("tester", "Second Pseud")))
        client.viewer = null
        assertNull("signed out", repository.loadOwnStats(AO3AuthorRoute("tester")))
        assertEquals("none of those asked AO3 for anything", emptyList<String>(), client.asked)

        client.viewer = "Tester"
        val own = repository.loadOwnStats(AO3AuthorRoute("tester"))
        assertEquals(3_812, (own as AO3Result.Success).value.kudos)
        assertEquals(listOf("https://archiveofourown.org/users/tester/stats"), client.asked)
        repository.loadOwnStats(AO3AuthorRoute("tester"))
        assertEquals("kept: a second opening asks nothing", 1, client.asked.size)
        repository.loadOwnStats(AO3AuthorRoute("tester"), bypassCache = true)
        assertEquals("a pull to refresh reads it again", 2, client.asked.size)
    }

    @Test fun theLineKeepsWhatItHadWhenTheTotalsDoNotCome() {
        val stats = AO3UserStats(wordCount = 248_400, kudos = 3_812)
        assertEquals("12 works · 248,400 words · 3,812 kudos", ownWorksLine("Tester", 12, stats))
        assertEquals("1,204 works · 9 kudos", ownWorksLine("Tester", 1_204, AO3UserStats(kudos = 9)))
        assertEquals("not read, or the read failed", "12 works · Tester", ownWorksLine("Tester", 12, null))
        assertEquals("1 work · Tester", ownWorksLine("Tester", 1, AO3UserStats()))
        assertEquals("no count from AO3: the name alone, as before", "Tester", ownWorksLine("Tester", null, stats))
    }
}
