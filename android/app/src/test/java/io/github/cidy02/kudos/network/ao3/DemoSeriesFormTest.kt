package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.*
import io.github.cidy02.kudos.writing.seriesFixture
import kotlinx.coroutines.test.runTest
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

class DemoSeriesFormTest {
    private val source = FixtureSource { name -> try { seriesFixture(name).encodeToByteArray() } catch (_: Exception) { null } }
    private fun demoHttp() = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor({ true }, { source }))
        .addInterceptor { throw AssertionError("Series demo attempted a socket") }.build()

    @Test fun actualDemoSaveRefusalAndReorderAreLocalAndPersistUntilInterceptorRestart() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()); auth.restoreSession()
        val requests = CopyOnWriteArrayList<String>()
        val http = demoHttp().newBuilder().addInterceptor { throw AssertionError("No downstream traffic") }.build()
        val client = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
        val authenticated = object : AO3AuthenticatedClient {
            private val delegate = DefaultAO3AuthenticatedClient(client, client, auth)
            override fun username() = delegate.username()
            override fun sessionGeneration() = delegate.sessionGeneration()
            override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
                requests += "GET $url"; return delegate.getAuthenticated(url)
            }
            override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                requests += "POST $url"; return delegate.postAuthenticatedInSession(url, formFields, headers, sessionGeneration())
            }
        }
        val repo = AO3SeriesFormRepository(authenticated, auth)
        val writes = AO3WriteRepository(authenticated)
        val loaded = (repo.loadForm(321) as AO3Result.Success).value
        val draft = loaded.copy(title = "A Lantern at Dawn", creators = loaded.creators.copy(coauthorByline = "friend (pseud)"))
        assertEquals(AO3Result.Success("Series was successfully updated."), writes.saveSeries(draft, auth.generation.value))
        assertEquals(listOf("GET ${AO3SeriesFormUrls.edit(321)}", "POST ${AO3SeriesFormUrls.show(321)}"), requests.toList())
        val fresh = (repo.loadForm(321) as AO3Result.Success).value
        assertEquals(draft.title, fresh.title); assertEquals("friend (pseud)", fresh.creators.coauthorByline)
        assertEquals(listOf("first", "second"), fresh.parameters().filter { it.first == "series[unknown][]" }.map { it.second })
        val refused = writes.saveSeries(draft.copy(title = "Refuse this series"), auth.generation.value)
        assertEquals(AO3Result.Failure(AO3Error.Validation("Title is too long (maximum is 255 characters)")), refused)
        assertEquals(draft.title, (repo.loadForm(321) as AO3Result.Success).value.title)
        val start = requests.size
        val order = listOf(3213L, 3211L, 3212L)
        val ordered = writes.reorderSeries(321, order, auth.generation.value) as AO3Result.Success
        assertEquals(order, ordered.value.map { it.serialWorkID })
        assertEquals(listOf("GET ${AO3SeriesFormUrls.manage(321)}", "POST ${AO3SeriesFormUrls.positions(321)}",
            "GET ${AO3SeriesFormUrls.manage(321)}"), requests.drop(start))
        val reset = OkHttpAO3Client(demoHttp(), AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
        val resetRepo = AO3SeriesFormRepository(DefaultAO3AuthenticatedClient(reset, reset, auth), auth)
        assertEquals("The Dawn Cycle", (resetRepo.loadForm(321) as AO3Result.Success).value.title)
        assertEquals(listOf(3211L, 3212L, 3213L), (resetRepo.loadManage(321) as AO3Result.Success).value.map { it.serialWorkID })
    }

    @Test fun realSharedClientNeverRetriesSeriesWritesAndUsesCookieTokenRefererAndEncodedByline() = runTest {
        for (ordering in listOf(false, true)) for (status in listOf(429, 503)) {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()); auth.restoreSession()
            val seen = CopyOnWriteArrayList<Request>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request(); seen += request
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                    .code(if (request.method == "GET") 200 else status).message("Local answer")
                    .body((if (request.method == "GET") seriesFixture("ao3_demo_series_manage") else "").toResponseBody()).build()
            }.build() // Terminal interceptor: no socket, even if incorrectly retried.
            val client = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
            val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
            val form = AO3SeriesFormParser().parse(seriesFixture("ao3_demo_series_edit"), AO3SeriesFormUrls.edit(321))
                .let { it.copy(creators = it.creators.copy(coauthorByline = "friend [dawn] & 星")) }
            if (ordering) writes.reorderSeries(321, listOf(3213, 3212, 3211), auth.generation.value)
                else writes.saveSeries(form, auth.generation.value)
            assertEquals(if (ordering) listOf("GET", "POST") else listOf("POST"), seen.map { it.method })
            val post = seen.last()
            assertTrue(post.header("Cookie").orEmpty().isNotEmpty())
            assertTrue(post.header("User-Agent").orEmpty().contains("KudosReader/"))
            assertEquals(if (ordering) "demo-series-manage-token" else "demo-series-token", post.header("X-CSRF-Token"))
            assertEquals(if (ordering) AO3SeriesFormUrls.manage(321) else form.actionUrl, post.header("Referer"))
            val buffer = okio.Buffer(); post.body!!.writeTo(buffer)
            val body = buffer.readUtf8()
            assertEquals(AO3FormEncoding.encode(if (ordering) listOf("authenticity_token" to "demo-series-manage-token",
                "serial[]" to "3213", "serial[]" to "3212", "serial[]" to "3211") else form.parameters()), body)
        }
    }

    @Test fun unsafeFormDoesNotPostAndMissingDemoAssetsFailLocally() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()); auth.restoreSession()
        val seen = CopyOnWriteArrayList<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain -> seen += chain.request(); throw AssertionError("Unexpected request") }.build()
        val client = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
        val form = AO3SeriesFormParser().parse(seriesFixture("ao3_demo_series_edit"), AO3SeriesFormUrls.edit(321))
        assertTrue(AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth)).saveSeries(
            form.copy(actionUrl = "https://archiveofourown.org.evil.test/series/321"), auth.generation.value) is AO3Result.Failure)
        assertTrue(seen.isEmpty())
        val emptyHttp = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor({ true }, { FixtureSource { null } }))
            .addInterceptor { throw AssertionError("Missing series asset reached a socket") }.build()
        emptyHttp.newCall(Request.Builder().url(AO3SeriesFormUrls.edit(321)).build()).execute().use { assertEquals(404, it.code) }
    }
}
