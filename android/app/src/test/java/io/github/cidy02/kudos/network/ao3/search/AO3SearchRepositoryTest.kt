package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchRepositoryTest {
    @Test
    fun buildsUrlCallsClientAndParsesPage() = runTest {
        val client = FakeAO3Client(
            AO3Result.Success(
                AO3HttpResponse(
                    body = repositoryResourceText("ao3/search_basic.html"),
                    statusCode = 200,
                    headers = emptyMap(),
                    url = "https://archiveofourown.org/works/search?page=1"
                )
            )
        )
        val repository = AO3SearchRepository(client = client)

        val result = repository.search(
            filters = AO3SearchFilters(query = "found family", sort = AO3SearchSort.HITS),
            page = 3
        )

        val page = (result as AO3Result.Success).value
        assertEquals(1, page.works.size)
        assertEquals(12345L, page.works.first().id)
        assertTrue(client.requestedUrl!!.contains("work_search%5Bquery%5D=found%20family"))
        assertTrue(client.requestedUrl!!.contains("work_search%5Bsort_column%5D=hits"))
        assertTrue(client.requestedUrl!!.contains("page=3"))
    }

    @Test
    fun surfacesNetworkErrorsWithoutParsing() = runTest {
        val repository = AO3SearchRepository(
            client = FakeAO3Client(AO3Result.Failure(AO3Error.Network("offline")))
        )

        val result = repository.search(AO3SearchFilters(query = "test"))

        assertEquals(AO3Error.Network("offline"), (result as AO3Result.Failure).error)
    }

    @Test
    fun mapsParserOverloadToTypedAo3Error() = runTest {
        val repository = AO3SearchRepository(
            client = FakeAO3Client(
                AO3Result.Success(
                    AO3HttpResponse(
                        body = repositoryResourceText("ao3/search_overload.html"),
                        statusCode = 200,
                        headers = emptyMap(),
                        url = "https://archiveofourown.org/works/search?page=1"
                    )
                )
            )
        )

        val result = repository.search(AO3SearchFilters(query = "test"))

        assertTrue((result as AO3Result.Failure).error is AO3Error.Overloaded)
    }

    @Test
    fun authenticatedClientSuccessBypassesPublicClient() = runTest {
        val successResponse = AO3Result.Success(
            AO3HttpResponse(
                body = repositoryResourceText("ao3/search_basic.html"),
                statusCode = 200,
                headers = emptyMap(),
                url = "https://archiveofourown.org/works/search?page=1"
            )
        )
        val authenticatedClient = FakeAuthenticatedClient(successResponse)
        val publicClient = FakeAO3Client(AO3Result.Failure(AO3Error.Network("should not be called")))
        val repository = AO3SearchRepository(client = publicClient, authenticatedClient = authenticatedClient)

        val result = repository.search(AO3SearchFilters(query = "found family"))

        val page = (result as AO3Result.Success).value
        assertEquals(1, page.works.size)
        assertEquals(12345L, page.works.first().id)
        assertEquals(null, publicClient.requestedUrl)
    }

    @Test
    fun authenticatedClientFailureFallsBackToPublicClient() = runTest {
        val authFailure = AO3Result.Failure(AO3Error.AuthenticationRequired)
        val authenticatedClient = FakeAuthenticatedClient(authFailure)
        val successResponse = AO3Result.Success(
            AO3HttpResponse(
                body = repositoryResourceText("ao3/search_basic.html"),
                statusCode = 200,
                headers = emptyMap(),
                url = "https://archiveofourown.org/works/search?page=1"
            )
        )
        val publicClient = FakeAO3Client(successResponse)
        val repository = AO3SearchRepository(client = publicClient, authenticatedClient = authenticatedClient)

        val result = repository.search(AO3SearchFilters(query = "found family"))

        val page = (result as AO3Result.Success).value
        assertEquals(1, page.works.size)
        assertEquals(12345L, page.works.first().id)
        assertTrue(publicClient.requestedUrl!!.contains("work_search%5Bquery%5D=found%20family"))
    }

    private class FakeAO3Client(
        private val result: AO3Result<AO3HttpResponse>
    ) : AO3Client {
        var requestedUrl: String? = null

        override suspend fun get(
            url: String,
            headers: Map<String, String>
        ): AO3Result<AO3HttpResponse> {
            requestedUrl = url
            return result
        }
    }

    private class FakeAuthenticatedClient(
        private val result: AO3Result<AO3HttpResponse>
    ) : io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient {
        override fun username() = null
        override suspend fun getAuthenticated(url: String) = result
        override suspend fun postAuthenticated(
            url: String,
            formFields: List<Pair<String, String>>,
            headers: Map<String, String>
        ) = error("not used in this test")
    }
}

private fun repositoryResourceText(path: String): String {
    val resource = Thread.currentThread().contextClassLoader?.getResource(path)
        ?: error("Missing test resource: $path")
    return resource.readText()
}
