package io.github.cidy02.kudos.network.ao3.series

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3SeriesRepositoryParseTest {
    @org.junit.Before fun clearPageCache() { io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.clear() }
    @Test
    fun parsesSeriesPageBlurbsWithFixture() = runTest {
        val client = FakeSeriesClient(
            mapOf(
                "https://archiveofourown.org/series/55" to seriesResource("ao3/series/series_page.html")
            )
        )
        val repository = AO3SeriesRepository(client = client)

        val page = (repository.seriesPage("https://archiveofourown.org/series/55", page = 1)
            as AO3Result.Success).value

        assertEquals(2, page.works.size)
        assertEquals(listOf(101L, 102L), page.works.map { it.id })
        assertEquals("Series Part One", page.works[0].title)
        assertEquals("Demo Series", page.works[0].seriesTitle)
        assertEquals(1, page.works[0].seriesPosition)
        assertEquals(true, page.works[0].isComplete)
        assertEquals(false, page.works[1].isComplete)
        assertEquals(2, page.totalPages)
        assertEquals(
            "https://archiveofourown.org/series/55",
            client.requestedUrls.single()
        )
    }

    @Test
    fun seriesWorksPaginatesAcrossPages() = runTest {
        val client = FakeSeriesClient(
            mapOf(
                "https://archiveofourown.org/series/55" to seriesResource("ao3/series/series_page.html"),
                "https://archiveofourown.org/series/55?page=2" to seriesResource("ao3/series/series_page_2.html")
            )
        )
        val repository = AO3SeriesRepository(client = client)

        val works = (repository.seriesWorks("https://archiveofourown.org/series/55")
            as AO3Result.Success).value

        assertEquals(listOf(101L, 102L, 103L), works.map { it.id })
        assertEquals(
            listOf(
                "https://archiveofourown.org/series/55",
                "https://archiveofourown.org/series/55?page=2"
            ),
            client.requestedUrls
        )
    }

    @Test
    fun invalidSeriesUrlFailsValidation() = runTest {
        val repository = AO3SeriesRepository(client = FakeSeriesClient(emptyMap()))
        val result = repository.seriesWorks("https://evil.example.com/series/1")
        assertTrue((result as AO3Result.Failure).error is AO3Error.Validation)
    }

    @Test
    fun surfacesNetworkErrorsWithoutParsing() = runTest {
        val repository = AO3SeriesRepository(
            client = object : AO3Client {
                override suspend fun get(
                    url: String,
                    headers: Map<String, String>
                ): AO3Result<AO3HttpResponse> = AO3Result.Failure(AO3Error.Network("offline"))
            }
        )
        val result = repository.seriesPage("https://archiveofourown.org/series/55")
        assertEquals(AO3Error.Network("offline"), (result as AO3Result.Failure).error)
    }

    @Test fun detailIdentityComesFromSameShowReadAndNeverDisplayedPseudOrWorkByline() = runTest {
        val url = "https://archiveofourown.org/series/321"
        val html = io.github.cidy02.kudos.writing.seriesFixture("ao3_demo_dawn_series")
        val client = FakeSeriesClient(mapOf(url to html))
        // Each reader its own page cache: with the shared one, the second client's page for the same
        // address was never asked for (the first one's copy was still fresh).
        fun repository(client: AO3Client) = AO3SeriesRepository(client, pageCache = io.github.cidy02.kudos.network.ao3.AO3PageCache())
        val detail = (repository(client).detailPage(url) as AO3Result.Success).value
        assertEquals("The Dawn Cycle", detail.title)
        assertEquals(listOf("AO3_Reader"), detail.creatorUsernames)
        assertEquals(3, detail.workCount); assertEquals(45678, detail.words)
        assertEquals(listOf(url), client.requestedUrls)
        val other = FakeSeriesClient(mapOf(url to html.replace("/users/AO3_Reader/pseuds/Avery%20Writes",
            "/users/stranger/pseuds/AO3_Reader")))
        assertEquals(listOf("stranger"), (repository(other).detailPage(url) as AO3Result.Success).value.creatorUsernames)
        val summaries = io.github.cidy02.kudos.network.ao3.author.AO3AuthorParser().parseSeriesPage(
            io.github.cidy02.kudos.writing.seriesFixture("ao3_author_series"), 1).series
        assertEquals(listOf("Avery Writes"), summaries.first().creators)
        assertEquals(listOf("AO3_Reader"), summaries.first().creatorUsernames)
        assertTrue(summaries.last().creatorUsernames.isEmpty())
    }

    @Test fun signedInDetailUsesOneAuthenticatedReadWithoutAnonymousFallback() = runTest {
        val url = "https://archiveofourown.org/series/321"
        val anonymous = FakeSeriesClient(emptyMap())
        val reads = mutableListOf<String>()
        val authenticated = object : io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient {
            override fun username() = "AO3_Reader"
            override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
                reads += url; return AO3Result.Failure(AO3Error.Forbidden)
            }
            override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                error("A detail read must never post")
        }
        assertEquals(AO3Result.Failure(AO3Error.Forbidden), AO3SeriesRepository(anonymous, authenticatedClient = authenticated).detailPage(url))
        assertEquals(listOf(url), reads); assertTrue(anonymous.requestedUrls.isEmpty())
    }

    private class FakeSeriesClient(
        private val bodiesByUrl: Map<String, String>
    ) : AO3Client {
        val requestedUrls = mutableListOf<String>()

        override suspend fun get(
            url: String,
            headers: Map<String, String>
        ): AO3Result<AO3HttpResponse> {
            requestedUrls += url
            val body = bodiesByUrl[url]
                ?: return AO3Result.Failure(AO3Error.NotFound)
            return AO3Result.Success(
                AO3HttpResponse(
                    body = body,
                    statusCode = 200,
                    headers = emptyMap(),
                    url = url
                )
            )
        }
    }
}

private fun seriesResource(path: String): String {
    val resource = Thread.currentThread().contextClassLoader?.getResource(path)
        ?: error("Missing test resource: $path")
    return resource.readText()
}
