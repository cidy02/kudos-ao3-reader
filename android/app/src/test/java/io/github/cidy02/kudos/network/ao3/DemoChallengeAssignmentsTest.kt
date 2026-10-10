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

class DemoChallengeAssignmentsTest {
    private val source = FixtureSource { name -> listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
        .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes() }
    private fun client(fixtures: FixtureSource = source) = OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
        .addInterceptor { throw AssertionError("Assignments demo attempted a socket") }.build()
    private fun url(list: SignUpAssignmentList, page: Int = 1) = AO3ChallengeSignUpsUrls.assignments("winter_exchange", list, page)
    private fun get(http: OkHttpClient, address: String) = http.newCall(Request.Builder().url(address).build()).execute().use {
        assertEquals(200, it.code); it.body.string()
    }
    private fun rows(http: OkHttpClient, list: SignUpAssignmentList) = AO3ChallengeSignUpsParser().parseAssignments(get(http, url(list)), list)
    private fun write(http: OkHttpClient, claim: Boolean, id: Int, extra: Boolean = false): Pair<Int, String> {
        val referer = url(if (claim) SignUpAssignmentList.Defaults else SignUpAssignmentList.Open)
        val token = AO3WriteFormParser().parseAuthenticityToken(get(http, referer), metaOnly = true)!!
        val fields = listOf("_method" to "put", "authenticity_token" to token,
            if (claim) "cover_$id" to "AO3_Reader" else "default_$id" to "1") + if (extra) listOf("commit" to "Update") else emptyList()
        return http.newCall(Request.Builder().url("${url(SignUpAssignmentList.Defaults)}/update_multiple")
            .header("X-CSRF-Token", token).header("Referer", referer)
            .post(AO3FormEncoding.encode(fields).toRequestBody()).build()).execute().use { it.code to it.body.string() }
    }
    @Test fun everyFirstAndRequestedFurtherPageSharesBrowserAddressAndRealParser() {
        val http = client()
        for (list in SignUpAssignmentList.entries) for (page in 1..2) {
            val address = url(list, page); val html = get(http, address)
            assertEquals(html, DemoNetwork.webFixture(address.toHttpUrl(), source)!!.decodeToString())
            val parsed = AO3ChallengeSignUpsParser().parseAssignmentPage(html, list, page)
            assertEquals(2, parsed.totalPages); assertTrue(parsed.rows.isNotEmpty())
        }
        assertEquals(listOf(82, 85, 88), rows(http, SignUpAssignmentList.Defaults).map { it.id })
        assertEquals("Replacement", rows(http, SignUpAssignmentList.PinchHits).single().pinchHitter)
    }
    @Test fun bothRefusalsKeepEverythingBothSuccessesMoveRowsAndRelaunchResetsSharedJoin() {
        val http = client()
        val original = SignUpAssignmentList.entries.associateWith { get(http, url(it)) }
        for ((claim, id, reason) in listOf(Triple(true, 85, "This pinch hit is no longer available."),
            Triple(false, 86, "This assignment cannot be defaulted."))) {
            val answer = write(http, claim, id)
            assertEquals(422, answer.first); assertEquals(reason, AO3WriteFormParser().writeErrorMessage(answer.second))
            assertEquals(original, SignUpAssignmentList.entries.associateWith { get(http, url(it)) })
        }
        assertEquals(200, write(http, true, 82).first)
        assertFalse(rows(http, SignUpAssignmentList.Defaults).any { it.id == 82 })
        assertEquals("AO3_Reader", rows(http, SignUpAssignmentList.Open).first { it.id == 82 }.pinchHitter)
        assertEquals("AO3_Reader", rows(http, SignUpAssignmentList.PinchHits).first { it.id == 82 }.pinchHitter)
        assertEquals(200, write(http, false, 84).first)
        assertFalse(rows(http, SignUpAssignmentList.Open).any { it.id == 84 })
        assertTrue(rows(http, SignUpAssignmentList.Defaults).first { it.id == 84 }.defaulted)
        val signups = AO3ChallengeSignUpsParser().parse(get(http, AO3ChallengeSignUpsUrls.page("winter_exchange"))).rows
        val joined = listOf(SignUpAssignmentList.Complete, SignUpAssignmentList.Open, SignUpAssignmentList.Defaults).flatMap { rows(http, it) }
        assertEquals(SignUpMatch.Matched, signUpMatch(signups.first { it.id == 5 }, joined))
        assertEquals(original, SignUpAssignmentList.entries.associateWith { get(client(), url(it)) })
    }
    @Test fun missingAssetsUnknownPagesExtraFieldsAndDuplicateWriteNeverReachSocket() {
        client(FixtureSource { null }).newCall(Request.Builder().url(url(SignUpAssignmentList.Defaults)).build()).execute().use { assertEquals(404, it.code) }
        val http = client()
        http.newCall(Request.Builder().url(url(SignUpAssignmentList.PinchHits, 3)).build()).execute().use { assertEquals(404, it.code) }
        assertEquals(422, write(http, true, 82, extra = true).first)
        assertTrue(rows(http, SignUpAssignmentList.Defaults).any { it.id == 82 })
        assertEquals(200, write(http, true, 82).first)
        assertEquals(422, write(http, true, 82).first)
    }
}
