package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class DemoChallengeSignUpsTest {
    private val source = FixtureSource { name -> listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
        .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes() }
    private fun client(fixtures: FixtureSource = source) = OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
        .addInterceptor { throw AssertionError("Sign-ups demo attempted a socket") }.build()
    private fun get(http: OkHttpClient, url: String): String = http.newCall(Request.Builder().url(url).build()).execute().use {
        assertEquals(200, it.code); it.body.string()
    }
    private fun withdraw(http: OkHttpClient, id: Int): Pair<Int, String> {
        val token = AO3WriteFormParser().parseAuthenticityToken(get(http, AO3ChallengeSignUpUrls.confirmDelete("winter_exchange", id)), metaOnly = true)!!
        val body = AO3FormEncoding.encode(listOf("_method" to "delete", "authenticity_token" to token))
        return http.newCall(Request.Builder().url(AO3ChallengeSignUpUrls.signUp("winter_exchange", id)).post(body.toRequestBody()).build())
            .execute().use { it.code to it.body.string() }
    }
    @Test fun listAndThreeAssignmentAddressesShareOneFixtureWithBrowserAndSettingsCount() {
        val http = client()
        val parser = AO3ChallengeSignUpsParser()
        val addresses = listOf(AO3ChallengeSignUpsUrls.page("winter_exchange"), AO3ChallengeSignUpsUrls.page("winter_exchange", 2)) +
            listOf(SignUpAssignmentList.Complete, SignUpAssignmentList.Open, SignUpAssignmentList.Defaults).map { AO3ChallengeSignUpsUrls.assignments("winter_exchange", it) } +
            listOf(ChallengeSettingsDestinations.challengeSettingsEditView("winter_exchange", AO3ChallengeKind.GiftExchange),
                AO3ChallengeSignUpUrls.confirmDelete("winter_exchange", 4), AO3ChallengeSignUpUrls.confirmDelete("winter_exchange", 5),
                AO3ChallengeSignUpUrls.form("winter_exchange", 5))
        for (url in addresses) assertEquals(get(http, url), DemoNetwork.webFixture(url.toHttpUrl(), source)!!.decodeToString())
        val first = parser.parse(get(http, addresses[0]))
        val last = parser.parse(get(http, addresses[1]), 2)
        assertEquals(6, first.rows.size * (first.totalPages - 1) + last.rows.size)
        val settings = AO3ChallengeSettingsParser().parseSettings(get(http, addresses[5]), AO3ChallengeKind.GiftExchange)
        assertFalse(settings.signupOpen)
        val joined = listOf(SignUpAssignmentList.Complete, SignUpAssignmentList.Open, SignUpAssignmentList.Defaults).flatMap { parser.parseAssignments(get(http, AO3ChallengeSignUpsUrls.assignments("winter_exchange", it))) }
        assertEquals(3, (first.rows + last.rows).count { signUpMatch(it, joined) == SignUpMatch.Matched })
        assertEquals(3, (first.rows + last.rows).count { signUpMatch(it, joined) == SignUpMatch.Unmatched })
        assertEquals(5, AO3ChallengeSignUpParser().parse(get(http, AO3ChallengeSignUpUrls.form("winter_exchange", 5)), "winter_exchange").signUpID)
    }
    @Test fun successRemovesOnlyItsRowRefusalKeepsFormAndListAndFreshInterceptorResets() {
        val http = client()
        val url = AO3ChallengeSignUpsUrls.page("winter_exchange")
        val original = get(http, url)
        val refusedForm = get(http, AO3ChallengeSignUpUrls.form("winter_exchange", 5))
        val refusal = withdraw(http, 5)
        assertEquals(422, refusal.first)
        assertEquals("Sign-ups are closed. You cannot delete your sign-up.", AO3WriteFormParser().writeErrorMessage(refusal.second))
        assertEquals(original, get(http, url))
        assertEquals(refusedForm, get(http, AO3ChallengeSignUpUrls.form("winter_exchange", 5)))
        val confirmed = withdraw(http, 4)
        assertEquals(200, confirmed.first)
        assertEquals("Sign-up withdrawn.", AO3WriteFormParser().writeSuccessMessage(confirmed.second))
        val rows = AO3ChallengeSignUpsParser().parse(get(http, url)).rows
        assertEquals(listOf(5, 6, 7), rows.map { it.id })
        assertEquals(5, ownListedSignUpID(rows, "AO3_Reader"))
        assertEquals(original, get(client(), url))
    }
    @Test fun missingAssetsUnknownPagesAndWrongOrExtraFieldsNeverReachSocket() {
        val urls = listOf(AO3ChallengeSignUpsUrls.page("winter_exchange"), AO3ChallengeSignUpUrls.confirmDelete("winter_exchange", 4),
            AO3ChallengeSignUpsUrls.assignments("winter_exchange", SignUpAssignmentList.Complete))
        for (url in urls) client(FixtureSource { null }).newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) }
        client().newCall(Request.Builder().url(AO3ChallengeSignUpsUrls.page("winter_exchange", 3)).build()).execute().use { assertEquals(404, it.code) }
        for (fields in listOf(listOf("_method" to "delete", "authenticity_token" to "wrong"),
            listOf("_method" to "delete", "authenticity_token" to "withdraw-4-fresh", "commit" to "Delete Sign-up"))) {
            client().newCall(Request.Builder().url(AO3ChallengeSignUpUrls.signUp("winter_exchange", 4))
                .post(AO3FormEncoding.encode(fields).toRequestBody()).build()).execute().use { assertEquals(422, it.code) }
        }
    }
}
