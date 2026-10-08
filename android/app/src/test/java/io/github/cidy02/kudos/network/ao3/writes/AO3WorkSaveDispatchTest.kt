package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

class AO3WorkSaveDispatchTest {
    @Test fun realSharedClientSendsIosHeadersAndEncodedBodyOnceAndNeverRetries429Or503() = runTest {
        for (code in listOf(200, 429, 503)) {
            val requests = CopyOnWriteArrayList<Request>()
            val bodies = CopyOnWriteArrayList<String>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request()
                requests += request
                val buffer = okio.Buffer(); request.body!!.writeTo(buffer); bodies += buffer.readUtf8()
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(code).message("Local answer")
                    .body("<main id=main><div class='flash notice'>Saved.</div></main>".toResponseBody()).build()
            }.build()
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()).also { it.restoreSession() }
            val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 0)
            val client = OkHttpAO3Client(http, config)
            val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
            val form = AO3WorkFormParser().parse(workFixture("ao3_demo_work_draft_edit")).copy(title = "  Stars & 星  ")
            val result = writes.saveWork(form, auth.generation.value)
            assertEquals(code == 200, result is AO3Result.Success)
            val request = requests.single()
            assertEquals("POST", request.method); assertEquals(form.actionUrl, request.url.toString())
            assertEquals(AO3UserAgent.VALUE, request.header("User-Agent"))
            assertTrue(request.header("Cookie").orEmpty().isNotEmpty())
            assertEquals(form.csrfToken, request.header("X-CSRF-Token"))
            assertEquals(form.actionUrl, request.header("Referer"))
            assertEquals("application/x-www-form-urlencoded; charset=UTF-8", request.body!!.contentType().toString())
            assertNull(request.header("X-Requested-With")); assertNull(request.header("Accept"))
            assertEquals(AO3FormEncoding.encode(form.parameters(AO3WorkSubmitAction.SaveDraft)), bodies.single())
        }
    }

    @Test fun aSessionChangeDuringSharedPacingPreventsWorkPostDispatch() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()).also { it.restoreSession() }
        val requests = CopyOnWriteArrayList<String>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            requests += chain.request().method
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("Local answer")
                .body("<main id=main></main>".toResponseBody()).build()
        }.build()
        val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 600)
        var paced = false
        val coordinator = AO3RequestCoordinator(config, AO3Clock { 0 }, AO3Delay { paced = true; auth.logout() })
        val client = OkHttpAO3Client(http, config, coordinator)
        client.get(AO3WorkFormUrls.newWork()) // Reserve the previous slot, locally only.
        val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
        val form = AO3WorkFormParser().parse(workFixture("ao3_demo_work_draft_edit"))
        try {
            writes.saveWork(form, auth.generation.value)
            fail("Stale queued write must not dispatch")
        } catch (_: CancellationException) { }
        assertTrue(paced); assertEquals(listOf("GET"), requests)
    }
}
