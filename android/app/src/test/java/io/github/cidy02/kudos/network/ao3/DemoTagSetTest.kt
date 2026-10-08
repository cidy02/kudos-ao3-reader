package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.*
import java.io.File
import okhttp3.OkHttpClient
import okhttp3.Request
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

    @Test fun missingAssetsAndUnknownSubpagesFailLocallyWithNoGeneralFixtureFallback() {
        for (fixtures in listOf(source, FixtureSource { null })) {
            val http = client(fixtures)
            val urls = if (fixtures === source) listOf("${AO3TagSetUrls.page(42)}/unknown") else
                listOf(42, 43, 44).flatMap { listOf(AO3TagSetUrls.page(it), AO3TagSetUrls.edit(it), AO3TagSetUrls.nominations(it)) }
            urls.forEach { url -> http.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) } }
        }
    }
}
