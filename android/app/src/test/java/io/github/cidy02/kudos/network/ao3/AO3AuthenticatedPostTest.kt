package io.github.cidy02.kudos.network.ao3

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3AuthenticatedPostDoesNotRetryTest {
    @Test
    fun postIsNotRetriedEvenForServerFailure() = runTest {
        withPostServer { server ->
            val delay = PostRecordingDelay()
            val client = postClient(delay = delay)
            server.enqueue(MockResponse.Builder().code(500).body("server issue").build())
            server.enqueue(MockResponse.Builder().code(200).body("would be unsafe replay").build())

            val result = client.postForm(server.url("/works/123/comments").toString(), listOf("a" to "b"))

            assertEquals(AO3Error.Server(500), (result as AO3Result.Failure).error)
            assertEquals(1, server.requestCount)
            assertEquals(emptyList<Long>(), delay.delays)
        }
    }
}

class AO3AuthenticatedPostAuthRequiredTest {
    @Test
    fun postRedirectToLoginMapsToAuthRequired() = runTest {
        withPostServer { server ->
            server.enqueue(
                MockResponse.Builder()
                    .code(302)
                    .addHeader("Location", server.url(AO3Constants.LOGIN_PATH).toString())
                    .build()
            )
            server.enqueue(MockResponse.Builder().code(200).body("login").build())

            val result = postClient().postForm(server.url("/works/123/comments").toString(), listOf("a" to "b"))

            assertEquals(AO3Error.AuthenticationRequired, (result as AO3Result.Failure).error)
        }
    }

    @Test
    fun postUsesCentralUserAgentAndPercentEncodedBody() = runTest {
        withPostServer { server ->
            server.enqueue(MockResponse.Builder().code(200).body("ok").build())

            val result = postClient().postForm(
                server.url("/kudos.js").toString(),
                listOf("authenticity_token" to "a b/c")
            )

            assertEquals("ok", (result as AO3Result.Success).value.body)
            val request = server.takeRequest(1, TimeUnit.SECONDS)
            assertEquals("POST", request?.method)
            assertEquals(AO3UserAgent.VALUE, request?.headers?.get("User-Agent"))
            assertEquals("authenticity_token=a%20b%2Fc", request?.body?.utf8())
        }
    }
}

class AO3WriteOverloadErrorTest {
    @Test
    fun postOverloadBodyMapsToRetryableOverloadWithoutRetrying() = runTest {
        withPostServer { server ->
            server.enqueue(
                MockResponse.Builder()
                    .code(200)
                    .body("<html><title>Archive of Our Own is temporarily overloaded</title></html>")
                    .build()
            )

            val result = postClient().postForm(server.url("/works/123/comments").toString(), listOf("a" to "b"))

            assertTrue((result as AO3Result.Failure).error is AO3Error.Overloaded)
            assertEquals(1, server.requestCount)
        }
    }
}

private fun postClient(delay: AO3Delay = PostRecordingDelay()): OkHttpAO3Client {
    val config = AO3NetworkConfig(maxRetries = 2, minDelayBetweenRequestsMillis = 0)
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

private inline fun withPostServer(block: (MockWebServer) -> Unit) {
    val server = MockWebServer()
    server.start()
    try {
        block(server)
    } finally {
        server.close()
    }
}

private class PostRecordingDelay : AO3Delay {
    val delays = mutableListOf<Long>()

    override suspend fun delay(millis: Long) {
        delays += millis
    }
}
