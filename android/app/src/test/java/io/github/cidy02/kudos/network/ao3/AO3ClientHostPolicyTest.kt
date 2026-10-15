package io.github.cidy02.kudos.network.ao3

import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3ClientHostPolicyTest {
    // Ports AO3ClientPolicyTests' host and imageData/getHTML assertions; no sockets.
    @Test
    fun lookalikeForeignCleartextAndLoopbackAreRejectedBeforeDispatch() = runTest {
        var dispatches = 0
        var beforeSendCalls = 0
        val http = OkHttpClient.Builder().addInterceptor {
            dispatches++
            throw AssertionError("Untrusted URL reached OkHttp")
        }.build()
        val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 0)
        val client = OkHttpAO3Client(http, config)
        for (url in listOf(
            "https://archiveofourown.org.evil.com/tags/Fluff",
            "https://evil.example/pixel.gif",
            "http://archiveofourown.org/",
            "https://127.0.0.1:1/pixel",
            "http://localhost/",
            "not a URL"
        )) {
            val results = listOf(
                client.get(url),
                client.getBytes(url),
                client.postForm(url, emptyList(), emptyMap()),
                client.postFormChecked(url, emptyList(), emptyMap()) { beforeSendCalls++ }
            )
            results.forEach { result ->
                assertTrue("Expected URL validation for $url: $result",
                    result is AO3Result.Failure && result.error is AO3Error.Validation)
            }
        }
        assertEquals(0, dispatches)
        assertEquals(0, beforeSendCalls)
    }

    @Test
    fun httpsAO3AndDownloadSubdomainPassTheDefaultCheck() = runTest {
        val dispatched = mutableListOf<String>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            dispatched += chain.request().url.toString()
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(200).message("Local fixture").body("ok".toResponseBody()).build()
        }.build()
        val client = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
        val work = "https://archiveofourown.org/works/1"
        val epub = "https://download.archiveofourown.org/downloads/1/1.epub"
        assertTrue(client.get(work) is AO3Result.Success)
        assertTrue(client.getBytes(epub) is AO3Result.Success)
        assertEquals(listOf(work, epub), dispatched)
    }
}
