package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

/** In-memory clients only: no OkHttp, login or network fallback. */
class NamedSubscriptionsLoaderTest {
    @Test fun constructionDoesNotFetchAndSignedOutDoesNotFetch() = runTest {
        var calls = 0
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                calls++
                error("A signed-out tab must never GET")
            }
        }
        val repository = AccountListRepository(client, AO3AuthRepository(MemorySessionStore(), MemoryCookieStore()))
        val loader = NamedSubscriptionsLoader(repository, AO3NamedSubscriptionsScope.Series, 1)
        assertEquals(0, calls)
        loader.load()
        assertEquals(NamedSubscriptionsUiState.AuthRequired, loader.uiState.value)
        assertEquals(0, calls)
    }

    @Test fun answeredNoneIsLoadedEmptyAndFailureIsFailedThenRetryCanRecover() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        var fail = true
        val requests = mutableListOf<String>()
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                requests.add(url)
                assertTrue(headers.getValue("Cookie").contains("_otwarchive_session=secret"))
                return if (fail) AO3Result.Failure(AO3Error.Network("Test failure")) else
                    AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
                        "<p class='notes'>You have no subscriptions.</p>"))
            }
        }
        val loader = NamedSubscriptionsLoader(AccountListRepository(client, auth), AO3NamedSubscriptionsScope.Users, 2)
        loader.load()
        assertTrue(loader.uiState.value is NamedSubscriptionsUiState.Failed)
        fail = false
        loader.load()
        val loaded = loader.uiState.value as NamedSubscriptionsUiState.Loaded
        assertTrue(loaded.page.rows.isEmpty())
        assertEquals(2, loaded.page.currentPage)
        assertEquals(List(2) { "https://archiveofourown.org/users/AO3_Reader/subscriptions?type=users&page=2" }, requests)
    }

    @Test fun logoutDuringRequestCancelsRatherThanPublishingPrivateRows() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val entered = CompletableDeferred<Unit>()
        val reply = CompletableDeferred<AO3Result<AO3HttpResponse>>()
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                entered.complete(Unit)
                return reply.await()
            }
        }
        val loader = NamedSubscriptionsLoader(AccountListRepository(client, auth), AO3NamedSubscriptionsScope.Users, 1)
        val load = async { loader.load() }
        entered.await()
        auth.logout()
        reply.complete(AO3Result.Success(AO3HttpResponse(
            "https://archiveofourown.org/users/AO3_Reader/subscriptions?type=users", 200, emptyMap(),
            "<dl class='subscription'><dt><a href='/users/private'>Private</a></dt></dl>")))
        try {
            load.await()
            fail("Expected session cancellation")
        } catch (_: kotlinx.coroutines.CancellationException) { }
        assertFalse(loader.uiState.value is NamedSubscriptionsUiState.Loaded)
    }
}
