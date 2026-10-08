package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.*
import java.io.File
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class DemoTagSetTest {
    private val source = FixtureSource { name ->
        listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
            .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes()
    }
    private fun client(fixtures: FixtureSource = source) = OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
        .addInterceptor { throw AssertionError("Tag-set demo attempted a socket request") }.build()

    @Test fun allThreeTagSetsHaveOneLocalAnswerPerAddressForHttpAndBrowserIncludingRefusedEdit() {
        val http = client()
        val parser = AO3TagSetParser()
        val observed = mutableListOf<String>()
        fun read(url: String): Pair<Int, String> {
            observed += url
            return http.newCall(Request.Builder().url(url).build()).execute().use { it.code to it.body.string() }
        }
        for (id in listOf(42, 43, 44)) {
            for (url in listOf(AO3TagSetUrls.page(id), AO3TagSetUrls.edit(id), AO3TagSetUrls.nominations(id), AO3TagSetUrls.associations(id))) {
                val (status, body) = read(url)
                assertEquals(if (url == AO3TagSetUrls.edit(44)) 403 else 200, status)
                assertEquals(body, DemoNetwork.webFixture(url.toHttpUrl(), source)!!.decodeToString())
                if (url == AO3TagSetUrls.page(id)) assertEquals(id, parser.parse(body, id).id)
                if (url == AO3TagSetUrls.nominations(id)) {
                    assertEquals(when (id) { 42 -> 5; 43 -> 0; else -> 2 }, parser.parseNominations(body).size)
                }
            }
        }
        assertEquals(12, observed.size)
        assertTrue(observed.none { "page=" in it })
        val collectionParser = AO3ChallengeSettingsParser()
        val winter = collectionParser.parseTagSets(read(ChallengeSettingsDestinations.profile("winter_exchange")).second)
        val summer = collectionParser.parseTagSets(read(ChallengeSettingsDestinations.profile("summer_meme")).second)
        assertEquals(listOf(AO3ChallengeTagSet(42, "Winter Exchange Tags"), AO3ChallengeTagSet(43, "Snowbound Characters")), winter)
        assertEquals(listOf(AO3ChallengeTagSet(44, "Summer Prompt Tags")), summer)
        assertEquals(read(ChallengeSettingsDestinations.profile("summer_meme")).second,
            DemoNetwork.webFixture(ChallengeSettingsDestinations.profile("summer_meme").toHttpUrl(), source)!!.decodeToString())
    }

    private fun read(http: OkHttpClient, url: String) = http.newCall(Request.Builder().url(url).build()).execute().use {
        it.code to it.body.string()
    }
    private fun post(http: OkHttpClient, url: String, fields: List<Pair<String, String>>) = http.newCall(Request.Builder().url(url)
        .post(AO3FormEncoding.encode(fields).toRequestBody("application/x-www-form-urlencoded; charset=UTF-8".toMediaType()))
        .build()).execute().use { it.code to it.body.string() }
    private fun saveFields(vararg values: Pair<AO3TagSetField, String>): List<Pair<String, String>> {
        val data = AO3TagSetParser().parse(source.read("ao3_demo_tag_set_42_edit")!!.decodeToString(), 42)
        return data.saveParameters(values.toMap(), "demo-tag-set-42")
    }

    @Test fun saveAcceptsEmptyAndNamedListsRefusesTriggerWithExactListReasonAndRelaunchResets() {
        val http = client()
        val parser = AO3TagSetParser()
        assertEquals(200, post(http, AO3TagSetUrls.page(42), saveFields()).first)
        assertEquals(7, parser.parse(read(http, AO3TagSetUrls.page(42)).second, 42).totalTagCount)
        assertEquals(200, post(http, AO3TagSetUrls.page(42), saveFields(AO3TagSetField.Fandom to "New Lantern Harbor")).first)
        assertEquals(8, parser.parse(read(http, AO3TagSetUrls.page(42)).second, 42).totalTagCount)
        assertTrue(parser.parse(read(http, AO3TagSetUrls.edit(42)).second, 42).tagnames.values.all(String::isEmpty))
        for (field in AO3TagSetField.entries) {
            val (status, body) = post(http, AO3TagSetUrls.page(42), saveFields(field to "Uncharted Lantern"))
            assertEquals(422, status)
            assertEquals("${field.editorLabel}: Uncharted Lantern could not be added.",
                io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser().writeErrorMessage(body))
            assertEquals(8, parser.parse(read(http, AO3TagSetUrls.page(42)).second, 42).totalTagCount)
        }
        assertEquals(7, parser.parse(read(client(), AO3TagSetUrls.page(42)).second, 42).totalTagCount)
    }

    @Test fun bracketedRejectSucceedsAndRefusedNominationStaysAndNewInterceptorResets() {
        val http = client()
        val url = AO3TagSetUrls.nominations(42)
        val parser = AO3TagSetParser()
        fun queue(client: OkHttpClient) = parser.parseNominations(read(client, url).second)
        val fields = listOf("_method" to "put", "authenticity_token" to "demo-tag-set-42-nominations")
        val refusal = post(http, url, fields + ("fandom_reject_Paper Harbor" to "1"))
        assertEquals(422, refusal.first)
        assertTrue(refusal.second.contains("Paper Harbor is locked for this review."))
        assertEquals(3, queue(http).count { it.state == AO3TagNominationState.Unreviewed })
        assertEquals(200, post(http, url, fields + ("freeform_reject_Letters #LBRACKETWinter#RBRACKET" to "1")).first)
        assertEquals(AO3TagNominationState.Rejected, queue(http).first { it.tagName == "Letters [Winter]" }.state)
        assertEquals(listOf(2, 1, 2), AO3TagNominationState.entries.map { status -> queue(http).count { it.state == status } })
        assertEquals(AO3TagNominationState.Unreviewed, queue(client()).first { it.tagName == "Letters [Winter]" }.state)
    }

    @Test fun onlyTwoPostAddressesAreWritableAndInvalidFieldsOrMissingAssetsFailLocally() {
        val http = client()
        for (url in listOf(AO3TagSetUrls.edit(42), AO3TagSetUrls.associations(42), AO3TagSetUrls.page(43),
            AO3TagSetUrls.nominations(43), AO3TagSetUrls.page(44), AO3TagSetUrls.nominations(44))) {
            assertEquals(405, post(http, url, saveFields()).first)
        }
        assertEquals(422, post(http, AO3TagSetUrls.page(42), saveFields().filter { it.first != "_method" }).first)
        assertEquals(422, post(http, AO3TagSetUrls.page(42), saveFields().map {
            if (it.first == "authenticity_token") it.first to "wrong" else it }).first)
        assertEquals(422, post(http, AO3TagSetUrls.page(42), saveFields() + ("owned_tag_set[visible]" to "1")).first)
        assertEquals(422, post(http, AO3TagSetUrls.nominations(42), listOf("_method" to "put",
            "authenticity_token" to "demo-tag-set-42-nominations", "freeform_reject_Letters [Winter]" to "1")).first)
        assertEquals(404, post(client(FixtureSource { null }), AO3TagSetUrls.page(42), saveFields()).first)
        assertEquals(404, post(client(FixtureSource { null }), AO3TagSetUrls.nominations(42), emptyList()).first)
    }

    @Test fun missingAssetsAndUnknownSubpagesFailLocallyWithNoGeneralFixtureFallback() {
        for (fixtures in listOf(source, FixtureSource { null })) {
            val http = client(fixtures)
            val urls = if (fixtures === source) listOf("${AO3TagSetUrls.page(42)}/unknown") else
                listOf(42, 43, 44).flatMap { listOf(AO3TagSetUrls.page(it), AO3TagSetUrls.edit(it), AO3TagSetUrls.nominations(it)) }
            urls.forEach { url -> http.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) } }
        }
    }
}
