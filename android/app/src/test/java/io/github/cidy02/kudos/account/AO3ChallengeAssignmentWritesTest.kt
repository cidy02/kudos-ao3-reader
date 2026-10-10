package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

@OptIn(ExperimentalCoroutinesApi::class)
class AO3ChallengeAssignmentWritesTest {
    @Test fun bothWritesHaveExactlyIosFieldsAndVerdictsAloneOnlyConfirmedAnswersReloadLists() = runTest {
        for (kind in AssignmentWrite.entries) for ((status, body, message) in listOf(
            Triple(200, "<div class='flash notice'>Assignments updated.</div>", null), Triple(302, "", null),
            Triple(422, "<div class='flash error'>AO3's exact refusal.</div>", "AO3's exact refusal."),
            Triple(302, "<div class='flash notice'>Saved.</div><div class='flash error'>Error wins.</div>", "Error wins."),
            Triple(200, "<p>Nothing confirmed</p>", AO3CollectionFields.UNCONFIRMED),
            Triple(422, "<p>No specific reason</p>", if (kind == AssignmentWrite.Claim) "AO3 couldn't claim that pinch hit." else "AO3 couldn't record the default.")
        )) {
            val (auth, client, repo) = assignmentsSetup()
            val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, true, repo, promptMemeWrites(client, auth))
            model.load()
            val before = model.state.value.pages
            val row = if (kind == AssignmentWrite.Claim) model.state.value.unmatched.first() else model.state.value.reportable.first { it.id == 84 }
            model.select(kind, row)
            val tokenUrl = assignmentUrl(if (kind == AssignmentWrite.Claim) SignUpAssignmentList.Defaults else SignUpAssignmentList.Open)
            val token = if (kind == AssignmentWrite.Claim) "assignments-defaults-fresh" else "assignments-open-fresh"
            client.postReply = AO3Result.Success(AO3HttpResponse(assignmentAction, status, emptyMap(), body))
            val start = client.gets.size
            model.perform()
            assertEquals(listOf(tokenUrl) + if (message == null) assignmentReads + signUpsSettings else emptyList(), client.gets.drop(start))
            assertEquals(1, client.posts)
            val sent = client.sent.single()
            assertEquals(assignmentAction, sent.url)
            assertEquals(listOf("_method" to "put", "authenticity_token" to token,
                if (kind == AssignmentWrite.Claim) "cover_82" to "AO3_Reader" else "default_84" to "1"), sent.fields)
            assertEquals(tokenUrl, sent.headers["Referer"]); assertEquals(token, sent.headers["X-CSRF-Token"])
            assertTrue(sent.headers["Cookie"].orEmpty().isNotBlank())
            assertFalse(sent.headers.containsKey("Accept")); assertFalse(sent.headers.containsKey("X-Requested-With"))
            assertEquals(message, model.state.value.actionError)
            assertEquals(before, model.state.value.pages) // memory client serves unchanged pages, no optimistic mutation
            assertFalse(model.state.value.busy); assertFalse(model.state.value.loading)
        }
    }

    @Test fun failedTokenMissingMetaSignedOutAndSessionMovingBeforePostSendNothingBusyAlwaysClears() = runTest {
        for (kind in AssignmentWrite.entries) for (problem in listOf("failed", "missing", "before", "after")) {
            val (auth, client, repo) = assignmentsSetup()
            val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, true, repo, promptMemeWrites(client, auth))
            model.load()
            val before = model.state.value.pages
            model.select(kind, model.state.value.candidates(kind).first())
            val url = assignmentUrl(if (kind == AssignmentWrite.Claim) SignUpAssignmentList.Defaults else SignUpAssignmentList.Open)
            if (problem == "failed") client.replies[url] = AO3Result.Failure(AO3Error.Forbidden)
            if (problem == "missing") client.replies[url] = challengeResponse(url, "<input name='authenticity_token' value='input-only'>")
            if (problem == "before") client.afterGet = { if (it == url) auth.logout() }
            if (problem == "after") client.afterPost = { auth.logout() }
            client.postReply = challengeResponse(assignmentAction, "<div class='flash notice'>Assignments updated.</div>")
            val start = client.gets.size
            model.perform()
            assertEquals(listOf(url), client.gets.drop(start))
            assertEquals(if (problem == "after") 1 else 0, client.posts)
            assertEquals(before, model.state.value.pages); assertFalse(model.state.value.busy)
            assertEquals(when (problem) {
                "failed" -> "AO3 refused the request (HTTP 403). Wait a while before trying again."
                "missing" -> "Couldn't prepare the request. Try again, or open the work on AO3."
                "after" -> AO3CollectionFields.UNCONFIRMED
                else -> null
            }, model.state.value.actionError)
        }
        for (kind in AssignmentWrite.entries) {
            val (auth, client, _) = assignmentsSetup(false)
            val writer = promptMemeWrites(client, auth)
            val answer = if (kind == AssignmentWrite.Claim) writer.claimPinchHit("winter_exchange", 82, "AO3_Reader", auth.generation.value)
                else writer.markAssignmentDefaulted("winter_exchange", 84, auth.generation.value)
            assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), answer)
            assertTrue(client.gets.isEmpty()); assertEquals(0, client.posts)
        }
    }

    @Test fun postSessionRefusalKeepsRepositoryVerdictAloneAndStopsFurtherControls() = runTest {
        for (kind in AssignmentWrite.entries) {
            val (auth, client, repo) = assignmentsSetup()
            val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, true, repo, promptMemeWrites(client, auth))
            model.load(); model.select(kind, model.state.value.candidates(kind).first())
            client.postReply = AO3Result.Failure(AO3Error.AuthenticationRequired)
            model.perform()
            assertEquals(AO3Error.AuthenticationRequired.moderationMessage(), model.state.value.actionError)
            assertFalse(model.state.value.busy); assertTrue(model.state.value.terminal)
            assertEquals(1, client.posts); assertEquals(6, client.gets.size)
            model.pick(AssignmentWrite.Default); model.load(refresh = true)
            assertNull(model.state.value.picking); assertEquals(6, client.gets.size)
        }
    }

    @Test fun emptyBylineStaleEntryAndModeratorSendNoPreparationOrWrite() = runTest {
        val (auth, client, repo) = assignmentsSetup()
        val writes = promptMemeWrites(client, auth)
        assertEquals(AO3Result.Failure(AO3Error.Validation("Name a pinch hitter.")),
            writes.claimPinchHit("winter_exchange", 82, "  ", auth.generation.value))
        assertTrue(client.gets.isEmpty())
        val moderator = AO3ChallengeAssignmentsState("winter_exchange", false, true, true, repo, writes)
        moderator.load(); val count = client.gets.size
        moderator.select(AssignmentWrite.Claim, moderator.state.value.unmatched.first()); moderator.perform()
        assertEquals(count, client.gets.size); assertEquals(0, client.posts)
        val old = auth.generation.value; auth.logout()
        assertTrue(runCatching { writes.markAssignmentDefaulted("winter_exchange", 84, old) }.isFailure)
        assertEquals(count, client.gets.size); assertEquals(0, client.posts)
    }

    @Test fun inFlightWriteDisablesEveryOtherWriteAndRefreshPreservesTarget() = runTest {
        val (auth, client, repo) = assignmentsSetup()
        val model = AO3ChallengeAssignmentsState("winter_exchange", true, true, true, repo, promptMemeWrites(client, auth))
        model.load()
        model.select(AssignmentWrite.Claim, model.state.value.unmatched.first())
        val original = model.state.value.pending
        client.holdPost = true
        client.postReply = challengeResponse(assignmentAction, "<p>Unconfirmed</p>")
        val start = client.gets.size
        val task = async { model.perform() }; runCurrent()
        assertTrue(model.state.value.busy)
        model.perform(); model.pick(AssignmentWrite.Default)
        model.select(AssignmentWrite.Default, model.state.value.reportable.first())
        model.load(refresh = true); model.load(more = SignUpAssignmentList.Open); model.cancel()
        assertEquals(original, model.state.value.pending); assertNull(model.state.value.picking)
        assertEquals(listOf(assignmentUrl(SignUpAssignmentList.Defaults)), client.gets.drop(start))
        assertEquals(1, client.posts)
        client.postRelease.complete(Unit); task.await()
        assertFalse(model.state.value.busy); assertEquals(AO3CollectionFields.UNCONFIRMED, model.state.value.actionError)
    }

    @Test fun realEncodedWireHasHeadersTokenBodyAndExactlyOnePostEven429Or503() = runTest {
        for (kind in AssignmentWrite.entries) for (status in listOf(200, 429, 503)) {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore()); auth.restoreSession()
            val seen = CopyOnWriteArrayList<Request>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val req = chain.request(); seen += req
                Response.Builder().request(req).protocol(Protocol.HTTP_1_1).message("Local assignment")
                    .code(if (req.method == "GET") 200 else status)
                    .body((if (req.method == "GET") "<meta name='csrf-token' content='fresh &amp; token+/='><input name='authenticity_token' value='stale'>"
                        else "<div class='flash notice'>Assignments updated.</div>").toResponseBody()).build()
            }.addInterceptor { throw AssertionError("Assignment write attempted a socket") }.build()
            val wire = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
            val writer = AO3WriteRepository(DefaultAO3AuthenticatedClient(wire, wire, auth))
            val answer = if (kind == AssignmentWrite.Claim) writer.claimPinchHit("winter_exchange", 82, " AO3_Reader ", auth.generation.value)
                else writer.markAssignmentDefaulted("winter_exchange", 84, auth.generation.value)
            assertEquals(status == 200, answer is AO3Result.Success)
            assertEquals(listOf("GET", "POST"), seen.map { it.method })
            val referer = assignmentUrl(if (kind == AssignmentWrite.Claim) SignUpAssignmentList.Defaults else SignUpAssignmentList.Open)
            assertEquals(referer, seen.first().url.toString())
            val post = seen.last(); assertEquals(assignmentAction, post.url.toString())
            assertEquals(AO3UserAgent.VALUE, post.header("User-Agent")); assertTrue(post.header("Cookie").orEmpty().isNotEmpty())
            assertEquals(referer, post.header("Referer")); assertEquals("fresh & token+/=", post.header("X-CSRF-Token"))
            assertNull(post.header("Accept")); assertNull(post.header("X-Requested-With"))
            assertEquals("application/x-www-form-urlencoded; charset=UTF-8", post.body!!.contentType().toString())
            val buf = Buffer(); post.body!!.writeTo(buf)
            assertEquals("_method=put&authenticity_token=fresh%20%26%20token%2B%2F%3D&" +
                if (kind == AssignmentWrite.Claim) "cover_82=AO3_Reader" else "default_84=1", buf.readUtf8())
        }
    }
}
internal val assignmentAction = "${ChallengeSettingsDestinations.challengeAssignmentsView("winter_exchange")}/update_multiple"
