package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import java.io.File
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.junit.Assert.*
import org.junit.Test

class DemoChallengeSignUpTest {
    private val source = FixtureSource { name -> listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
        .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes() }
    private fun client(fixtures: FixtureSource = source) = OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
        .addInterceptor { throw AssertionError("Sign-up demo attempted a socket") }.build()
    private fun get(http: OkHttpClient, url: String) = http.newCall(Request.Builder().url(url).build()).execute().use {
        assertEquals(200, it.code); it.body.string()
    }
    private fun post(http: OkHttpClient, form: AO3ChallengeSignUpForm, status: Int) = http.newCall(Request.Builder().url(form.actionUrl)
        .post(AO3FormEncoding.encode(form.parameters()).toRequestBody()).build()).execute().use {
        assertEquals(status, it.code); it.body.string()
    }

    @Test fun allThreeAddressesShareTheirLocalFormWithTheBrowser() {
        val http = client()
        for ((slug, id) in listOf("winter_exchange" to null, "winter_exchange" to 4, "summer_meme" to null)) {
            val url = AO3ChallengeSignUpUrls.form(slug, id)
            val native = get(http, url)
            assertEquals(native, DemoNetwork.webFixture(url.toHttpUrl(), source)!!.decodeToString())
            val form = AO3ChallengeSignUpParser().parse(native, slug)
            assertEquals(id, form.signUpID)
            assertEquals(slug == "winter_exchange", form.takesOffers)
            assertTrue(form.validated().isValid)
        }
    }

    @Test fun eachSaveSucceedsLocallyAndRelaunchResetsNewOrExistingForm() {
        val parser = AO3ChallengeSignUpParser()
        for ((slug, id) in listOf("winter_exchange" to null, "winter_exchange" to 4, "summer_meme" to null)) {
            val http = client()
            val url = AO3ChallengeSignUpUrls.form(slug, id)
            val original = get(http, url)
            val form = parser.parse(original, slug)
            val typedFirst = form.update(form.requests[0].copy(description = "A courier brings a lantern to a snowbound pier."))
            val newRequest = SignUpPrompt(-9, SignUpPromptKind.Request, title = "A second island",
                description = "A new prompt keeps its text and choices.", anonymous = true,
                tags = mapOf(SignUpTagType.Fandom to listOf("Cloudbound Courier")), any = setOf(SignUpTagType.Relationship))
            val typed = typedFirst.copy(requests = typedFirst.requests + newRequest)
            val response = post(http, typed, 200)
            assertNotNull(AO3WriteFormParser().writeSuccessMessage(response))
            val confirmed = parser.parse(response, slug)
            assertEquals(4, confirmed.signUpID)
            assertEquals(newRequest.description, confirmed.requests[1].description)
            assertEquals(newRequest.title, confirmed.requests[1].title)
            assertTrue(confirmed.requests[1].anonymous)
            assertTrue(SignUpTagType.Relationship in confirmed.requests[1].any)
            assertEquals(typed.requests[0].description, parser.parse(get(http, url), slug).requests[0].description)
            assertEquals(original, get(client(), url))
        }
    }

    @Test fun refusalPreservesServerStateAndHasBothIosReasonsInReturnedForm() {
        val http = client()
        val url = AO3ChallengeSignUpUrls.form("winter_exchange", 4)
        val original = get(http, url)
        val form = AO3ChallengeSignUpParser().parse(original, "winter_exchange")
        val typed = form.update(form.requests[0].copy(description = "Uncharted Lantern & 星"))
        val response = post(http, typed, 422)
        val invalid = AO3ChallengeSignUpParser().parse(response, form.slug)
        assertEquals(2, invalid.generalErrors.size)
        assertEquals(typed.requests[0].description, invalid.requests[0].description)
        assertEquals(invalid.generalErrors.first(), AO3WriteFormParser().writeErrorMessage(response))
        assertEquals(original, get(http, url))
        assertTrue(typed.parameters().contains("challenge_signup[requests_attributes][0][tag_set_attributes][id]" to "421"))
    }

    @Test fun missingAssetUnknownAddressAndWithdrawalAreTerminalLocalFailures() {
        for ((http, url) in listOf(client(FixtureSource { null }) to AO3ChallengeSignUpUrls.form("winter_exchange"),
            client() to "https://archiveofourown.org/collections/winter_exchange/signups/4/unknown")) {
            http.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) }
        }
        // No withdrawal is accepted by the demo's sign-up server.
        client().newCall(Request.Builder().url("https://archiveofourown.org/collections/winter_exchange/signups/4")
            .post("_method=delete&authenticity_token=invalid".toRequestBody()).build()).execute().use { assertNotEquals(200, it.code) }
    }
}
