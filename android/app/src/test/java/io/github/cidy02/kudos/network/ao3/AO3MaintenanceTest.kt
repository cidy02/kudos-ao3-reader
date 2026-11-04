package io.github.cidy02.kudos.network.ao3

import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for AO3's "The archive is down for maintenance." page detection,
 * non-retry policy, and pacer 60 s hold off the network (port of iOS `AO3MaintenanceTests`).
 */
class AO3MaintenanceTest {

    private fun fixture(name: String): String {
        val stream = checkNotNull(
            javaClass.classLoader?.getResourceAsStream("ao3/$name.html")
        ) { "Fixture not found: ao3/$name.html" }
        return stream.bufferedReader().use { it.readText() }
    }

    @Test
    fun theCapturedMaintenancePageIsRecognised() {
        val text = fixture("maintenance")
        assertTrue(AO3Client.isMaintenancePage(text))
        assertTrue(AO3Client.isMaintenancePage(text.toByteArray(Charsets.UTF_8)))
    }

    @Test
    fun ordinaryAO3PagesAreNot() {
        val search = fixture("search_basic")
        assertFalse(AO3Client.isMaintenancePage(search))
        assertFalse(AO3Client.isMaintenancePage("<h2>Request temporarily denied.</h2>"))
        assertFalse(AO3Client.isMaintenancePage("<html><body><h1>Welcome</h1></body></html>"))
    }

    /**
     * A rejected comment or form comes back with the reader's own words in it, escaped.
     */
    @Test
    fun echoedReaderTextIsNotTheMaintenancePage() {
        val echoed = listOf(
            "<textarea>I wrote this while the archive is down for maintenance.</textarea>",
            "<p>&lt;h2&gt;The archive is down for maintenance.&lt;/h2&gt;</p>",
            "<div>The archive is down for maintenance.</div>"
        )
        for (body in echoed) {
            assertFalse(AO3Client.isMaintenancePage(body))
            assertFalse(AO3Client.isMaintenancePage(body.toByteArray(Charsets.UTF_8)))
        }
    }

    @Test
    fun successful2xxResponseWithMaintenanceWordsIsNotMaintenanceError() = runTest {
        withServer { server ->
            // A story whose chapter contains "<h2>The archive is down for maintenance.</h2>"
            // must NOT fail if served with HTTP 200. Only non-2xx answers check isMaintenancePage.
            server.enqueue(
                MockResponse.Builder()
                    .code(200)
                    .body("<h2>The archive is down for maintenance.</h2>")
                    .build()
            )
            val client = makeTestClient()
            val result = client.get(server.url("/works/123").toString())
            assertTrue(result is AO3Result.Success)
        }
    }

    @Test
    fun maintenanceIsNotRetriedButKeptCopiesMayShow() {
        val policy = AO3RetryPolicy()
        assertFalse(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.Maintenance, 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.POST, AO3Error.Maintenance, 1))
        assertTrue(AO3Error.Maintenance.allowsPageFallback())
        assertTrue(AO3Error.Maintenance.displayMessage().contains("down for maintenance"))
        assertEquals(
            "AO3 is down for maintenance. Your saved works still open. Try AO3 again later.",
            AO3Error.Maintenance.displayMessage()
        )
    }

    @Test
    fun oneMaintenanceAnswerHoldsTheNextRequestsOffTheNetwork() = runTest {
        withServer { server ->
            // Cloudflare served maintenance as HTTP 418 on 2026-11-03
            val maintenanceHtml = fixture("maintenance")
            server.enqueue(
                MockResponse.Builder()
                    .code(418)
                    .body(maintenanceHtml)
                    .build()
            )

            val client = makeTestClient()
            val paths = listOf("/works/1", "/works/2", "/media")

            for (path in paths) {
                val result = client.get(server.url(path).toString())
                assertTrue(
                    "Expected Failure(Maintenance) for $path but got $result",
                    result is AO3Result.Failure && result.error == AO3Error.Maintenance
                )
            }

            // The first request met the page; the hold answered the other two locally.
            assertEquals(1, server.requestCount)
        }
    }

    @Test
    fun pullToRefreshAsksAO3AgainDuringTheHold() = runTest {
        withServer { server ->
            val maintenanceHtml = fixture("maintenance")
            server.enqueue(MockResponse.Builder().code(418).body(maintenanceHtml).build())
            server.enqueue(MockResponse.Builder().code(200).body("recovered").build())

            val client = makeTestClient()
            val first = client.get(server.url("/works/1").toString())
            assertEquals(AO3Result.Failure(AO3Error.Maintenance), first)
            assertEquals(1, server.requestCount)

            // Second request fails under the hold without reaching the network.
            val second = client.get(server.url("/works/2").toString())
            assertEquals(AO3Result.Failure(AO3Error.Maintenance), second)
            assertEquals(1, server.requestCount)

            // Pull to refresh lifts the hold for one probe.
            client.invalidateCachedResponses()
            val third = client.get(server.url("/works/3").toString())
            assertTrue(third is AO3Result.Success)
            assertEquals("recovered", (third as AO3Result.Success).value.body)
            assertEquals(2, server.requestCount)
        }
    }

    @Test
    fun writesDetectMaintenanceBefore429() = runTest {
        withServer { server ->
            val maintenanceHtml = fixture("maintenance")
            server.enqueue(
                MockResponse.Builder()
                    .code(418)
                    .addHeader("Retry-After", "120")
                    .body(maintenanceHtml)
                    .build()
            )

            val client = makeTestClient()
            val result = client.postForm(
                server.url("/works/1/kudos").toString(),
                listOf("work_id" to "1"),
                emptyMap()
            )

            assertTrue(
                "Write must detect Maintenance, not RateLimited/429",
                result is AO3Result.Failure && result.error == AO3Error.Maintenance
            )
            // A write must never be retried
            assertEquals(1, server.requestCount)

            // Subsequent request is held off the network
            val next = client.get(server.url("/works/2").toString())
            assertEquals(AO3Result.Failure(AO3Error.Maintenance), next)
            assertEquals(1, server.requestCount)
        }
    }

    @Test
    fun epubDownloadDetectsMaintenance() = runTest {
        withServer { server ->
            val maintenanceHtml = fixture("maintenance")
            server.enqueue(
                MockResponse.Builder()
                    .code(418)
                    .body(maintenanceHtml)
                    .build()
            )

            val client = makeTestClient()
            val result = client.getBytes(server.url("/downloads/123/test.epub").toString())
            assertEquals(AO3Result.Failure(AO3Error.Maintenance), result)
            assertEquals(1, server.requestCount)

            // Subsequent download is held off the network
            val next = client.getBytes(server.url("/downloads/456/test2.epub").toString())
            assertEquals(AO3Result.Failure(AO3Error.Maintenance), next)
            assertEquals(1, server.requestCount)
        }
    }

    @Test
    fun holdExpiryAllowsProbingAgain() = runTest {
        withServer { server ->
            val maintenanceHtml = fixture("maintenance")
            server.enqueue(MockResponse.Builder().code(418).body(maintenanceHtml).build())
            server.enqueue(MockResponse.Builder().code(200).body("recovered").build())

            val fakeClock = FakeTestClock(now = 1_000_000L)
            val client = makeTestClient(clock = fakeClock)

            val first = client.get(server.url("/works/1").toString())
            assertEquals(AO3Result.Failure(AO3Error.Maintenance), first)
            assertEquals(1, server.requestCount)

            // Within 60 seconds (e.g. 30s), it is still held
            fakeClock.now += 30_000L
            val second = client.get(server.url("/works/2").toString())
            assertEquals(AO3Result.Failure(AO3Error.Maintenance), second)
            assertEquals(1, server.requestCount)

            // After 60 seconds (60_001ms), the hold has expired and next request probes
            fakeClock.now += 30_001L
            val third = client.get(server.url("/works/3").toString())
            assertTrue(third is AO3Result.Success)
            assertEquals(2, server.requestCount)
        }
    }

    @Test
    fun pacerHoldCheckedAfterPacerWait() = runTest {
        withServer { server ->
            val maintenanceHtml = fixture("maintenance")
            server.enqueue(MockResponse.Builder().code(418).body(maintenanceHtml).build())

            val fakeClock = FakeTestClock()
            val waits = AdvancingTestDelay(fakeClock)
            val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 600, maxConcurrentRequests = 2)
            val coordinator = AO3RequestCoordinator(config = config, clock = fakeClock, delay = waits)
            val client = makeTestClient(config = config, coordinator = coordinator, clock = fakeClock)

            // First request meets maintenance
            val first = client.get(server.url("/works/1").toString())
            assertEquals(AO3Result.Failure(AO3Error.Maintenance), first)

            // Second request: spacing wait occurs, then throwIfHeldForMaintenance prevents the call
            val second = client.get(server.url("/works/2").toString())
            assertEquals(AO3Result.Failure(AO3Error.Maintenance), second)
            assertEquals(1, server.requestCount)
        }
    }

    private fun makeTestClient(
        config: AO3NetworkConfig = AO3NetworkConfig(
            maxRetries = 2,
            minDelayBetweenRequestsMillis = 0
        ),
        clock: AO3Clock = SystemAO3Clock,
        coordinator: AO3RequestCoordinator = AO3RequestCoordinator(config = config, clock = clock)
    ): OkHttpAO3Client {
        return OkHttpAO3Client(
            okHttpClient = OkHttpClient.Builder()
                .followRedirects(true)
                .build(),
            config = config,
            coordinator = coordinator,
            coalescer = AO3RequestCoalescer(),
            retryPolicy = AO3RetryPolicy(config),
            isAllowedUrl = { true }
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

    private class FakeTestClock(var now: Long = 0L) : AO3Clock {
        override fun nowMillis(): Long = now
    }

    private class AdvancingTestDelay(private val clock: FakeTestClock) : AO3Delay {
        val delays = mutableListOf<Long>()
        override suspend fun delay(millis: Long) {
            delays += millis
            clock.now += millis
        }
    }
}
