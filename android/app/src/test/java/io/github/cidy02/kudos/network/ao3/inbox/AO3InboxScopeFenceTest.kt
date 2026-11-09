package io.github.cidy02.kudos.network.ao3.inbox

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3InboxScopeFenceTest {
    private class Client : AO3AuthenticatedClient {
        var name: String? = "alice"
        var generation: Int? = 1
        val sessions = MutableStateFlow(1)
        override val sessionChanges = sessions
        override fun username() = name
        override fun sessionGeneration() = generation
        override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> =
            AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), INBOX))
        override suspend fun postAuthenticated(
            url: String,
            formFields: List<Pair<String, String>>,
            headers: Map<String, String>
        ): AO3Result<AO3HttpResponse> = AO3Result.Failure(AO3Error.NotFound)
    }

    @Test
    fun switchedAccountDuringParseDoesNotPublishThePreviousUnread() = runBlocking {
        val client = Client()
        val repo = AO3InboxRepository(
            client,
            pageCache = AO3PageCache(),
            beforeInboxParse = {
                client.name = "bob"
                client.generation = 2
            }
        )
        val alice = AO3PageCache.Scope("alice", 1)
        val bob = AO3PageCache.Scope("bob", 2)
        assertNull(repo.inboxUnreadAfterFence(alice, bob, 3))
        assertEquals(alice to 3, repo.inboxUnreadAfterFence(alice, alice, 3))

        val thrown = runCatching { repo.load() }.exceptionOrNull()
        assertTrue(thrown is CancellationException)
        assertNull(repo.storedInboxUnread())
        assertNull(repo.cachedUnreadCount())
    }

    @Test
    fun laterSessionChangeClearsTheStoredUnread() = runBlocking {
        val client = Client()
        val scope = CoroutineScope(Dispatchers.Unconfined)
        val repo = AO3InboxRepository(client, pageCache = AO3PageCache(), sessionScope = scope)
        val loaded = repo.load()
        assertTrue(loaded is AO3Result.Success)
        assertEquals(3, repo.cachedUnreadCount())
        client.sessions.value = 2
        assertNull(repo.storedInboxUnread())
        scope.cancel()
    }

    private companion object {
        const val INBOX = """<html><body><h2 class="heading">My Inbox (12 comments, 3 unread)</h2></body></html>"""
    }
}
