package io.github.cidy02.kudos.network.ao3

import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3RetryAfterTest {
    @Test
    fun parsesSecondsAndHttpDate() {
        val now = Instant.parse("2026-06-26T12:00:00Z")

        assertEquals(2_000L, AO3RetryAfter.parseMillis("2", now))
        assertEquals(5_000L, AO3RetryAfter.parseMillis("Fri, 26 Jun 2026 12:00:05 GMT", now))
        assertEquals(0L, AO3RetryAfter.parseMillis("Fri, 26 Jun 2026 11:59:59 GMT", now))
        assertEquals(null, AO3RetryAfter.parseMillis("not a retry header", now))
    }
}

class AO3RetryPolicyTest {
    private val policy = AO3RetryPolicy(AO3NetworkConfig(maxRetries = 2))

    @Test
    fun retriesOnlyTransientGetFailuresWithinMaxRetries() {
        assertTrue(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.Network("offline"), 1))
        assertTrue(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.RateLimited(null), 1))
        assertTrue(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.Server(503), 2))
        assertTrue(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.Overloaded(200, null), 2))

        assertFalse(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.NotFound, 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.Forbidden, 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.AuthenticationRequired, 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.Server(503), 3))
    }

    @Test
    fun neverRetriesPostEvenForTransientFailures() {
        assertFalse(policy.shouldRetry(AO3HttpMethod.POST, AO3Error.Server(503), 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.POST, AO3Error.RateLimited(1_000), 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.POST, AO3Error.Network("timeout"), 1))
    }

    @Test
    fun retryDelayUsesBackoffAndHonorsRetryAfterMinimum() {
        assertEquals(500L, policy.retryDelayMillis(AO3Error.Server(500), 1))
        assertEquals(1_000L, policy.retryDelayMillis(AO3Error.Server(500), 2))
        assertEquals(3_000L, policy.retryDelayMillis(AO3Error.RateLimited(3_000L), 1))
        assertEquals(1_000L, policy.retryDelayMillis(AO3Error.RateLimited(200L), 2))
    }
}

class AO3RequestCoordinatorTest {
    @Test
    fun defaultConfigMatchesAppleThreeSlotPolicy() {
        assertEquals(3, AO3NetworkConfig().maxConcurrentRequests)
    }

    @Test
    fun neverExceedsConfiguredConcurrency() = runTest {
        val coordinator = AO3RequestCoordinator(
            config = AO3NetworkConfig(maxConcurrentRequests = 3, minDelayBetweenRequestsMillis = 0)
        )
        var running = 0
        var peak = 0

        val jobs = List(12) {
            async {
                coordinator.coordinate {
                    running += 1
                    peak = maxOf(peak, running)
                    delay(10)
                    running -= 1
                }
            }
        }
        jobs.forEach { it.await() }

        assertTrue(peak <= 3)
        assertTrue(peak >= 2)
    }

    @Test
    fun appliesMinimumDelayBetweenRequestStarts() = runTest {
        val clock = FakeClock()
        val delay = AdvancingDelay(clock)
        val coordinator = AO3RequestCoordinator(
            config = AO3NetworkConfig(maxConcurrentRequests = 1, minDelayBetweenRequestsMillis = 500),
            clock = clock,
            delay = delay
        )

        coordinator.coordinate { "first" }
        coordinator.coordinate { "second" }

        assertEquals(listOf(500L), delay.delays)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class AO3RequestCoalescerTest {
    @Test
    fun identicalConcurrentRequestsShareOneOperationAndThenEvict() = runTest {
        val coalescer = AO3RequestCoalescer<String, String>(this)
        val release = CompletableDeferred<Unit>()
        var calls = 0

        val first = async {
            coalescer.coalesce("same") {
                calls += 1
                release.await()
                "shared"
            }
        }
        runCurrent()
        val second = async {
            coalescer.coalesce("same") {
                calls += 1
                "not used"
            }
        }
        runCurrent()

        assertEquals(1, calls)
        release.complete(Unit)
        assertEquals("shared", first.await())
        assertEquals("shared", second.await())
        assertEquals(0, coalescer.inFlightCount())

        assertEquals("fresh", coalescer.coalesce("same") {
            calls += 1
            "fresh"
        })
        assertEquals(2, calls)
    }

    @Test
    fun differentKeysDoNotCoalesce() = runTest {
        val coalescer = AO3RequestCoalescer<String, String>(this)
        var calls = 0

        val first = async {
            coalescer.coalesce("one") {
                calls += 1
                "one"
            }
        }
        val second = async {
            coalescer.coalesce("two") {
                calls += 1
                "two"
            }
        }
        runCurrent()

        assertEquals("one", first.await())
        assertEquals("two", second.await())
        assertEquals(2, calls)
    }
}

class AO3ClientStatusMappingTest {
    @Test
    fun successfulGetReturnsRawBodyStatusAndHeaders() = runTest {
        withServer { server ->
            server.enqueue(
                MockResponse.Builder()
                    .code(200)
                    .addHeader("X-Kudos", "yes")
                    .body("hello AO3")
                    .build()
            )

            val result = testClient().get(server.url("/works/search").toString())

            val response = (result as AO3Result.Success).value
            assertEquals(200, response.statusCode)
            assertEquals("hello AO3", response.body)
            assertEquals("yes", response.header("X-Kudos"))
        }
    }

    @Test
    fun mapsNonRetryableHttpStatuses() = runTest {
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(400).body("bad").build())
            server.enqueue(MockResponse.Builder().code(401).body("auth").build())
            server.enqueue(MockResponse.Builder().code(403).body("forbidden").build())
            server.enqueue(MockResponse.Builder().code(404).body("missing").build())

            val client = testClient(config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
            assertEquals(AO3Error.BadRequest, (client.get(server.url("/400").toString()) as AO3Result.Failure).error)
            assertEquals(
                AO3Error.AuthenticationRequired,
                (client.get(server.url("/401").toString()) as AO3Result.Failure).error
            )
            assertEquals(AO3Error.Forbidden, (client.get(server.url("/403").toString()) as AO3Result.Failure).error)
            assertEquals(AO3Error.NotFound, (client.get(server.url("/404").toString()) as AO3Result.Failure).error)
            assertEquals(4, server.requestCount)
        }
    }

    @Test
    fun detectsRedirectToLoginAsAuthenticationRequired() = runTest {
        withServer { server ->
            server.enqueue(
                MockResponse.Builder()
                    .code(302)
                    .addHeader("Location", server.url(AO3Constants.LOGIN_PATH).toString())
                    .build()
            )
            server.enqueue(MockResponse.Builder().code(200).body("login").build())

            val result = testClient().get(server.url("/works/search").toString())

            assertEquals(AO3Error.AuthenticationRequired, (result as AO3Result.Failure).error)
            assertEquals(2, server.requestCount)
        }
    }

    @Test
    fun mapsNetworkFailureToNetworkError() = runTest {
        val server = MockWebServer()
        server.start()
        val url = server.url("/disconnect").toString()
        server.close()

        val result = testClient(
            config = AO3NetworkConfig(maxRetries = 0, minDelayBetweenRequestsMillis = 0)
        ).get(url)

        assertTrue((result as AO3Result.Failure).error is AO3Error.Network)
    }
}

class AO3ClientRetryTest {
    @Test
    fun retriesServerErrorForGetThenReturnsSuccess() = runTest {
        withServer { server ->
            val delay = RecordingDelay()
            server.enqueue(MockResponse.Builder().code(500).body("server issue").build())
            server.enqueue(MockResponse.Builder().code(200).body("ok").build())

            val result = testClient(delay = delay).get(server.url("/works/search").toString())

            assertEquals("ok", (result as AO3Result.Success).value.body)
            assertEquals(listOf(500L), delay.delays)
            assertEquals(2, server.requestCount)
        }
    }

    @Test
    fun retriesRateLimitWithRetryAfterSeconds() = runTest {
        withServer { server ->
            val delay = RecordingDelay()
            server.enqueue(
                MockResponse.Builder()
                    .code(429)
                    .addHeader("Retry-After", "2")
                    .body("rate limited")
                    .build()
            )
            server.enqueue(MockResponse.Builder().code(200).body("ok").build())

            val result = testClient(delay = delay).get(server.url("/works/search").toString())

            assertEquals("ok", (result as AO3Result.Success).value.body)
            assertEquals(listOf(2_000L), delay.delays)
            assertEquals(2, server.requestCount)
        }
    }

    @Test
    fun invalidRetryAfterFallsBackToBackoff() = runTest {
        withServer { server ->
            val delay = RecordingDelay()
            server.enqueue(
                MockResponse.Builder()
                    .code(429)
                    .addHeader("Retry-After", "later-ish")
                    .body("rate limited")
                    .build()
            )
            server.enqueue(MockResponse.Builder().code(200).body("ok").build())

            val result = testClient(delay = delay).get(server.url("/works/search").toString())

            assertEquals("ok", (result as AO3Result.Success).value.body)
            assertEquals(listOf(500L), delay.delays)
            assertEquals(2, server.requestCount)
        }
    }

    @Test
    fun doesNotRetryNotFound() = runTest {
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(404).body("missing").build())

            val result = testClient().get(server.url("/works/missing").toString())

            assertEquals(AO3Error.NotFound, (result as AO3Result.Failure).error)
            assertEquals(1, server.requestCount)
        }
    }
}

class AO3ClientDoesNotRetryPostOrNonRetryableErrorsTest {
    @Test
    fun retryPolicyDocumentsPostAndNonRetryableBehavior() {
        val policy = AO3RetryPolicy(AO3NetworkConfig(maxRetries = 2))

        assertFalse(policy.shouldRetry(AO3HttpMethod.POST, AO3Error.Server(500), 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.POST, AO3Error.RateLimited(1_000), 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.BadRequest, 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.AuthenticationRequired, 1))
        assertFalse(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.NotFound, 1))
    }
}

class AO3ClientUserAgentTest {
    @Test
    fun appliesCentralizedUserAgent() = runTest {
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(200).body("ok").build())

            testClient().get(server.url("/works/search").toString())

            val request = server.takeRequest(1, TimeUnit.SECONDS)
            assertEquals(AO3UserAgent.VALUE, request?.headers?.get("User-Agent"))
        }
    }
}

class AO3ClientCoalescingTest {
    @Test
    fun identicalConcurrentGetsShareOneServerRequest() = runTest {
        withServer { server ->
            server.enqueue(
                MockResponse.Builder()
                    .code(200)
                    .body("shared")
                    .bodyDelay(200, TimeUnit.MILLISECONDS)
                    .build()
            )
            val client = testClient()
            val url = server.url("/works/search").toString()

            val first = async { client.get(url) }
            val second = async { client.get(url) }

            assertEquals("shared", (first.await() as AO3Result.Success).value.body)
            assertEquals("shared", (second.await() as AO3Result.Success).value.body)
            assertEquals(1, server.requestCount)
        }
    }

    @Test
    fun differentUrlsDoNotCoalesce() = runTest {
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(200).body("one").build())
            server.enqueue(MockResponse.Builder().code(200).body("two").build())
            val client = testClient()

            val first = async { client.get(server.url("/one").toString()) }
            val second = async { client.get(server.url("/two").toString()) }

            val bodies = setOf(
                (first.await() as AO3Result.Success).value.body,
                (second.await() as AO3Result.Success).value.body
            )
            assertEquals(setOf("one", "two"), bodies)
            assertEquals(2, server.requestCount)
        }
    }

    @Test
    fun completedCoalescedRequestDoesNotPoisonFutureRequests() = runTest {
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(200).body("first").build())
            server.enqueue(MockResponse.Builder().code(200).body("second").build())
            val client = testClient()
            val url = server.url("/works/search").toString()

            assertEquals("first", (client.get(url) as AO3Result.Success).value.body)
            assertEquals("second", (client.get(url) as AO3Result.Success).value.body)
            assertEquals(2, server.requestCount)
        }
    }
}

class AO3OverloadDetectorTest {
    @Test
    fun detectsObviousAo3OverloadFixtures() {
        val overloaded200 = """
            <html>
            <head><title>Archive of Our Own is temporarily overloaded</title></head>
            <body>AO3 has too many users right now. Please try again later.</body>
            </html>
        """
        val overloaded503 = """
            <html>
            <head><title>Archive of Our Own capacity issue</title></head>
            <body>The Archive of Our Own is temporarily unavailable.</body>
            </html>
        """

        assertTrue(AO3OverloadDetector.isOverloadPage(overloaded200))
        assertTrue(AO3OverloadDetector.isOverloadPage(overloaded503))
        assertFalse(AO3OverloadDetector.isOverloadPage("<html><body>No works found.</body></html>"))
    }

    @Test
    fun clientMapsOverloadBodyToRetryableOverloadedError() = runTest {
        withServer { server ->
            server.enqueue(
                MockResponse.Builder()
                    .code(200)
                    .body("<html><title>Archive of Our Own is temporarily overloaded</title></html>")
                    .build()
            )

            val result = testClient(
                config = AO3NetworkConfig(maxRetries = 0, minDelayBetweenRequestsMillis = 0)
            ).get(server.url("/works/search").toString())

            assertTrue((result as AO3Result.Failure).error is AO3Error.Overloaded)
        }
    }
}

private fun testClient(
    config: AO3NetworkConfig = AO3NetworkConfig(
        maxRetries = 2,
        minDelayBetweenRequestsMillis = 0
    ),
    delay: AO3Delay = RecordingDelay()
): AO3Client {
    return OkHttpAO3Client(
        okHttpClient = OkHttpClient.Builder()
            .followRedirects(true)
            .build(),
        config = config,
        coordinator = AO3RequestCoordinator(config = config, delay = delay),
        coalescer = AO3RequestCoalescer(),
        retryPolicy = AO3RetryPolicy(config),
        delay = delay
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

private class RecordingDelay : AO3Delay {
    val delays = mutableListOf<Long>()

    override suspend fun delay(millis: Long) {
        delays += millis
    }
}

private class FakeClock : AO3Clock {
    var now = 0L

    override fun nowMillis(): Long = now
}

private class AdvancingDelay(
    private val clock: FakeClock
) : AO3Delay {
    val delays = mutableListOf<Long>()

    override suspend fun delay(millis: Long) {
        delays += millis
        clock.now += millis
    }
}
