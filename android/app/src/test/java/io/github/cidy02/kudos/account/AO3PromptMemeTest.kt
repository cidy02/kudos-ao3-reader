package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AO3PromptMemeTest {
    private val parser = AO3PromptMemeParser()

    @Test fun bothOriginalFixturesParseEveryStateTagsAnonymousAndFullDescription() {
        val first = parser.parse(challengeFixture("ao3_demo_meme_requests_1"))
        assertEquals(1, first.currentPage)
        assertEquals(2, first.totalPages)
        assertEquals(listOf(701, 702, 703, 704), first.prompts.map { it.id })
        val unclaimed = first.prompts[0]
        assertFalse(unclaimed.isClaimed)
        assertTrue(unclaimed.canClaim)
        assertEquals(2, unclaimed.fandoms.size)
        assertEquals(listOf("No Archive Warnings Apply", "General Audiences", "Gen", "Mira Vale & Oren Moss",
            "Mira Vale", "Oren Moss", "Found Family", "Letters That Arrive Late"), unclaimed.tags)
        assertFalse(unclaimed.tags.contains("Optional hidden suggestion"))
        assertEquals("HarborScribe", unclaimed.displayedOwner)
        val own = first.prompts[1]
        assertTrue(own.claimedByCurrentUser)
        assertTrue(own.isClaimed)
        assertEquals(801, own.claimID)
        assertTrue(first.prompts[2].isClaimed)
        assertFalse(first.prompts[2].claimedByCurrentUser)
        val anonymous = first.prompts[3]
        assertEquals("", anonymous.title)
        assertTrue(anonymous.isAnonymous)
        assertNull(anonymous.displayedOwner)
        assertNull(anonymous.ownerPseud)
        assertEquals(2, anonymous.claimantCount)
        assertTrue(anonymous.canClaim) // another person's claim does not block claiming
        val second = parser.parse(challengeFixture("ao3_demo_meme_requests_2"), 2)
        assertEquals(2, second.currentPage)
        assertEquals(2, second.totalPages)
        assertTrue(second.prompts[0].promptText.length > 700)
        assertTrue(second.prompts[0].promptText.endsWith("the smell of warm bread."))
        assertEquals("EveningInk (AO3_Reader)", second.prompts[0].displayedOwner)
        assertTrue(second.prompts[1].isAnonymous)
        assertEquals("", second.prompts[1].title)
    }

    @Test fun filtersUseOnlyThisPageAndNeverGuessAnonymousIdentity() {
        val first = parser.parse(challengeFixture("ao3_demo_meme_requests_1")).prompts
        assertEquals(4, first.count { AO3PromptMemeFilter.All.includes(it, "AO3_Reader") })
        assertEquals(listOf(701), first.filter { AO3PromptMemeFilter.Unclaimed.includes(it, "AO3_Reader") }.map { it.id })
        assertEquals(listOf(702), first.filter { AO3PromptMemeFilter.Yours.includes(it, "AO3_Reader") }.map { it.id })
        val posted = parser.parse(challengeFixture("ao3_demo_meme_requests_2"), 2).prompts[0]
        assertTrue(AO3PromptMemeFilter.Yours.includes(posted, " ao3_READER "))
        assertFalse(AO3PromptMemeFilter.Yours.includes(posted, "reader"))
        assertFalse(AO3PromptMemeFilter.Yours.includes(posted, ""))
        assertFalse(AO3PromptMemeFilter.Yours.includes(first[3].copy(ownerPseud = "AO3_Reader"), "AO3_Reader"))
    }

    @Test fun recognizedEmptyMalformedAndNegativeFallbackFollowIosParser() {
        assertTrue(parser.parse("<h2 class='heading'>Prompts</h2>").prompts.isEmpty())
        assertTrue(parser.parse("<p class='note'>Nothing here yet</p>").prompts.isEmpty())
        assertThrows(IllegalArgumentException::class.java) { parser.parse("<html>unexpected page</html>") }
        assertThrows(IllegalArgumentException::class.java) { parser.parse("<h2 class='heading'>Prompts</h2><form action='/users/login'></form>") }
        val card = parser.parse("<ul class='prompt index'><li class='blurb'><blockquote class='userstuff summary'>No heading</blockquote></li></ul>").prompts.single()
        assertEquals(-1, card.id)
        assertNull(card.displayedOwner)
        assertFalse(card.canClaim)
        assertFalse(card.isClaimed)
        // Any-type choices can be bare li.tag; iOS preserves the words without adding category labels.
        val any = parser.parse("<ul class='prompt index'><li class='blurb'><ul class='tags'><li class='tag'>Any Relationship</li></ul></li></ul>").prompts.single()
        assertEquals(listOf("Any Relationship"), any.tags)
    }

    @Test fun theCloseDateIsAskedForOnceAndOnlyForAnOwner() = runTest {
        // iOS's cases (PromptMemeFixtureTests, same name): AO3 serves the settings form to owners only.
        assertTrue(readsPromptMemeSchedule(viewerIsOwner = true, attempted = false, hasDate = false))
        assertFalse(readsPromptMemeSchedule(viewerIsOwner = true, attempted = true, hasDate = false))
        assertFalse(readsPromptMemeSchedule(viewerIsOwner = true, attempted = true, hasDate = true))
        assertFalse(readsPromptMemeSchedule(viewerIsOwner = true, attempted = false, hasDate = true))
        assertFalse(readsPromptMemeSchedule(viewerIsOwner = false, attempted = false, hasDate = false))
        // A participant or a moderator: the listing and nothing else, on opening, on a page and on a refresh.
        val (_, client, repository) = promptMemeSetup()
        val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = false, writes = promptMemeWrites(client, repository.authRepository))
        model.load(readSchedule = true)
        model.load(2)
        model.load(readSchedule = true)
        assertEquals(listOf(promptFirstUrl, promptSecondUrl, promptFirstUrl), client.gets)
        assertEquals("", model.state.value.closeDateText)
        assertEquals(0, client.posts)
    }

    @Test fun anOwnersOpeningIsThreeReadsAFurtherPageOneAndARefreshOneOnceTheDateIsKnown() = runTest {
        val (_, client, repository) = promptMemeSetup()
        val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = true, writes = promptMemeWrites(client, repository.authRepository))
        model.load(readSchedule = true)
        assertEquals(listOf(promptGiftUrl, promptSettingsUrl, promptFirstUrl), client.gets)
        assertTrue(model.state.value.closeDateText.startsWith("open until "))
        model.load(2)
        assertEquals(listOf(promptGiftUrl, promptSettingsUrl, promptFirstUrl, promptSecondUrl), client.gets)
        assertEquals(listOf(705, 706), model.state.value.data!!.prompts.map { it.id }) // replacement, not append
        model.load(readSchedule = true)
        // The date is known, so a refresh does not ask for it again.
        assertEquals(listOf(promptFirstUrl), client.gets.drop(4))
        assertTrue(client.headers.all { it["Cookie"].orEmpty().isNotEmpty() })
        assertTrue(client.gets.none { it.contains("/profile") || it.contains("/signups") || it.contains("/claims") })
        assertEquals(0, client.posts)
    }

    @Test fun failedOrMissingScheduleIsSilentAndNeverRetriedByAPageOrListingRetry() = runTest {
        for (missing in listOf(false, true)) {
            val (_, client, repository) = promptMemeSetup()
            client.replies[promptSettingsUrl] = if (missing) challengeResponse(promptSettingsUrl,
                "<main id='main'><form action='/collections/summer_meme/prompt_meme'><input name='authenticity_token' value='local'></form></main>")
            else AO3Result.Failure(AO3Error.Forbidden)
            val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = true, writes = promptMemeWrites(client, repository.authRepository))
            model.load(readSchedule = true)
            assertEquals("", model.state.value.closeDateText)
            assertNull(model.state.value.failure)
            assertEquals(3, client.gets.size)
            model.load(2)
            assertEquals(listOf(promptSecondUrl), client.gets.drop(3))
            client.replies.remove(promptSettingsUrl)
            model.load(readSchedule = true)
            assertTrue(model.state.value.closeDateText.isNotEmpty())
            assertEquals(7, client.gets.size)
            assertEquals(0, client.posts)
        }
    }

    @Test fun unparsedNonemptyCloseDateKeepsIosVerbatimWords() = runTest {
        val (_, client, repository) = promptMemeSetup()
        client.replies[promptSettingsUrl] = challengeResponse(promptSettingsUrl,
            challengeFixture("ao3_demo_meme_settings").replace("2026-06-30 00:00:00", "After the last lantern"))
        val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = true, writes = promptMemeWrites(client, repository.authRepository))
        model.load(readSchedule = true)
        assertEquals("open until After the last lantern", model.state.value.closeDateText)
    }

    @Test fun scheduleNonFallbackErrorStopsOnlyScheduleListingStillLoads() = runTest {
        val (_, client, repository) = promptMemeSetup()
        client.replies[promptGiftUrl] = AO3Result.Failure(AO3Error.Forbidden)
        val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = true, writes = promptMemeWrites(client, repository.authRepository))
        model.load(readSchedule = true)
        assertEquals(listOf(promptGiftUrl, promptFirstUrl), client.gets)
        assertEquals("", model.state.value.closeDateText)
        assertEquals(4, model.state.value.data!!.prompts.size)
        assertNull(model.state.value.failure)
    }

    @Test fun failedPageRetainsRowsCountsAndCurrentPageAndAnExplicitRetryHasOneRead() = runTest {
        val (_, client, repository) = promptMemeSetup()
        val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = true, writes = promptMemeWrites(client, repository.authRepository))
        model.load(readSchedule = true)
        val old = model.state.value.data
        client.replies[promptSecondUrl] = AO3Result.Failure(AO3Error.Forbidden)
        model.load(2)
        assertEquals(old, model.state.value.data)
        assertEquals(1, model.state.value.data!!.currentPage)
        assertEquals("AO3 refused the request (HTTP 403). Wait a while before trying again.", model.state.value.failure)
        client.replies.remove(promptSecondUrl)
        model.load(2)
        assertEquals(2, model.state.value.data!!.currentPage)
        assertNull(model.state.value.failure)
        assertEquals(listOf(promptSecondUrl, promptSecondUrl), client.gets.drop(3))
        assertEquals(0, client.posts)
    }

    @Test fun initialListingFailureAndRetryPreserveDateAndSendNoScheduleRetry() = runTest {
        val (_, client, repository) = promptMemeSetup()
        client.replies[promptFirstUrl] = AO3Result.Failure(AO3Error.NotFound)
        val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = true, writes = promptMemeWrites(client, repository.authRepository))
        model.load(readSchedule = true)
        assertNull(model.state.value.data)
        assertNotNull(model.state.value.failure)
        assertTrue(model.state.value.closeDateText.isNotEmpty())
        client.replies.remove(promptFirstUrl)
        model.load()
        assertEquals(listOf(promptFirstUrl), client.gets.drop(3))
        assertNotNull(model.state.value.data)
    }

    @Test fun signedOutReadsPublicListingAndOnlyPublicListingOnFurtherPage() = runTest {
        val (_, client, repository) = promptMemeSetup(signedIn = false)
        val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = true, writes = promptMemeWrites(client, repository.authRepository))
        model.load(readSchedule = true)
        assertEquals(listOf(promptFirstUrl), client.gets)
        assertEquals("", model.state.value.closeDateText)
        assertNull(model.state.value.failure)
        model.load(2)
        assertEquals(listOf(promptFirstUrl, promptSecondUrl), client.gets)
        assertTrue(client.headers.all { it.isEmpty() })
        assertEquals(0, client.posts)
    }

    @Test fun sessionChangeAtEachReadRetiresOldResultAndDoesNotContinueAnonymously() = runTest {
        for (read in listOf(promptGiftUrl, promptSettingsUrl, promptFirstUrl)) {
            val (auth, client, repository) = promptMemeSetup()
            client.afterGet = { if (it == read) auth.logout() }
            val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = true, writes = promptMemeWrites(client, repository.authRepository))
            val load = async { model.load(readSchedule = true) }
            runCatching { load.await() }
            assertTrue(load.isCancelled)
            assertEquals(read, client.gets.last())
            assertNull(model.state.value.data)
        }
    }

    @Test fun duplicateLoadAndDepartureCannotStartAnotherRead() = runTest {
        val (_, client, repository) = promptMemeSetup()
        client.hold = true
        val model = AO3PromptMemeState("summer_meme", repository, viewerIsOwner = true, writes = promptMemeWrites(client, repository.authRepository))
        val load = async { model.load(readSchedule = true) }
        client.entered.await()
        model.load(2)
        assertEquals(listOf(promptGiftUrl), client.gets)
        model.close()
        runCatching { load.await() }
        assertTrue(load.isCancelled)
        assertEquals(listOf(promptGiftUrl), client.gets)
        assertNull(model.state.value.data)
    }

    @Test fun addressesEncodeSlugAndFillOpensMemeNotRequests() {
        assertTrue(AO3PromptMemeUrls.requests("a/b", 2).contains("a%2Fb/requests?page=2"))
        assertEquals("https://archiveofourown.org/collections/summer_meme/prompt_meme", AO3PromptMemeUrls.meme("summer_meme"))
    }
}

internal val promptGiftUrl = ChallengeSettingsDestinations.challengeSettingsEditView("summer_meme", AO3ChallengeKind.GiftExchange)
internal val promptSettingsUrl = ChallengeSettingsDestinations.challengeSettingsEditView("summer_meme", AO3ChallengeKind.PromptMeme)
internal val promptFirstUrl = AO3PromptMemeUrls.requests("summer_meme")
internal val promptSecondUrl = AO3PromptMemeUrls.requests("summer_meme", 2)

internal suspend fun promptMemeSetup(signedIn: Boolean = true): Triple<AO3AuthRepository, PromptMemeReadClient, AO3CollectionDetailRepository> {
    val auth = AO3AuthRepository(MemorySessionStore(if (signedIn) testSession() else null), MemoryCookieStore())
    auth.restoreSession()
    val client = PromptMemeReadClient()
    return Triple(auth, client, AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined))
}

internal fun promptMemeWrites(client: PromptMemeReadClient, auth: AO3AuthRepository) =
    AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))

internal data class PromptMemePost(val url: String, val fields: List<Pair<String, String>>, val headers: Map<String, String>)

internal class PromptMemeReadClient : AO3Client, AO3FormPostClient {
    val gets = mutableListOf<String>()
    val headers = mutableListOf<Map<String, String>>()
    val replies = mutableMapOf<String, AO3Result<AO3HttpResponse>>()
    var posts = 0
    val sent = mutableListOf<PromptMemePost>()
    var postReply: AO3Result<AO3HttpResponse>? = null
    var holdPost = false
    val postEntered = CompletableDeferred<Unit>()
    val postRelease = CompletableDeferred<Unit>()
    var afterPost: suspend () -> Unit = {}
    var afterGet: suspend (String) -> Unit = {}
    var hold = false
    val entered = CompletableDeferred<Unit>()
    val release = CompletableDeferred<Unit>()
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url
        this.headers += headers
        entered.complete(Unit)
        if (hold) release.await()
        afterGet(url)
        return replies[url] ?: when (url) {
            promptGiftUrl -> AO3Result.Failure(AO3Error.NotFound)
            promptSettingsUrl -> challengeResponse(url, challengeFixture("ao3_demo_meme_settings"))
            AO3PromptMemeUrls.claims("summer_meme", forUser = true) -> challengeResponse(url, "<meta name='csrf-token' content='fresh-release'>")
            promptFirstUrl -> challengeResponse(url, challengeFixture("ao3_demo_meme_requests_1"))
            promptSecondUrl -> challengeResponse(url, challengeFixture("ao3_demo_meme_requests_2"))
            else -> error("Unexpected prompts read: $url")
        }
    }
    override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts++
        sent += PromptMemePost(url, formFields.toList(), headers.toMap())
        postEntered.complete(Unit)
        if (holdPost) postRelease.await()
        afterPost()
        return postReply ?: error("Prompt Meme reading must never POST")
    }
}
