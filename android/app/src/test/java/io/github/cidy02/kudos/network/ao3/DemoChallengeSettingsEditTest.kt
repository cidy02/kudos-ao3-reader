package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.account.challengeFixture
import io.github.cidy02.kudos.network.ao3.account.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class DemoChallengeSettingsEditTest {
    private val source = FixtureSource { name -> runCatching { challengeFixture(name).encodeToByteArray() }.getOrNull() }
    private fun client() = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor({ true }, { source }))
        .addInterceptor { throw AssertionError("Demo challenge settings attempted a socket") }.build()
    @Test fun bothEditPagesShareOneAnswerWithBrowserAndSaveRefusalPreservesPageRelaunchResets() {
        for (kind in AO3ChallengeKind.entries) {
            val slug = if (kind == AO3ChallengeKind.GiftExchange) "winter_exchange" else "summer_meme"
            val url = ChallengeSettingsDestinations.challengeSettingsEditView(slug, kind)
            val http = client()
            fun get() = http.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(200, it.code); it.body.string() }
            val original = get()
            assertEquals(original, DemoNetwork.webFixture(url.toHttpUrl(), source)!!.decodeToString())
            val form = AO3ChallengeSettingsFormParser().parse(original, slug, kind)
            fun post(value: String) = http.newCall(Request.Builder().url(form.actionUrl)
                .post(AO3FormEncoding.encode(form.changed(form.field("signup_instructions_general"), value).parameters()).toRequestBody())
                .build()).execute().use { it.code to it.body.string() }
            val refusal = post("refuse settings")
            assertEquals(422, refusal.first)
            assertTrue(refusal.second.contains("Sign-up instructions contain a refused demo phrase."))
            assertEquals(original, get())
            assertEquals(200, post("Original edited demo instructions").first)
            assertEquals("Original edited demo instructions", AO3ChallengeSettingsFormParser().parse(get(), slug, kind).value("signup_instructions_general"))
            val restarted = client()
            val reset = restarted.newCall(Request.Builder().url(url).build()).execute().use { it.body.string() }
            assertEquals(original, reset)
            assertEquals(200, http.newCall(Request.Builder().url(AO3CollectionFormUrls.form(slug)).build()).execute().use { it.code })
            if (kind == AO3ChallengeKind.PromptMeme) {
                assertEquals(404, http.newCall(Request.Builder().url(ChallengeSettingsDestinations.challengeSettingsEditView(slug, AO3ChallengeKind.GiftExchange))
                    .build()).execute().use { it.code })
                assertEquals(200, http.newCall(Request.Builder().url(ChallengeSettingsDestinations.signUpPage(slug)).build()).execute().use { it.code })
            }
        }
    }
}
