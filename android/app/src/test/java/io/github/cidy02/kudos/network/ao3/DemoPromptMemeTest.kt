package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemeParser
import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemeUrls
import java.io.File
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
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

    @Test fun claimSuccessRefusalReleaseAndPageReloadAreLocalAndRelaunchResets() {
        val http = client()
        val parser = AO3PromptMemeParser()
        val first = AO3PromptMemeUrls.requests("summer_meme")
        val claims = AO3PromptMemeUrls.claims("summer_meme")
        fun get(url: String): String = http.newCall(Request.Builder().url(url).build()).execute().use {
            assertEquals(200, it.code); it.body.string()
        }
        fun post(url: String, fields: List<Pair<String, String>>, expectedStatus: Int): String =
            http.newCall(Request.Builder().url(url).post(AO3FormEncoding.encode(fields).toRequestBody()).build()).execute().use {
                assertEquals(expectedStatus, it.code); it.body.string()
            }
        assertFalse(parser.parse(get(first)).prompts.first().claimedByCurrentUser)
        assertTrue(get(first).contains("demo-meme-requests"))
        assertTrue(post(claims, listOf("authenticity_token" to "demo-meme-requests", "prompt_id" to "701"), 200).contains("flash notice"))
        val claimed = parser.parse(get(first)).prompts.first()
        assertTrue(claimed.claimedByCurrentUser)
        assertEquals(1701, claimed.claimID)
        val beforeRefusal = get(first)
        assertTrue(post(claims, listOf("authenticity_token" to "demo-meme-requests", "prompt_id" to "704"), 422)
            .contains("This prompt is closed to new claims."))
        assertEquals(beforeRefusal, get(first))
        assertTrue(get(AO3PromptMemeUrls.claims("summer_meme", forUser = true)).contains("demo-meme-claims"))
        assertTrue(post(AO3PromptMemeUrls.claim("summer_meme", 801),
            listOf("_method" to "delete", "authenticity_token" to "demo-meme-claims"), 200).contains("flash notice"))
        val released = parser.parse(get(first)).prompts.first { it.id == 702 }
        assertFalse(released.claimedByCurrentUser)
        assertFalse(released.isClaimed)
        assertTrue(released.canClaim)
        post(AO3PromptMemeUrls.claim("summer_meme", 1701),
            listOf("_method" to "delete", "authenticity_token" to "demo-meme-claims"), 200)
        assertFalse(parser.parse(get(first)).prompts.first().claimedByCurrentUser)
        // New process/interceptor restores the original Summer fixture state.
        client().newCall(Request.Builder().url(first).build()).execute().use {
            val reset = parser.parse(it.body.string())
            assertFalse(reset.prompts.first().claimedByCurrentUser)
            assertEquals(801, reset.prompts.first { row -> row.id == 702 }.claimID)
        }
    }

    @Test fun secondPageClaimReloadsThatPageAndMissingClaimsAssetIsTerminal() {
        val http = client()
        http.newCall(Request.Builder().url(AO3PromptMemeUrls.claims("summer_meme"))
            .post("authenticity_token=demo-meme-requests&prompt_id=705".toRequestBody()).build()).execute().use {
            assertEquals(200, it.code)
        }
        http.newCall(Request.Builder().url(AO3PromptMemeUrls.requests("summer_meme", 2)).build()).execute().use {
            assertTrue(AO3PromptMemeParser().parse(it.body.string(), 2).prompts.first().claimedByCurrentUser)
        }
        client(FixtureSource { null }).newCall(Request.Builder()
            .url(AO3PromptMemeUrls.claims("summer_meme", forUser = true)).build()).execute().use { assertEquals(404, it.code) }
    }

    @Test fun missingAssetsAndUnknownSummerPagesCannotFallThroughToNetwork() {
        for ((http, url) in listOf(client(FixtureSource { null }) to AO3PromptMemeUrls.requests("summer_meme"),
            client() to AO3PromptMemeUrls.requests("summer_meme", 3))) {
            http.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) }
            assertNull(DemoNetwork.webFixture(url.toHttpUrl(), if (url.endsWith("page=3")) source else FixtureSource { null }))
        }
    }
}
