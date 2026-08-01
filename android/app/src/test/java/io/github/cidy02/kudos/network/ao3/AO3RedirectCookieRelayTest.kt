package io.github.cidy02.kudos.network.ao3

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure unit tests mirror Apple `AO3RedirectCookieRelayTests` (hig-review).
 * MockWebServer cases cover interceptor wiring: merge on same-host, strip off-host.
 */
class AO3RedirectCookieRelayMergedHeaderTest {
    private val url = "https://archiveofourown.org/works/1/comments".toHttpUrl()

    @Test
    fun replacesOnlyTheSessionCookiesValueLeavingOthersUntouched() {
        val current = "_otwarchive_session=stale-value; other_cookie=unchanged"
        val setCookies = listOf("_otwarchive_session=fresh-value-with-flash; path=/")

        val merged = AO3RedirectCookieRelay.mergedCookieHeader(current, setCookies, url)

        assertTrue(merged != null)
        assertTrue(merged!!.contains("_otwarchive_session=fresh-value-with-flash"))
        assertFalse(merged.contains("stale-value"))
        assertTrue(merged.contains("other_cookie=unchanged"))
    }

    @Test
    fun appendsTheSessionCookieWhenTheCurrentHeaderDidNotHaveOne() {
        val current = "other_cookie=unchanged"
        val setCookies = listOf("_otwarchive_session=fresh; path=/")

        val merged = AO3RedirectCookieRelay.mergedCookieHeader(current, setCookies, url)

        assertEquals("other_cookie=unchanged; _otwarchive_session=fresh", merged)
    }

    @Test
    fun returnsNullWhenTheResponseSetsNoSessionCookie() {
        val current = "_otwarchive_session=stale-value"
        val setCookies = listOf("unrelated_cookie=123; path=/")

        assertNull(
            AO3RedirectCookieRelay.mergedCookieHeader(current, setCookies, url)
        )
    }

    @Test
    fun returnsNullWhenThereIsNoExistingHeaderToUpdate() {
        val setCookies = listOf("_otwarchive_session=fresh; path=/")
        assertNull(AO3RedirectCookieRelay.mergedCookieHeader(null, setCookies, url))
        assertNull(AO3RedirectCookieRelay.mergedCookieHeader("", setCookies, url))
    }

    @Test
    fun returnsNullWhenThereIsNoURLToResolveCookiesAgainst() {
        val setCookies = listOf("_otwarchive_session=fresh; path=/")
        assertNull(
            AO3RedirectCookieRelay.mergedCookieHeader(
                "_otwarchive_session=stale",
                setCookies,
                responseUrl = null
            )
        )
    }

    @Test
    fun handlesMultipleUnrelatedExistingCookiePairs() {
        val current = "cf_clearance=cf1; _otwarchive_session=stale; __cf_bm=cf2"
        val setCookies = listOf("_otwarchive_session=fresh-flash-bearing; path=/")

        val merged = AO3RedirectCookieRelay.mergedCookieHeader(current, setCookies, url)

        assertTrue(merged!!.contains("cf_clearance=cf1"))
        assertTrue(merged.contains("__cf_bm=cf2"))
        assertTrue(merged.contains("_otwarchive_session=fresh-flash-bearing"))
        assertFalse(merged.contains("stale"))
    }
}

class AO3RedirectCookieRelayActionTest {
    private val url = "https://archiveofourown.org/works/1/comments".toHttpUrl()

    @Test
    fun stripsTheCookieHeaderWhenTheRedirectLeavesAO3() {
        val setCookies = listOf("_otwarchive_session=fresh-with-flash; path=/")
        val action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader = "_otwarchive_session=live-session-value",
            setCookieHeaders = setCookies,
            responseUrl = url,
            newRequestUrl = "https://attacker.example.com/".toHttpUrl()
        )
        assertEquals(AO3RedirectCookieRelay.RedirectCookieAction.Strip, action)
    }

    @Test
    fun stripsWhenTheRedirectTargetIsNotHTTPS() {
        val action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader = "_otwarchive_session=live-session-value",
            setCookieHeaders = emptyList(),
            responseUrl = url,
            newRequestUrl = "http://archiveofourown.org/".toHttpUrl()
        )
        assertEquals(AO3RedirectCookieRelay.RedirectCookieAction.Strip, action)
    }

    @Test
    fun stripsWhenThereIsNoRedirectTargetURLAtAll() {
        val action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader = "_otwarchive_session=live-session-value",
            setCookieHeaders = emptyList(),
            responseUrl = url,
            newRequestUrl = null
        )
        assertEquals(AO3RedirectCookieRelay.RedirectCookieAction.Strip, action)
    }

    @Test
    fun setsTheRefreshedCookieWhenTheRedirectStaysOnAO3() {
        val setCookies = listOf("_otwarchive_session=fresh-with-flash; path=/")
        val action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader = "_otwarchive_session=stale; other_cookie=unchanged",
            setCookieHeaders = setCookies,
            responseUrl = url,
            newRequestUrl = "https://archiveofourown.org/works/1".toHttpUrl()
        )
        assertEquals(
            AO3RedirectCookieRelay.RedirectCookieAction.Set(
                "_otwarchive_session=fresh-with-flash; other_cookie=unchanged"
            ),
            action
        )
    }

    @Test
    fun setsTheRefreshedCookieWhenTheRedirectStaysOnAnAO3Subdomain() {
        val setCookies = listOf("_otwarchive_session=fresh; path=/")
        val action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader = "_otwarchive_session=stale",
            setCookieHeaders = setCookies,
            responseUrl = url,
            newRequestUrl = "https://download.archiveofourown.org/works/1".toHttpUrl()
        )
        assertEquals(
            AO3RedirectCookieRelay.RedirectCookieAction.Set("_otwarchive_session=fresh"),
            action
        )
    }

    @Test
    fun leavesTheHeaderUnchangedWhenAO3RedirectSetsNoSessionCookie() {
        val action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader = "_otwarchive_session=stale; other_cookie=unchanged",
            setCookieHeaders = emptyList(),
            responseUrl = url,
            newRequestUrl = "https://archiveofourown.org/works/1".toHttpUrl()
        )
        assertEquals(AO3RedirectCookieRelay.RedirectCookieAction.LeaveUnchanged, action)
    }

    @Test
    fun isTrustedUrlRequiresHttpsAo3Hosts() {
        assertTrue(AO3RedirectCookieRelay.isTrustedUrl("https://archiveofourown.org/works/1"))
        assertTrue(AO3RedirectCookieRelay.isTrustedUrl("https://www.archiveofourown.org/"))
        assertTrue(AO3RedirectCookieRelay.isTrustedUrl("https://download.archiveofourown.org/x"))
        assertFalse(AO3RedirectCookieRelay.isTrustedUrl("http://archiveofourown.org/"))
        assertFalse(AO3RedirectCookieRelay.isTrustedUrl("https://example.com/"))
        assertFalse(AO3RedirectCookieRelay.isTrustedUrl(null as String?))
    }
}

class AO3RedirectCookieRelayInterceptorTest {
    @Test
    fun mergesSessionCookieOnSameHostRedirect() = runTest {
        withServer { server ->
            val trust: (HttpUrl?) -> Boolean = { url ->
                url != null && url.host == server.hostName
            }
            server.enqueue(
                MockResponse.Builder()
                    .code(302)
                    .addHeader("Location", server.url("/works/1").toString())
                    .addHeader("Set-Cookie", "_otwarchive_session=fresh-with-flash; path=/")
                    .build()
            )
            server.enqueue(MockResponse.Builder().code(200).body("ok-after-redirect").build())

            val client = relayClient(trust)
            val result = client.get(
                server.url("/works/1/comments").toString(),
                mapOf("Cookie" to "_otwarchive_session=stale; other_cookie=unchanged")
            )

            assertEquals("ok-after-redirect", (result as AO3Result.Success).value.body)
            assertEquals(2, server.requestCount)

            val first = server.takeRequest(1, TimeUnit.SECONDS)
            assertEquals(
                "_otwarchive_session=stale; other_cookie=unchanged",
                first?.headers?.get("Cookie")
            )

            val second = server.takeRequest(1, TimeUnit.SECONDS)
            assertEquals("GET", second?.method)
            assertEquals("/works/1", second?.url?.encodedPath)
            val followCookie = second?.headers?.get("Cookie")
            assertTrue(followCookie!!.contains("_otwarchive_session=fresh-with-flash"))
            assertTrue(followCookie.contains("other_cookie=unchanged"))
            assertFalse(followCookie.contains("stale"))
        }
    }

    @Test
    fun stripsCookieWhenRedirectLeavesTrustedHost() = runTest {
        val origin = MockWebServer()
        val attacker = MockWebServer()
        origin.start()
        attacker.start()
        try {
            // Only the origin host:port is trusted — redirect target must strip Cookie.
            val trust: (HttpUrl?) -> Boolean = { url ->
                url != null && url.host == origin.hostName && url.port == origin.port
            }
            origin.enqueue(
                MockResponse.Builder()
                    .code(302)
                    .addHeader("Location", attacker.url("/steal").toString())
                    .addHeader("Set-Cookie", "_otwarchive_session=fresh; path=/")
                    .build()
            )
            attacker.enqueue(MockResponse.Builder().code(200).body("stolen").build())

            val config = AO3NetworkConfig(maxRetries = 0, minDelayBetweenRequestsMillis = 0)
            val client = OkHttpAO3Client(
                okHttpClient = OkHttpClient.Builder()
                    .followRedirects(false)
                    .followSslRedirects(false)
                    .addInterceptor(AO3RedirectCookieRelayInterceptor(isTrusted = trust))
                    .build(),
                config = config,
                coordinator = AO3RequestCoordinator(config = config, delay = NoDelay),
                delay = NoDelay
            )

            val result = client.get(
                origin.url("/works/1").toString(),
                mapOf("Cookie" to "_otwarchive_session=live-session-value")
            )

            assertEquals("stolen", (result as AO3Result.Success).value.body)
            val follow = attacker.takeRequest(1, TimeUnit.SECONDS)
            assertNull(follow?.headers?.get("Cookie"))
        } finally {
            origin.close()
            attacker.close()
        }
    }

    @Test
    fun leavesCookieUnchangedWhenRedirectSetsNoSessionCookie() = runTest {
        withServer { server ->
            val trust: (HttpUrl?) -> Boolean = { url ->
                url != null && url.host == server.hostName
            }
            server.enqueue(
                MockResponse.Builder()
                    .code(302)
                    .addHeader("Location", server.url("/works/1").toString())
                    .build()
            )
            server.enqueue(MockResponse.Builder().code(200).body("ok").build())

            val result = relayClient(trust).get(
                server.url("/works/1/comments").toString(),
                mapOf("Cookie" to "_otwarchive_session=stale; other_cookie=unchanged")
            )

            assertEquals("ok", (result as AO3Result.Success).value.body)
            server.takeRequest(1, TimeUnit.SECONDS) // first
            val second = server.takeRequest(1, TimeUnit.SECONDS)
            assertEquals(
                "_otwarchive_session=stale; other_cookie=unchanged",
                second?.headers?.get("Cookie")
            )
        }
    }

    @Test
    fun postRedirectConvertsToGetAndMergesSessionCookie() = runTest {
        withServer { server ->
            val trust: (HttpUrl?) -> Boolean = { url ->
                url != null && url.host == server.hostName
            }
            server.enqueue(
                MockResponse.Builder()
                    .code(302)
                    .addHeader("Location", server.url("/works/1").toString())
                    .addHeader("Set-Cookie", "_otwarchive_session=flash-bearing; path=/")
                    .build()
            )
            server.enqueue(MockResponse.Builder().code(200).body("<p class=\"flash notice\">ok</p>").build())

            val result = relayClient(trust).postForm(
                server.url("/works/1/comments").toString(),
                formFields = listOf("comment[content]" to "hi"),
                headers = mapOf("Cookie" to "_otwarchive_session=stale")
            )

            assertTrue(result is AO3Result.Success)
            server.takeRequest(1, TimeUnit.SECONDS) // POST
            val follow = server.takeRequest(1, TimeUnit.SECONDS)
            assertEquals("GET", follow?.method)
            assertEquals("_otwarchive_session=flash-bearing", follow?.headers?.get("Cookie"))
        }
    }

    private fun relayClient(trust: (HttpUrl?) -> Boolean): OkHttpAO3Client {
        val config = AO3NetworkConfig(maxRetries = 0, minDelayBetweenRequestsMillis = 0)
        return OkHttpAO3Client(
            okHttpClient = OkHttpClient.Builder()
                .followRedirects(false)
                .followSslRedirects(false)
                .addInterceptor(AO3RedirectCookieRelayInterceptor(isTrusted = trust))
                .build(),
            config = config,
            coordinator = AO3RequestCoordinator(config = config, delay = NoDelay),
            delay = NoDelay
        )
    }

    private inline fun withServer(block: (MockWebServer) -> Unit) {
        val server = MockWebServer()
        server.start()
        try {
            block(server)
        } finally {
            server.close()
        }
    }

    private object NoDelay : AO3Delay {
        override suspend fun delay(millis: Long) = Unit
    }
}
