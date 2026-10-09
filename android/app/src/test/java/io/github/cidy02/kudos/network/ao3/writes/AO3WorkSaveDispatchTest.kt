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

    @Test fun postPreviewAndDeleteUseRealClientHeadersAndAreSingleShotOn429And503() = runTest {
        for (action in listOf("post", "preview", "delete")) for (code in listOf(200, 429, 503)) {
            val requests = CopyOnWriteArrayList<Request>()
            val bodies = CopyOnWriteArrayList<String>()
            val form = AO3WorkFormParser().parse(workFixture("ao3_demo_work_draft_edit"))
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request(); requests += request
                if (request.method == "POST") {
                    val buffer = okio.Buffer(); request.body!!.writeTo(buffer); bodies += buffer.readUtf8()
                }
                val html = if (request.method == "GET") "<main id=main><p class=caution>Delete draft?</p><form class=destroy method=post action='/works/995001'><input name=authenticity_token value=delete-token><input name=_method value=delete></form></main>"
                    else if (action == "preview") "<main id=main><div id=previewpane><h2 class=title>Preview</h2></div></main>"
                    else "<main id=main><div class='flash notice'>Confirmed.</div></main>"
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(if (request.method == "GET") 200 else code)
                    .message("Terminal local answer").body(html.toResponseBody()).build()
            }.addInterceptor { error("No work action may reach a socket in this test") }.build()
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()).also { it.restoreSession() }
            val client = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
            val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
            val result = when (action) {
                "post" -> writes.postWork(form, auth.generation.value)
                "preview" -> writes.previewWork(form, auth.generation.value)
                else -> writes.deleteWork(995001, auth.generation.value)
            }
            assertEquals(code == 200, result is AO3Result.Success)
            val post = requests.single { it.method == "POST" }
            val token = if (action == "delete") "delete-token" else form.csrfToken
            assertEquals(AO3UserAgent.VALUE, post.header("User-Agent")); assertTrue(post.header("Cookie").orEmpty().isNotEmpty())
            assertEquals(token, post.header("X-CSRF-Token")); assertEquals(form.actionUrl, post.header("Referer"))
            assertEquals("application/x-www-form-urlencoded; charset=UTF-8", post.body!!.contentType().toString())
            assertNull(post.header("X-Requested-With")); assertNull(post.header("Accept"))
            val fields = if (action == "delete") listOf("authenticity_token" to "delete-token", "_method" to "delete")
                else form.parameters(if (action == "preview") AO3WorkSubmitAction.Preview else AO3WorkSubmitAction.Post)
            assertEquals(AO3FormEncoding.encode(fields), bodies.single())
            assertEquals(if (action == "delete") 2 else 1, requests.size)
        }
    }

    @Test fun realClientSessionMovingAfterDispatchReturnsUnconfirmedForEveryWorkWrite() = runTest {
        for (action in listOf("save", "post", "preview", "delete")) for (code in listOf(200, 401)) {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()).also { it.restoreSession() }
            val requests = CopyOnWriteArrayList<String>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request(); requests += request.method
                val html = if (request.method == "GET") "<main id=main><p class=caution>Delete draft?</p><form class=destroy method=post action='/works/995001'><input name=authenticity_token value=delete-token><input name=_method value=delete></form></main>"
                    else "<main id=main><div class='flash notice'>Confirmed.</div><div id=previewpane></div></main>"
                if (request.method == "POST" && code == 200) kotlinx.coroutines.runBlocking<Unit> { auth.logout() }
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(if (request.method == "GET") 200 else code)
                    .message("Terminal local answer").body(html.toResponseBody()).build()
            }.addInterceptor { error("No work write may reach a socket") }.build()
            val client = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
            val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
            val form = AO3WorkFormParser().parse(workFixture("ao3_demo_work_draft_edit"))
            val generation = auth.generation.value
            val result = when (action) {
                "save" -> writes.saveWork(form, generation)
                "post" -> writes.postWork(form, generation)
                "preview" -> writes.previewWork(form, generation)
                else -> writes.deleteWork(995001, generation)
            }
            // A 401 is AO3 refusing the cookie, and is itself what ended the session: "session expired, log
            // in again", not "didn't confirm" (decision of 2026-10-09, audit A26).
            assertEquals(if (code == 401) AO3Result.Failure(AO3Error.AuthenticationRequired) else AO3Result.Failure(AO3Error.Validation(
                io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED)), result)
            assertEquals(if (action == "delete") listOf("GET", "POST") else listOf("POST"), requests)
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
