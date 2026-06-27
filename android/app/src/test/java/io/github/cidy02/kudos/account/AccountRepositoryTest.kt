package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountRepositoryAuthRequiredTest {
    @Test
    fun authRequiredResponseExpiresSession() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val repository = AccountListRepository(
            client = FakeAccountClient(AO3Result.Failure(AO3Error.AuthenticationRequired)),
            authRepository = auth
        )

        val result = repository.load(AccountListType.History)

        assertEquals(AO3Error.AuthenticationRequired, (result as AO3Result.Failure).error)
        assertTrue(auth.state.value is AO3AuthState.Expired)
    }
}

class AO3AuthRedirectDetectionTest {
    @Test
    fun successfulHtmlLoginPageStillExpiresSession() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val repository = AccountListRepository(
            client = FakeAccountClient(
                AO3Result.Success(
                    AO3HttpResponse(
                        url = "https://archiveofourown.org/users/login",
                        statusCode = 200,
                        headers = emptyMap(),
                        body = accountRepositoryResourceText("ao3/account/login_required.html")
                    )
                )
            ),
            authRepository = auth
        )

        val result = repository.load(AccountListType.Bookmarks)

        assertEquals(AO3Error.AuthenticationRequired, (result as AO3Result.Failure).error)
        assertTrue(auth.state.value is AO3AuthState.Expired)
    }
}

class AccountRepositoryPaginationTest {
    @Test
    fun loadsRequestedPageWithAuthenticatedCookies() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = FakeAccountClient(
            AO3Result.Success(
                AO3HttpResponse(
                    url = "https://archiveofourown.org/users/AO3_Reader/readings?page=2",
                    statusCode = 200,
                    headers = emptyMap(),
                    body = accountRepositoryResourceText("ao3/account/history.html")
                )
            )
        )
        val repository = AccountListRepository(client = client, authRepository = auth)

        val page = (repository.load(AccountListType.History, page = 2) as AO3Result.Success).value

        assertTrue(client.requestedUrl!!.endsWith("/users/AO3_Reader/readings?page=2"))
        assertTrue(client.requestHeaders!!.getValue("Cookie").contains("_otwarchive_session=secret"))
        assertEquals(2, page.currentPage)
        assertEquals(2, page.totalPages)
        assertEquals(202L, page.works.single().id)
    }
}

class AccountListItemsDoNotAutoSaveTest {
    @Test
    fun repositoryReturnsRemoteSummariesWithoutTouchingLocalStorage() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val repository = AccountListRepository(
            client = FakeAccountClient(
                AO3Result.Success(
                    AO3HttpResponse(
                        url = "https://archiveofourown.org/users/AO3_Reader/bookmarks",
                        statusCode = 200,
                        headers = emptyMap(),
                        body = accountRepositoryResourceText("ao3/account/bookmarks.html")
                    )
                )
            ),
            authRepository = auth
        )

        val page = (repository.load(AccountListType.Bookmarks) as AO3Result.Success).value

        assertEquals(303L, page.works.single().id)
        assertEquals("https://archiveofourown.org/works/303", page.works.single().workUrl)
    }
}

private class FakeAccountClient(
    private val result: AO3Result<AO3HttpResponse>
) : AO3Client {
    var requestedUrl: String? = null
    var requestHeaders: Map<String, String>? = null

    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        requestedUrl = url
        requestHeaders = headers
        return result
    }
}

private fun accountRepositoryResourceText(path: String): String {
    val resource = Thread.currentThread().contextClassLoader?.getResource(path)
        ?: error("Missing test resource: $path")
    return resource.readText()
}
