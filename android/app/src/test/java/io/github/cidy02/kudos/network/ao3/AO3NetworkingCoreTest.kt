package io.github.cidy02.kudos.network.ao3

import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
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
        assertFalse(policy.shouldRetry(AO3HttpMethod.GET, AO3Error.Parse("changed markup"), 1))
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
    fun lastWaiterLeavingCancelsTheOperationBeforeItsFetch() = runTest {
        val coalescer = AO3RequestCoalescer<String, String>(this)
        val release = CompletableDeferred<Unit>()
        var fetches = 0
        var stopped = false
        val first = async {
            coalescer.coalesce("same") {
                try {
                    release.await() // Waiting for a pacing slot, before the fetch.
                    fetches += 1
                    "unwanted"
                } finally {
                    stopped = true
                }
            }
        }
        runCurrent()
        val second = async { coalescer.coalesce("same") { error("Must join the first") } }
        runCurrent()

        first.cancelAndJoin()
        assertFalse(stopped)
        second.cancelAndJoin()
        runCurrent()
        assertTrue(stopped)
        assertEquals(0, coalescer.inFlightCount())
        release.complete(Unit)
        runCurrent()
        assertEquals(0, fetches)
        assertEquals("new request", coalescer.coalesce("same") { "new request" })
    }

    @Test
    fun cancellingOneWaiterLeavesTheSharedOperationForTheOther() = runTest {
        val coalescer = AO3RequestCoalescer<String, String>(this)
        val release = CompletableDeferred<Unit>()
        var fetches = 0
        val first = async {
            coalescer.coalesce("same") {
                release.await()
                fetches += 1
                "shared"
            }
        }
        runCurrent()
        val second = async { coalescer.coalesce("same") { error("Must join the first") } }
        runCurrent()

        first.cancelAndJoin()
        assertEquals(1, coalescer.inFlightCount())
        release.complete(Unit)
        assertEquals("shared", second.await())
        assertEquals(1, fetches)
        assertEquals(0, coalescer.inFlightCount())
    }

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
    fun a503ReadRetryReentersCoordinatorSpacingForHtmlAndBytes() = runTest {
        for (binary in listOf(false, true)) withServer { server ->
            server.enqueue(MockResponse.Builder().code(503).addHeader("Retry-After", "0").body("busy").build())
            server.enqueue(MockResponse.Builder().code(200).body("ok").build())
            val clock = FakeClock()
            val waits = AdvancingDelay(clock)
            val starts = mutableListOf<Long>()
            val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 600, maxConcurrentRequests = 1)
            val stack = OkHttpAO3Client.defaultOkHttpClient(config).newBuilder()
                .addInterceptor { chain -> starts += clock.now; chain.proceed(chain.request()) }.build()
            val client = OkHttpAO3Client(stack, config,
                coordinator = AO3RequestCoordinator(config, clock, waits),
                // Backoff is separate from request spacing: don't advance the coordinator's clock.
                delay = RecordingDelay(), isAllowedUrl = { true })
            val url = server.url("/works/123").toString()
            val result = if (binary) client.getBytes(url) else client.get(url)
            assertTrue(result is AO3Result.Success)
            assertEquals(2, server.requestCount)
            assertEquals(listOf(0L, 600L), starts)
            assertEquals(listOf(600L), waits.delays)
        }
    }

    @Test
    fun aPostAnswered503RetryAfterZeroIsNotSentAgain() = runTest {
        // A51 F1: OkHttp repeats a request answered 503 with Retry-After: 0, whatever
        // retryOnConnectionFailure says.
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(503).addHeader("Retry-After", "0").body("busy").build())
            server.enqueue(MockResponse.Builder().code(200).body("ok").build())
            val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 0)
            val client = OkHttpAO3Client(OkHttpAO3Client.defaultOkHttpClient(config), config,
                delay = RecordingDelay(), isAllowedUrl = { true })
            client.postForm(server.url("/works/1/kudos").toString(), listOf("a" to "1"), emptyMap())
            assertEquals(1, server.requestCount)
        }
    }

    @Test
    fun theAppsClientNeverSendsAPostTwice() = runTest {
        // A50 F1: OkHttp answered a 408 by sending the POST again by itself.
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(408).body("timeout").build())
            server.enqueue(MockResponse.Builder().code(200).body("ok").build())
            val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 0)
            val client = OkHttpAO3Client(OkHttpAO3Client.defaultOkHttpClient(config), config,
                delay = RecordingDelay(), isAllowedUrl = { true })
            client.postForm(server.url("/works/1/kudos").toString(), listOf("a" to "1"), emptyMap())
            assertEquals(1, server.requestCount)
        }
    }

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

@OptIn(ExperimentalCoroutinesApi::class)
class AO3ClientCoalescingTest {
    // iOS AO3ClientPolicyTests: cancellation must precede reserving a pacing slot.
    @Test fun cancelledBinaryDownloadDoesNotReserveAPacingSlot() = runTest {
        withServer { server ->
            val waits = RecordingDelay()
            val coordinator = AO3RequestCoordinator(AO3NetworkConfig(), FakeClock(), waits)
            val client = OkHttpAO3Client(OkHttpClient(), coordinator = coordinator, isAllowedUrl = { true })
            val download = async {
                kotlinx.coroutines.currentCoroutineContext()[kotlinx.coroutines.Job]!!.cancel()
                client.getBytes(server.url("/download.epub").toString())
            }
            download.join()
            assertTrue(download.isCancelled)
            coordinator.coordinate { Unit }
            assertTrue(waits.delays.isEmpty())
            assertEquals(0, server.requestCount)
        }
    }

    @Test
    fun lastWaiterLeavingDuringPacingPreventsDispatch() = runTest {
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(200).body("unwanted").build())
            val config = AO3NetworkConfig()
            val release = CompletableDeferred<Unit>()
            var pacingStopped = false
            val coordinator = AO3RequestCoordinator(config, FakeClock(), AO3Delay {
                try { release.await() } finally { pacingStopped = true }
            })
            coordinator.coordinate { Unit } // Reserve the first slot so this GET must wait.
            val coalescer = AO3RequestCoalescer<AO3RequestKey, AO3Result<AO3HttpResponse>>(this)
            val client = OkHttpAO3Client(OkHttpClient(), config, coordinator, coalescer, isAllowedUrl = { true })
            val url = server.url("/works/1").toString()
            val first = async { client.get(url) }
            val second = async { client.get(url) }
            runCurrent()
            assertEquals(1, coalescer.inFlightCount())
            try {
                first.cancelAndJoin()
                second.cancelAndJoin()
                runCurrent()
                assertTrue(pacingStopped)
                assertEquals(0, coalescer.inFlightCount())
                assertEquals(0, server.requestCount)
            } finally {
                release.complete(Unit)
            }
            runCurrent()
            assertEquals(0, server.requestCount)
        }
    }

    @Test
    fun lastWaiterLeavingDuringBackoffPreventsRetry() = runTest {
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(500).body("try later").build())
            server.enqueue(MockResponse.Builder().code(200).body("unwanted retry").build())
            val enteredBackoff = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            var backoffStopped = false
            val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 0)
            val client = OkHttpAO3Client(
                okHttpClient = OkHttpClient(),
                config = config,
                coalescer = AO3RequestCoalescer(this),
                delay = AO3Delay {
                    enteredBackoff.complete(Unit)
                    try { release.await() } finally { backoffStopped = true }
                },
                isAllowedUrl = { true }
            )
            val waiting = async { client.get(server.url("/works/1").toString()) }
            enteredBackoff.await()
            try {
                waiting.cancelAndJoin()
                runCurrent()
                assertTrue(backoffStopped)
            } finally {
                release.complete(Unit)
            }
            runCurrent()
            assertEquals(1, server.requestCount)
        }
    }

    @Test
    fun bypassingPageReadDoesNotJoinAnOrdinaryGetStartedBeforeRemoval() = runTest {
        withServer { server ->
            server.enqueue(MockResponse.Builder().code(200).addHeader("X-Test-Hold", "yes")
                .body("before write").build())
            server.enqueue(MockResponse.Builder().code(200).body("after write").build())
            val started = CompletableDeferred<Unit>()
            val release = CountDownLatch(1)
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val response = chain.proceed(chain.request())
                if (response.header("X-Test-Hold") != null) {
                    started.complete(Unit)
                    if (!release.await(5, TimeUnit.SECONDS)) {
                        response.close()
                        throw java.io.IOException("Earlier GET was not released")
                    }
                }
                response
            }.build()
            val client = OkHttpAO3Client(http,
                AO3NetworkConfig(minDelayBetweenRequestsMillis = 0),
                coalescer = AO3RequestCoalescer(this), isAllowedUrl = { true })
            val url = server.url("/users/Writer").toString()
            val cache = AO3PageCache()
            val key = AO3PageCache.Key(url, AO3PageCache.Scope(null, null), AO3PageCache.Kind.Dashboard)
            val ordinary = async { client.get(url) }
            try {
                started.await()
                cache.removePages("/users/Writer", key.scope)
                val fresh = cache.read(url, key.kind, null, bypassCache = true,
                    fetch = { client.get(url) }, parse = { AO3Result.Success(it.body) })
                assertEquals(AO3Result.Success("after write"), fresh)
                assertFalse(ordinary.isCompleted)
                assertEquals(2, server.requestCount)
                assertEquals("after write", cache.value(key)?.body)
            } finally {
                release.countDown()
            }
            assertEquals("before write", (ordinary.await() as AO3Result.Success).value.body)
            assertEquals("after write", cache.value(key)?.body)
        }
    }

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
            <head><title>Archive of Our Own is over capacity</title></head>
            <body>The Archive of Our Own is temporarily unavailable.</body>
            </html>
        """

        assertTrue(AO3OverloadDetector.isOverloadPage(overloaded200))
        assertTrue(AO3OverloadDetector.isOverloadPage(overloaded503))
        assertFalse(AO3OverloadDetector.isOverloadPage("<html><body>No works found.</body></html>"))
    }

    @Test
    fun doesNotFlagNormalAo3PageContainingCapacitySubstring() {
        // Regression: a normal AO3 page (always contains "Archive of Our Own" in
        // its chrome) whose content merely includes "incapacity" / "try again
        // later" must NOT be treated as an overload page.
        val normalWork = """
            <html>
            <head><title>A Study in Grief - Archive of Our Own</title></head>
            <body>
              <blockquote class="userstuff summary">
                A meditation on loss and incapacity. They promise to try again later.
              </blockquote>
            </body>
            </html>
        """
        assertFalse(AO3OverloadDetector.isOverloadPage(normalWork))
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
        delay = delay,
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
