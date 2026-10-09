package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class AO3ChapterDispatchTest {
    @Test fun realSharedClientSendsExactChapterBytesHeadersAndOnePostFor429And503() = runTest {
        for (code in listOf(200, 429, 503)) {
            val requests = mutableListOf<Request>(); val bodies = mutableListOf<String>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                requests += chain.request()
                bodies += okio.Buffer().also { chain.request().body!!.writeTo(it) }.readUtf8()
                Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(code).message("Local")
                    .body("<main id=main><div class='flash notice'>Saved.</div></main>".toResponseBody()).build()
            }.build()
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()).also { it.restoreSession() }
            val client = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
            val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
            val form = AO3ChapterFormParser().parse(workFixture("ao3_demo_chapter_995006_new"), AO3ChapterUrls.form(995006, null))
                .copy(title = "  海 & Stars  ")
            val result = writes.saveChapter(form, AO3WorkSubmitAction.PostWithoutPreview, auth.generation.value)
            assertEquals(code == 200, result is AO3Result.Success)
            val sent = requests.single()
            assertEquals("POST", sent.method); assertEquals(form.actionUrl, sent.url.toString())
            assertEquals(AO3FormEncoding.encode(form.parameters(AO3WorkSubmitAction.PostWithoutPreview)), bodies.single())
            assertEquals(AO3UserAgent.VALUE, sent.header("User-Agent")); assertTrue(sent.header("Cookie").orEmpty().isNotEmpty())
            assertEquals(form.csrfToken, sent.header("X-CSRF-Token")); assertEquals(form.actionUrl, sent.header("Referer"))
            assertEquals("application/x-www-form-urlencoded; charset=UTF-8", sent.body!!.contentType().toString())
            assertNull(sent.header("X-Requested-With")); assertNull(sent.header("Accept"))
        }
    }

    @Test fun sessionChangeInSharedPacingPreventsChapterDispatch() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()).also { it.restoreSession() }
        val methods = mutableListOf<String>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            methods += chain.request().method
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("Local")
                .body("<main></main>".toResponseBody()).build()
        }.build()
        val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 600)
        val coordinator = AO3RequestCoordinator(config, AO3Clock { 0 }, AO3Delay { auth.logout() })
        val client = OkHttpAO3Client(http, config, coordinator)
        client.get(AO3WorkFormUrls.newWork())
        val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
        val form = AO3ChapterFormParser().parse(workFixture("ao3_demo_chapter_995006_new"), AO3ChapterUrls.form(995006, null))
        try { writes.saveChapter(form, AO3WorkSubmitAction.SaveDraft, auth.generation.value); fail("Old session must not send") }
        catch (_: CancellationException) { }
        assertEquals(listOf("GET"), methods)
    }
}
