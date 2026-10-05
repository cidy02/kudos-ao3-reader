package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class SubscriptionUnsubscribeStateTest {
    @Test fun confirmationPostsOnceBusyBlocksDuplicatesAndSuccessEmptiesLaterPage() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = HeldUnsubscribeClient(auth)
        val state = SubscriptionUnsubscribeState(AO3WriteRepository(client), auth)
        val loader = NamedSubscriptionsLoader(AccountListRepository(client, auth), AO3NamedSubscriptionsScope.Series, 2)
        loader.load()
        val readsBefore = client.gets
        // Merely constructing the screen write state and loading rows never writes.
        assertEquals(0, client.posts)
        val confirmed = async {
            state.confirm("/users/me/subscriptions/987", 2) {
                assertTrue(loader.removeSubscription("/series/456"))
            }
        }
        client.postEntered.await()
        assertEquals("/users/me/subscriptions/987", state.busyPath.value)
        state.confirm("/users/me/subscriptions/987", 2) { fail("Duplicate must not apply") }
        assertEquals(1, client.posts)
        assertEquals(readsBefore + 1, client.gets)
        assertEquals(1, (loader.uiState.value as NamedSubscriptionsUiState.Loaded).page.rows.size)
        client.reply.complete(response("<div class='flash notice'>Unsubscribed.</div>"))
        confirmed.await()
        assertTrue((loader.uiState.value as NamedSubscriptionsUiState.Loaded).page.rows.isEmpty())
        assertNull(state.busyPath.value)
        assertNull(state.error.value)
    }

    @Test fun unconfirmedResponseKeepsRowsAndPublishesIosFailureDetail() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = HeldUnsubscribeClient(auth)
        val state = SubscriptionUnsubscribeState(AO3WriteRepository(client), auth)
        var removed = false
        val confirmed = async { state.confirm("/users/me/subscriptions/987", 1) { removed = true } }
        client.postEntered.await()
        client.reply.complete(response("<p>Maintenance</p>"))
        confirmed.await()
        assertFalse(removed)
        assertEquals("AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.", state.error.value)
        assertEquals(1, client.posts)
    }

    @Test fun sessionChangeDuringFreshIndexReadPreventsPost() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = HeldUnsubscribeClient(auth)
        client.getGate = CompletableDeferred()
        val state = SubscriptionUnsubscribeState(AO3WriteRepository(client), auth)
        val confirmed = async { state.confirm("/users/me/subscriptions/987", 1) { fail("Stale result applied") } }
        client.getEntered.await()
        auth.logout()
        client.getGate!!.complete(Unit)
        confirmed.await()
        assertEquals(0, client.posts)
        assertNull(state.error.value)
    }

    @Test fun logoutAfterPostDoesNotTouchListOrShowError() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = HeldUnsubscribeClient(auth)
        val state = SubscriptionUnsubscribeState(AO3WriteRepository(client), auth)
        var applied = false
        val confirmed = async { state.confirm("/users/me/subscriptions/987", 1) { applied = true } }
        client.postEntered.await()
        auth.logout()
        client.reply.complete(response("<div class='flash notice'>Unsubscribed.</div>"))
        confirmed.await()
        assertFalse(applied)
        assertNull(state.error.value)
        assertEquals(1, client.posts)
        // Old staged confirmation cannot write under a replacement session.
        state.confirm("/users/me/subscriptions/987", 1) { fail("Old screen applied") }
        assertEquals(1, client.posts)
    }

    @Test fun screenExitAfterPostDoesNotCancelSentWriteOrApplyResult() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = HeldUnsubscribeClient(auth)
        val state = SubscriptionUnsubscribeState(AO3WriteRepository(client), auth)
        var applied = false
        val confirmed = async { state.confirm("/users/me/subscriptions/987", 1) { applied = true } }
        client.postEntered.await()
        confirmed.cancel()
        client.reply.complete(response("<div class='flash notice'>Unsubscribed.</div>"))
        confirmed.join()
        assertTrue(client.postFinished)
        assertEquals(1, client.posts)
        assertFalse(applied)
    }

    @Test fun olderRefreshCannotResurrectConfirmedRemoval() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = HeldUnsubscribeClient(auth)
        val loader = NamedSubscriptionsLoader(AccountListRepository(client, auth), AO3NamedSubscriptionsScope.Series, 1)
        loader.load()
        client.getGate = CompletableDeferred()
        val refresh = async { loader.load() }
        client.getEntered.await()
        assertFalse(loader.removeSubscription("/series/456"))
        client.getGate!!.complete(Unit)
        refresh.await()
        assertTrue((loader.uiState.value as NamedSubscriptionsUiState.Loaded).page.rows.isEmpty())
    }
}

private fun response(body: String) = AO3Result.Success(AO3HttpResponse(
    "https://archiveofourown.org/users/AO3_Reader/subscriptions", 200, emptyMap(), body
))

/** This terminal client cannot reach a socket. */
private class HeldUnsubscribeClient(private val auth: AO3AuthRepository) : AO3AuthenticatedClient, AO3Client {
    var gets = 0
    var posts = 0
    var postFinished = false
    var getGate: CompletableDeferred<Unit>? = null
    val getEntered = CompletableDeferred<Unit>()
    val postEntered = CompletableDeferred<Unit>()
    val reply = CompletableDeferred<AO3Result<AO3HttpResponse>>()
    override fun username() = auth.username()
    override fun sessionGeneration() = auth.generation.value
    override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets++
        if (getGate != null) {
            getEntered.complete(Unit)
            getGate!!.await()
        }
        return response("""<meta name='csrf-token' content='fresh'>
            <dl class='subscription'><dt><a href='/series/456'>Series</a></dt>
            <dd><form action='/users/me/subscriptions/987'></form></dd></dl>""")
    }
    override suspend fun postAuthenticated(
        url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        posts++
        postEntered.complete(Unit)
        val result = reply.await()
        postFinished = true
        return result
    }
}
