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
