package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import java.io.File
import java.util.Locale
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AO3ChallengeSettingsTest {
    private val parser = AO3ChallengeSettingsParser()

    @Test fun giftAndMemeFixturesUseRequestRestrictionsAndKeepAo3DateDigits() {
        val gift = parser.parseSettings(challengeFixture("ao3_challenge_settings"), AO3ChallengeKind.GiftExchange)
        assertEquals("1 to 3", gift.promptsPerSignup)
        assertEquals("1 to 3", gift.fandoms)
        assertEquals("0 to 2", gift.relationships)
        assertEquals("0 to 4", gift.characters)
        assertTrue(gift.optionalTags)
        assertTrue(gift.allowAnyPrompt)
        assertTrue(gift.requireFandomMatch)
        assertFalse(gift.anonymous)
        assertEquals(listOf("2026-01-01 00:00:00", "2026-02-01 00:00:00", "2026-03-01 00:00:00",
            "2026-04-01 00:00:00", "2026-05-01 00:00:00"), gift.dates)
        val meme = parser.parseSettings(challengeFixture("ao3_demo_meme_settings"), AO3ChallengeKind.PromptMeme)
        assertEquals(AO3ChallengeKind.PromptMeme, meme.kind)
        assertTrue(meme.anonymous)
        assertEquals("1 to 3", meme.fandoms)
        assertEquals("Jan 1, 2026", challengeDateText(gift.dates.first(), Locale.US))
        assertEquals("Mar 1, 2026", challengeDateText(gift.dates[2], Locale.US))
        assertEquals("Not set", challengeDateText("  ", Locale.US))
        assertEquals("AO3 date text", challengeDateText("AO3 date text", Locale.US))
        assertEquals("Jan 2, 2026", challengeDateText("2026-01-01T23:30:00-02:00", Locale.US))
        assertEquals("Jan 1, 2026", challengeDateText("2026-01-01 23:30:00", Locale.US))
    }

    @Test fun absentRequirementsAndDatesTakeIosDefaultsAndEveryAnyFlagContributes() {
        val minimal = "<main id='main'><form action='/collections/x/gift_exchange'><input name='authenticity_token' value='local'></form></main>"
        val settings = parser.parseSettings(minimal, AO3ChallengeKind.GiftExchange)
        assertEquals(List(5) { "" }, settings.dates)
        assertEquals("1 to 1", settings.promptsPerSignup)
        assertEquals("0 to 0", settings.fandoms)
        assertFalse(settings.allowAnyPrompt)
        assertFalse(settings.optionalTags)
        assertTrue(settings.requireFandomMatch)
        for (type in listOf("fandom", "character", "relationship", "freeform")) {
            val html = minimal.replace("</form>", "<input type='checkbox' checked name='gift_exchange[request_restriction_attributes][allow_any_$type]'></form>")
            val result = parser.parseSettings(html, AO3ChallengeKind.GiftExchange)
            assertTrue(result.allowAnyPrompt)
            assertEquals(type != "fandom", result.requireFandomMatch)
        }
        assertThrows(IllegalArgumentException::class.java) { parser.parseSettings(minimal.replace("value='local'", "value=''"), AO3ChallengeKind.GiftExchange) }
    }

    @Test fun profileLinksAreNumericDeduplicatedAndNamedInServedOrder() {
        assertEquals(listOf(AO3ChallengeTagSet(42, "Winter Exchange Tags"), AO3ChallengeTagSet(43, "Snowbound Characters")),
            parser.parseTagSets(challengeFixture("ao3_collection_show")))
        assertEquals(listOf(AO3ChallengeTagSet(44, "Summer Prompt Tags")), parser.parseTagSets("<dl><dt>Tag set:</dt><dd><a href='/tag_sets/44'>Summer Prompt Tags</a></dd></dl>"))
        assertEquals(listOf(AO3ChallengeTagSet(8, "Tag set 8")), parser.parseTagSets("""
            <dl><dt>Tag sets:</dt><dd><a href='/tag_sets/new'>new</a><a href='/tag_sets/8'></a>
            <a href='/tag_sets/8'>duplicate</a><a href='/tag_sets/9bad'>bad</a></dd>
            <dt>Other:</dt><dd><a href='/tag_sets/10'>unrelated</a></dd></dl>
        """))
        assertEquals(emptyList<AO3ChallengeTagSet>(), parser.parseTagSets("<dl></dl>"))
    }

    @Test fun signupParserRecognizesEmptyVersusMalformedAndCountsFixturePagination() {
        assertEquals(AO3ChallengeSignUpCountPage(2, 2), parser.parseSignUpCount(challengeFixture("ao3_challenge_signups")))
        assertEquals(AO3ChallengeSignUpCountPage(0, 1), parser.parseSignUpCount("<h2 class='heading'>Sign-ups</h2><dl class='index'></dl>"))
        assertThrows(IllegalArgumentException::class.java) { parser.parseSignUpCount("<html>login</html>") }
        assertThrows(IllegalArgumentException::class.java) { parser.parseSignUpCount("<dl class='index'><dt class='participant'><a href='/signups/1'>a</a></dt></dl>") }
    }

    @Test fun openingAndRefreshMakeOnlyFourOrderedAuthenticatedReadsNoIntermediateOrAssignmentPages() = runTest {
        val (_, client, repository) = challengeSetup()
        client.signupPages = 5
        val model = AO3ChallengeSettingsState("winter_exchange", repository)
        model.load()
        assertEquals(listOf(giftUrl, profileUrl, signupUrl, "$signupUrl?page=5"), client.gets)
        assertEquals(10, model.state.value.data!!.signUpTotal)
        assertEquals(2, model.state.value.data!!.tagSets.size)
        model.load()
        assertEquals(client.gets.take(4), client.gets.drop(4))
        assertTrue(client.headers.all { it["Cookie"].orEmpty().isNotEmpty() })
        assertTrue(client.gets.none { it.contains("/assignments") })
        assertEquals(0, client.posts)
    }

    @Test fun memeProbesGiftOn404ThenLoadsOnlyMemeAndProfileAndParseFallbackMatchesIos() = runTest {
        val (_, client, repository) = challengeSetup()
        client.replies[giftUrl] = AO3Result.Failure(AO3Error.NotFound)
        var page = repository.getChallengeSettings("winter_exchange") as AO3Result.Success<AO3ChallengeSettingsPage>
        assertEquals(listOf(giftUrl, memeUrl, profileUrl), client.gets)
        assertEquals(AO3ChallengeKind.PromptMeme, page.value.settings.kind)
        assertNull(page.value.signUpTotal)
        client.gets.clear()
        client.replies[giftUrl] = challengeResponse(giftUrl, "<html>unparseable</html>")
        page = repository.getChallengeSettings("winter_exchange") as AO3Result.Success<AO3ChallengeSettingsPage>
        assertEquals(AO3ChallengeKind.PromptMeme, page.value.settings.kind)
        assertEquals(listOf(giftUrl, memeUrl, profileUrl), client.gets)
        assertEquals(0, client.posts)
    }

    @Test fun profileAndFirstOrLastCountFailuresAreBestEffortNeverZeroAndNoAssignmentsAreRead() = runTest {
        for (failureUrl in listOf(signupUrl, "$signupUrl?page=2")) {
            val (_, client, repository) = challengeSetup()
            client.replies[profileUrl] = AO3Result.Failure(AO3Error.Forbidden)
            client.replies[failureUrl] = AO3Result.Failure(AO3Error.NotFound)
            val model = AO3ChallengeSettingsState("winter_exchange", repository)
            model.load()
            assertNull(model.state.value.failure)
            assertNull(model.state.value.data!!.signUpTotal)
            assertTrue(model.state.value.data!!.tagSets.isEmpty())
            assertEquals(if (failureUrl == signupUrl) 3 else 4, client.gets.size)
            assertTrue(client.gets.none { it.contains("/assignments") })
            assertEquals(0, client.posts)
        }
        val (_, client, repository) = challengeSetup()
        client.replies[signupUrl] = challengeResponse(signupUrl, "<h2 class='heading'>Sign-ups</h2>")
        assertEquals(0, (repository.getChallengeSettings("winter_exchange") as AO3Result.Success<AO3ChallengeSettingsPage>).value.signUpTotal)
        assertEquals(3, client.gets.size)
    }

    @Test fun requiredFormErrorStopsOpeningAndSignedOutSendsNoRequest() = runTest {
        val (_, client, repository) = challengeSetup()
        client.replies[giftUrl] = AO3Result.Failure(AO3Error.Forbidden)
        val model = AO3ChallengeSettingsState("winter_exchange", repository)
        model.load()
        assertEquals(listOf(giftUrl), client.gets)
        assertEquals("AO3 refused the request (HTTP 403). Wait a while before trying again.", model.state.value.failure)
        val (_, outClient, outRepo) = challengeSetup(signedIn = false)
        val out = AO3ChallengeSettingsState("winter_exchange", outRepo)
        out.load()
        assertEquals("Log in to AO3 before using this feature.", out.state.value.failure)
        assertTrue(outClient.gets.isEmpty())
        assertEquals(0, outClient.posts)
    }

    @Test fun logoutAtEachReadStopsLaterReadsAndNeverInstallsOldData() = runTest {
        for (url in listOf(giftUrl, profileUrl, signupUrl, "$signupUrl?page=2")) {
            val (auth, client, repository) = challengeSetup()
            client.afterGet = { read -> if (read == url) auth.logout() }
            val model = AO3ChallengeSettingsState("winter_exchange", repository)
            val load = async { model.load() }
            runCatching { load.await() }
            assertTrue(load.isCancelled)
            assertNull(model.state.value.data)
            assertEquals(url, client.gets.last())
            assertEquals(0, client.posts)
        }
    }

    @Test fun duplicateLoadsAndLeavingScreenDoNotContinueTheReadChain() = runTest {
        val (_, client, repository) = challengeSetup()
        client.hold = true
        val model = AO3ChallengeSettingsState("winter_exchange", repository)
        val load = async { model.load() }
        client.entered.await()
        assertTrue(model.state.value.loading)
        model.load()
        assertEquals(listOf(giftUrl), client.gets)
        model.close()
        runCatching { load.await() }
        assertTrue(load.isCancelled)
        assertNull(model.state.value.data)
        assertEquals(listOf(giftUrl), client.gets)
    }

    @Test fun allPlaceholderDestinationsAndExternalMatchingAreSingleSourcedAndEncodeSlugs() {
        assertEquals(giftUrl, ChallengeSettingsDestinations.challengeSettingsEditView("winter_exchange", AO3ChallengeKind.GiftExchange))
        assertEquals(memeUrl, ChallengeSettingsDestinations.challengeSettingsEditView("winter_exchange", AO3ChallengeKind.PromptMeme))
        assertEquals(signupUrl, ChallengeSettingsDestinations.challengeSignUpsView("winter_exchange"))
        assertEquals("https://archiveofourown.org/collections/winter_exchange/assignments", ChallengeSettingsDestinations.challengeAssignmentsView("winter_exchange"))
        assertEquals("https://archiveofourown.org/collections/winter_exchange/requests", ChallengeSettingsDestinations.promptMemeView("winter_exchange"))
        assertEquals("https://archiveofourown.org/tag_sets/42", ChallengeSettingsDestinations.tagSetView(42))
        assertEquals("https://archiveofourown.org/collections/winter_exchange/potential_matches", ChallengeSettingsDestinations.runMatching("winter_exchange"))
        assertTrue(ChallengeSettingsDestinations.challengeSignUpsView("a/b").contains("a%2Fb"))
    }
}

internal val giftUrl = ChallengeSettingsDestinations.challengeSettingsEditView("winter_exchange", AO3ChallengeKind.GiftExchange)
internal val memeUrl = ChallengeSettingsDestinations.challengeSettingsEditView("winter_exchange", AO3ChallengeKind.PromptMeme)
internal val profileUrl = ChallengeSettingsDestinations.profile("winter_exchange")
internal val signupUrl = ChallengeSettingsDestinations.challengeSignUpsView("winter_exchange")
internal fun challengeFixture(name: String): String = listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
    .map { File(it, "$name.html") }.first { it.isFile }.readText()
internal fun challengeResponse(url: String, html: String): AO3Result<AO3HttpResponse> = AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
internal suspend fun challengeSetup(signedIn: Boolean = true): Triple<AO3AuthRepository, ChallengeReadClient, AO3CollectionDetailRepository> {
    val auth = AO3AuthRepository(MemorySessionStore(if (signedIn) testSession() else null), MemoryCookieStore())
    auth.restoreSession()
    val client = ChallengeReadClient()
    return Triple(auth, client, AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined))
}
internal class ChallengeReadClient : AO3Client, AO3FormPostClient {
    val gets = mutableListOf<String>()
    val headers = mutableListOf<Map<String, String>>()
    val replies = mutableMapOf<String, AO3Result<AO3HttpResponse>>()
    var signupPages = 2
    var posts = 0
    var afterGet: suspend (String) -> Unit = {}
    var hold = false
    val entered = CompletableDeferred<Unit>()
    val release = CompletableDeferred<Unit>()
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url; this.headers += headers
        entered.complete(Unit)
        if (hold) release.await()
        afterGet(url)
        return replies[url] ?: challengeResponse(url, when {
            url == giftUrl -> challengeFixture("ao3_challenge_settings")
            url == memeUrl -> challengeFixture("ao3_demo_meme_settings")
            url == profileUrl -> challengeFixture("ao3_collection_show")
            url.startsWith(signupUrl) -> challengeFixture("ao3_challenge_signups").replace("page=2", "page=$signupPages").replace(">2</a>", ">$signupPages</a>")
            else -> error("Unexpected challenge read: $url")
        })
    }
    override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts++
        error("Challenge settings must never write")
    }
}
