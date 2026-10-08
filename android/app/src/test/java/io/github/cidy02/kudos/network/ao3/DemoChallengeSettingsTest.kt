package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.*
import java.io.File
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class DemoChallengeSettingsTest {
    private val source = FixtureSource { name ->
        listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
            .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes()
    }
    private fun client(fixtures: FixtureSource = source) = OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
        .addInterceptor { throw AssertionError("Challenge demo attempted a socket request") }.build()

    @Test fun giftMemeAndFailedCountAreTerminalLocalAnswersSharedWithBrowserAndOtherCollectionScreens() {
        val http = client()
        val parser = AO3ChallengeSettingsParser()
        fun read(url: String): Pair<Int, String> = http.newCall(Request.Builder().url(url).build()).execute().use { it.code to it.body.string() }
        val giftUrl = ChallengeSettingsDestinations.challengeSettingsEditView("winter_exchange", AO3ChallengeKind.GiftExchange)
        val gift = read(giftUrl)
        assertEquals(200, gift.first)
        assertEquals("1 to 3", parser.parseSettings(gift.second, AO3ChallengeKind.GiftExchange).fandoms)
        assertEquals(gift.second, DemoNetwork.webFixture(giftUrl.toHttpUrl(), source)!!.decodeToString())
        val profileUrl = ChallengeSettingsDestinations.profile("winter_exchange")
        val profile = read(profileUrl)
        assertEquals(2, parser.parseTagSets(profile.second).size)
        assertEquals(profile.second, DemoNetwork.webFixture(profileUrl.toHttpUrl(), source)!!.decodeToString())
        val first = parser.parseSignUpCount(read(ChallengeSettingsDestinations.signUpPage("winter_exchange")).second)
        val last = parser.parseSignUpCount(read(ChallengeSettingsDestinations.signUpPage("winter_exchange", first.totalPages)).second, first.totalPages)
        assertEquals(4, first.count * (first.totalPages - 1) + last.count)
        val probe = ChallengeSettingsDestinations.challengeSettingsEditView("summer_meme", AO3ChallengeKind.GiftExchange)
        assertEquals(404, read(probe).first)
        assertNull(DemoNetwork.webFixture(probe.toHttpUrl(), source))
        val memeUrl = ChallengeSettingsDestinations.challengeSettingsEditView("summer_meme", AO3ChallengeKind.PromptMeme)
        val meme = read(memeUrl)
        assertEquals(200, meme.first)
        assertTrue(parser.parseSettings(meme.second, AO3ChallengeKind.PromptMeme).anonymous)
        assertEquals(meme.second, DemoNetwork.webFixture(memeUrl.toHttpUrl(), source)!!.decodeToString())
        val summerProfile = ChallengeSettingsDestinations.profile("summer_meme")
        assertEquals(listOf(AO3ChallengeTagSet(44, "Summer Prompt Tags")), parser.parseTagSets(read(summerProfile).second))
        assertEquals(read(summerProfile).second, DemoNetwork.webFixture(summerProfile.toHttpUrl(), source)!!.decodeToString())
        // The existing collection parser sees the same page and an owner-visible Manage link.
        assertNotNull(AO3CollectionParser().parseCollectionShow(read(summerProfile).second, "summer_meme").dashboard.challengeSettingsUrl)
        assertTrue(AO3CollectionParser().parseCollectionShow(read(summerProfile).second, "summer_meme").collection.viewerIsOwner)
        val rareProfile = ChallengeSettingsDestinations.profile("rare_pairs")
        assertEquals(read(rareProfile).second, DemoNetwork.webFixture(rareProfile.toHttpUrl(), source)!!.decodeToString())
        assertNotNull(AO3CollectionParser().parseCollectionShow(read(rareProfile).second, "rare_pairs").dashboard.challengeSettingsUrl)
        val failedCount = ChallengeSettingsDestinations.signUpPage("rare_pairs")
        assertEquals(404, read(failedCount).first)
        assertNull(DemoNetwork.webFixture(failedCount.toHttpUrl(), source))
    }

    @Test fun missingAssetsNeverEscapeTheDemoBlock() {
        val http = client(FixtureSource { null })
        for (url in listOf(ChallengeSettingsDestinations.challengeSettingsEditView("winter_exchange", AO3ChallengeKind.GiftExchange),
            ChallengeSettingsDestinations.challengeSettingsEditView("summer_meme", AO3ChallengeKind.PromptMeme),
            ChallengeSettingsDestinations.profile("winter_exchange"), ChallengeSettingsDestinations.signUpPage("winter_exchange"))) {
            http.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) }
        }
    }
}
