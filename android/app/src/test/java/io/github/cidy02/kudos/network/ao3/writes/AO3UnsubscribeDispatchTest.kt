package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Clock
import io.github.cidy02.kudos.network.ao3.AO3Delay
import io.github.cidy02.kudos.network.ao3.AO3NetworkConfig
import io.github.cidy02.kudos.network.ao3.AO3RequestCoordinator
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class AO3UnsubscribeDispatchTest {
    @Test fun sessionChangeInsideSharedPacingWaitPreventsPostDispatch() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val requests = java.util.concurrent.CopyOnWriteArrayList<String>()
        // Terminal application interceptor: no chain.proceed and no sockets, even on a bug.
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            requests.add(chain.request().method)
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK")
                .body("<meta name='csrf-token' content='fresh'>".toResponseBody()).build()
        }.build()
        val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 600)
        var paced = false
        val coordinator = AO3RequestCoordinator(config, AO3Clock { 0 }, AO3Delay {
            paced = true
            auth.logout()
        })
        val client = OkHttpAO3Client(http, config, coordinator)
        val repository = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
        try {
            repository.unsubscribe("/users/me/subscriptions/987", 1)
            fail("Stale queued write must be cancelled")
        } catch (_: CancellationException) { }
        assertTrue(paced)
        assertEquals(listOf("GET"), requests)
    }
}
