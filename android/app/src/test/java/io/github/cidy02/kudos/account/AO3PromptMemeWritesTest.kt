package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AO3PromptMemeWritesTest {
    private val unconfirmed = "AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."
    private val missingToken = "Couldn't prepare the request. Try again, or open the work on AO3."
    private fun tokenUrl(release: Boolean) = if (release) AO3PromptMemeUrls.claims("summer_meme", forUser = true) else promptFirstUrl
    private fun result(status: Int, body: String) = AO3Result.Success(AO3HttpResponse(AO3PromptMemeUrls.claims("summer_meme"), status, emptyMap(), body))
    private suspend fun action(model: AO3PromptMemeState, release: Boolean) {
        if (release) model.release(702) else model.claim(701)
    }

    @Test fun eachWriteHasExactlyIosOrderedFieldsFreshTokenRefererAndOnePost() = runTest {
        for (release in listOf(false, true)) {
            val (auth, client, _) = promptMemeSetup()
            val writes = promptMemeWrites(client, auth)
            client.replies[tokenUrl(release)] = challengeResponse(tokenUrl(release),
                "<meta name='csrf-token' content='fresh &amp; 雪'><input name='authenticity_token' value='stale'>")
            client.postReply = result(200, "<div class='flash notice'>Confirmed.</div>")
            val answer = if (release) writes.releasePrompt("summer_meme", 801, auth.generation.value)
                else writes.claimPrompt("summer_meme", 701, auth.generation.value)
            assertTrue(answer is AO3Result.Success)
            assertEquals(listOf(tokenUrl(release)), client.gets)
            assertEquals(1, client.posts)
            val post = client.sent.single()
            assertEquals(if (release) AO3PromptMemeUrls.claim("summer_meme", 801) else AO3PromptMemeUrls.claims("summer_meme"), post.url)
            assertEquals(if (release) listOf("_method" to "delete", "authenticity_token" to "fresh & 雪")
                else listOf("authenticity_token" to "fresh & 雪", "prompt_id" to "701"), post.fields)
            assertEquals("fresh & 雪", post.headers["X-CSRF-Token"])
            assertEquals(tokenUrl(release), post.headers["Referer"])
            assertTrue(post.headers["Cookie"].orEmpty().isNotEmpty())
            assertFalse(post.headers.containsKey("X-Requested-With"))
            assertFalse(post.headers.containsKey("Accept"))
        }
    }

    @Test fun allIosVerdictsKeepOldCardsAndWordsOrReadCurrentPageOnce() = runTest {
        for (release in listOf(false, true)) for ((status, html, reason) in listOf(
            Triple(200, "<div class='flash notice'>Confirmed.</div>", null),
            Triple(302, "", null),
            Triple(200, "<div class='flash error'>This prompt is closed.</div>", "This prompt is closed."),
            Triple(302, "<div class='flash notice'>Saved.</div><div class='flash error'>Refused.</div>", "Refused."),
            Triple(200, "<p>No confirmation.</p>", unconfirmed),
            Triple(422, "", "AO3 couldn't ${if (release) "release" else "claim"} that prompt.")
        )) {
            val (auth, client, repo) = promptMemeSetup()
            val model = AO3PromptMemeState("summer_meme", repo, false, promptMemeWrites(client, auth))
            model.load(readSchedule = true)
            val old = model.state.value.data
            val before = client.gets.size
            client.postReply = result(status, html)
            action(model, release)
            assertEquals(old, model.state.value.data) // served reload is deliberately unchanged in this test
            assertNull(model.state.value.promptInFlight)
            assertEquals(1, client.posts)
            assertEquals(if (reason == null) listOf(tokenUrl(release), promptFirstUrl) else listOf(tokenUrl(release)), client.gets.drop(before))
            assertEquals(reason?.let { "Couldn't ${if (release) "release" else "claim"} that prompt: $it" }, model.state.value.actionError)
            model.dismissActionError()
            assertNull(model.state.value.actionError)
        }
    }

    @Test fun tokenFailureMissingMetaAndSignedOutSendNoPostAndKeepExactWords() = runTest {
        for (release in listOf(false, true)) for (kind in 0..2) {
            val (auth, client, repo) = promptMemeSetup(signedIn = kind != 2)
            val model = AO3PromptMemeState("summer_meme", repo, false, promptMemeWrites(client, auth))
            model.load()
            val old = model.state.value.data
            val before = client.gets.size
            client.replies[tokenUrl(release)] = if (kind == 0) AO3Result.Failure(AO3Error.Forbidden)
                else challengeResponse(tokenUrl(release), "<input name='authenticity_token' value='input-only'>")
            action(model, release)
            val reason = when (kind) {
                0 -> "AO3 refused the request (HTTP 403). Wait a while before trying again."
                1 -> missingToken
                else -> "Log in to AO3 first."
            }
            assertEquals("Couldn't ${if (release) "release" else "claim"} that prompt: $reason", model.state.value.actionError)
            assertEquals(old, model.state.value.data)
            assertEquals(if (kind == 2) emptyList<String>() else listOf(tokenUrl(release)), client.gets.drop(before))
            assertEquals(0, client.posts)
        }
    }

    @Test fun confirmationReloadIsOneCurrentPageAndNeverScheduleForOwnerOrParticipantWithOrWithoutDate() = runTest {
        for (owner in listOf(false, true)) for (missingDate in listOf(false, true)) for (release in listOf(false, true)) {
            val (auth, client, repo) = promptMemeSetup()
            if (missingDate) client.replies[promptSettingsUrl] = AO3Result.Failure(AO3Error.Forbidden)
            val model = AO3PromptMemeState("summer_meme", repo, owner, promptMemeWrites(client, auth))
            model.load(readSchedule = true)
            model.load(2)
            // Test both actions on page two, not the token page's page one.
            val doc = Jsoup.parse(challengeFixture("ao3_demo_meme_requests_2"))
            if (release) doc.selectFirst("li.blurb")!!.append("<a href='/collections/summer_meme/claims/805' data-method='delete'>Drop Claim</a>")
            client.replies[promptSecondUrl] = challengeResponse(promptSecondUrl, doc.outerHtml())
            model.load(2)
            val before = client.gets.size
            client.postReply = result(200, "<div class='flash notice'>Confirmed.</div>")
            if (release) model.release(705) else model.claim(705)
            assertEquals(listOf(tokenUrl(release), promptSecondUrl), client.gets.drop(before))
            assertEquals(2, model.state.value.data!!.currentPage)
            assertEquals(1, client.posts)
        }
    }

    @Test fun heldPostAndReloadKeepCardsAndBlockEveryOtherActionRefreshAndPage() = runTest {
        for (release in listOf(false, true)) {
            val (auth, client, repo) = promptMemeSetup()
            val model = AO3PromptMemeState("summer_meme", repo, true, promptMemeWrites(client, auth))
            model.load(readSchedule = true)
            val old = model.state.value.data
            client.holdPost = true
            client.postReply = result(200, "<div class='flash notice'>Confirmed.</div>")
            client.afterPost = { client.hold = true }
            val job = async { action(model, release) }
            client.postEntered.await()
            assertEquals(if (release) 702 else 701, model.state.value.promptInFlight)
            assertEquals(old, model.state.value.data)
            model.claim(704); model.release(702); model.load(2); model.load(readSchedule = true)
            assertEquals(1, client.posts)
            assertEquals(4, client.gets.size)
            client.postRelease.complete(Unit)
            runCurrent()
            assertTrue(model.state.value.loading)
            assertEquals(old, model.state.value.data)
            assertNotNull(model.state.value.promptInFlight)
            val doc = Jsoup.parse(challengeFixture("ao3_demo_meme_requests_1"))
            if (release) doc.select("a[data-method=delete]").remove()
            else doc.selectFirst("li.blurb")!!.append("<a href='/collections/summer_meme/claims/1701' data-method='delete'>Drop Claim</a>")
            client.replies[promptFirstUrl] = challengeResponse(promptFirstUrl, doc.outerHtml())
            client.release.complete(Unit)
            job.await()
            assertEquals(!release, model.state.value.data!!.prompts.first { it.id == if (release) 702 else 701 }.claimedByCurrentUser)
            assertNull(model.state.value.promptInFlight)
            assertEquals(listOf(tokenUrl(release), promptFirstUrl), client.gets.drop(3))
        }
    }

    @Test fun confirmedWriteWithFailedReloadKeepsOldCardAndShowsPageFailureWithoutAnotherPost() = runTest {
        val (auth, client, repo) = promptMemeSetup()
        val model = AO3PromptMemeState("summer_meme", repo, true, promptMemeWrites(client, auth))
        model.load(readSchedule = true)
        val old = model.state.value.data
        client.postReply = result(200, "<div class='flash notice'>Confirmed.</div>")
        client.afterPost = { client.replies[promptFirstUrl] = AO3Result.Failure(AO3Error.Forbidden) }
        model.claim(701)
        assertEquals(old, model.state.value.data)
        assertNotNull(model.state.value.failure)
        assertNull(model.state.value.actionError)
        assertEquals(1, client.posts)
        assertEquals(listOf(promptFirstUrl, promptFirstUrl), client.gets.drop(3))
    }

    @Test fun noPostOnOpeningPageOrRefreshAndUnavailableControlsDoNothing() = runTest {
        val (auth, client, repo) = promptMemeSetup()
        val model = AO3PromptMemeState("summer_meme", repo, true, promptMemeWrites(client, auth))
        model.load(readSchedule = true)
        model.claim(703); model.claim(702); model.release(701); model.release(-1)
        model.load(2); model.load(readSchedule = true)
        assertEquals(listOf(promptGiftUrl, promptSettingsUrl, promptFirstUrl, promptSecondUrl, promptFirstUrl), client.gets)
        assertEquals(0, client.posts)
    }

    @Test fun sessionChangeDuringPreparationOrDepartureDuringSentPostCannotReloadOrPublish() = runTest {
        for (release in listOf(false, true)) for (duringPost in listOf(false, true)) {
            val (auth, client, repo) = promptMemeSetup()
            val model = AO3PromptMemeState("summer_meme", repo, false, promptMemeWrites(client, auth))
            model.load()
            val old = model.state.value.data
            client.postReply = result(200, "<div class='flash notice'>Confirmed.</div>")
            if (!duringPost) client.afterGet = { auth.logout() }
            else client.holdPost = true
            val job = async { action(model, release) }
            if (duringPost) {
                client.postEntered.await()
                model.close()
                client.postRelease.complete(Unit)
            }
            runCatching { job.await() }
            assertTrue(job.isCancelled)
            assertEquals(if (duringPost) 1 else 0, client.posts)
            assertEquals(old, model.state.value.data)
            assertNull(model.state.value.actionError)
            assertEquals(listOf(promptFirstUrl, tokenUrl(release)), client.gets)
        }
    }

    @Test fun pageDerivedForeignOrInsecureControlsAreNotAccepted() {
        for (base in listOf("https://archiveofourown.org.evil.test", "https://elsewhere.test", "http://archiveofourown.org")) {
            val html = challengeFixture("ao3_demo_meme_requests_1")
                .replace("action=\"/collections", "action=\"$base/collections")
                .replace("href=\"/collections/summer_meme/claims/", "href=\"$base/collections/summer_meme/claims/")
            val prompts = AO3PromptMemeParser().parse(html).prompts
            assertTrue(prompts.none { it.canClaim || it.claimedByCurrentUser })
        }
    }

    @Test fun sharedWireEncodingHeadersAndNoRetryOn429Or503ForEitherWrite() = runTest {
        for (release in listOf(false, true)) for (status in listOf(200, 429, 503)) {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
            auth.restoreSession()
            val requests = CopyOnWriteArrayList<Request>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request(); requests += request
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                    .code(if (request.method == "GET") 200 else status).message("Local answer")
                    .body((if (request.method == "GET") "<meta name='csrf-token' content='fresh &amp; token'>"
                        else "<div class='flash notice'>Confirmed.</div>").toResponseBody()).build()
            }.addInterceptor { throw AssertionError("Test attempted a socket request") }.build()
            val wire = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
            val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(wire, wire, auth))
            val answer = if (release) writes.releasePrompt("summer_meme", 801, auth.generation.value)
                else writes.claimPrompt("summer_meme", 701, auth.generation.value)
            assertEquals(status == 200, answer is AO3Result.Success)
            assertEquals(listOf("GET", "POST"), requests.map { it.method })
            val post = requests.last()
            assertEquals(tokenUrl(release), requests.first().url.toString())
            assertEquals(AO3UserAgent.VALUE, post.header("User-Agent"))
            assertTrue(post.header("Cookie").orEmpty().isNotEmpty())
            assertEquals("fresh & token", post.header("X-CSRF-Token"))
            assertEquals(tokenUrl(release), post.header("Referer"))
            assertNull(post.header("X-Requested-With")); assertNull(post.header("Accept"))
            assertEquals("application/x-www-form-urlencoded; charset=UTF-8", post.body!!.contentType().toString())
            val buffer = Buffer(); post.body!!.writeTo(buffer)
            assertEquals(if (release) "_method=delete&authenticity_token=fresh%20%26%20token"
                else "authenticity_token=fresh%20%26%20token&prompt_id=701", buffer.readUtf8())
        }
    }

    @Test fun sharedPacingFenceCancelsEitherPostIfThePreparingSessionChanges() = runTest {
        for (release in listOf(false, true)) {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
            auth.restoreSession()
            val methods = CopyOnWriteArrayList<String>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                methods += chain.request().method
                Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("Local answer")
                    .body("<meta name='csrf-token' content='fresh'>".toResponseBody()).build()
            }.addInterceptor { throw AssertionError("Test attempted a socket request") }.build()
            val config = AO3NetworkConfig(minDelayBetweenRequestsMillis = 600)
            var paced = false
            val coordinator = AO3RequestCoordinator(config, AO3Clock { 0 }, AO3Delay { paced = true; auth.logout() })
            val client = OkHttpAO3Client(http, config, coordinator)
            val writes = AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth))
            try {
                if (release) writes.releasePrompt("summer_meme", 801, auth.generation.value)
                else writes.claimPrompt("summer_meme", 701, auth.generation.value)
                fail("A stale prepared write must not dispatch")
            } catch (_: kotlinx.coroutines.CancellationException) { }
            assertTrue(paced)
            assertEquals(listOf("GET"), methods)
        }
    }
}
