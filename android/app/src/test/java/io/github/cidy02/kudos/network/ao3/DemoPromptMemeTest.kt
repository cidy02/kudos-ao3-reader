package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemeParser
import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemeUrls
import java.io.File
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test

class DemoPromptMemeTest {
    private val source = FixtureSource { name ->
        listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
            .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes()
    }
    private fun client(fixtures: FixtureSource = source) = OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
        .addInterceptor { throw AssertionError("Prompt Meme demo attempted a socket request") }.build()

    @Test fun bothPagesAreLocalAndSharedWithBrowserAndExplicitPageOne() {
        val http = client()
        val parser = AO3PromptMemeParser()
        for (page in 1..2) {
            val url = AO3PromptMemeUrls.requests("summer_meme", page)
            val native = http.newCall(Request.Builder().url(url).build()).execute().use {
                assertEquals(200, it.code)
                it.body.string()
            }
            assertEquals(native, DemoNetwork.webFixture(url.toHttpUrl(), source)!!.decodeToString())
            assertEquals(page, parser.parse(native, page).currentPage)
            assertEquals(if (page == 1) 4 else 2, parser.parse(native, page).prompts.size)
        }
        val first = AO3PromptMemeUrls.requests("summer_meme").toHttpUrl()
        assertArrayEquals(DemoNetwork.webFixture(first, source), DemoNetwork.webFixture(first.newBuilder().addQueryParameter("page", "1").build(), source))
        // Other collections retain the fixture they already used.
        assertEquals("ao3_challenge_requests", DemoNetworkRoutes.fixtureName(AO3PromptMemeUrls.requests("winter_exchange").toHttpUrl()))
    }

    @Test fun missingAssetsAndUnknownSummerPagesCannotFallThroughToNetwork() {
        for ((http, url) in listOf(client(FixtureSource { null }) to AO3PromptMemeUrls.requests("summer_meme"),
            client() to AO3PromptMemeUrls.requests("summer_meme", 3))) {
            http.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) }
            assertNull(DemoNetwork.webFixture(url.toHttpUrl(), if (url.endsWith("page=3")) source else FixtureSource { null }))
        }
    }
}
