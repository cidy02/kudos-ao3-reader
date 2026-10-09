package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
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
class AO3ChallengeWithdrawTest {
    @Test fun everyVerdictIsShownAloneOneFreshConfirmReadOnePostErrorsWinAndTypedFormStays() = runTest {
        for ((status, body, message) in listOf(
            Triple(200, challengeFixture("ao3_demo_signup_withdrawn"), null),
            Triple(302, "", null),
            Triple(422, challengeFixture("ao3_demo_signup_withdraw_refused"), "Sign-ups are closed. You cannot delete your sign-up."),
            Triple(302, "<div class='flash notice'>Deleted.</div><div class='flash error'>AO3's exact reason.</div>", "AO3's exact reason."),
            Triple(200, "<p>Unconfirmed</p>", AO3CollectionFields.UNCONFIRMED),
            Triple(422, "<p>Refused without reason</p>", "AO3 couldn't withdraw that sign-up.")
        )) {
            val (auth, client, repo) = withdrawalSetup()
            val model = AO3ChallengeSignUpState("winter_exchange", 4, repo, promptMemeWrites(client, auth))
            model.load()
            model.update(model.state.value.form!!.requests.first().copy(description = "Typed text & 星", title = "Typed title"))
            val typed = model.state.value.form!!
            client.postReply = AO3Result.Success(AO3HttpResponse(withdrawAction, status, emptyMap(), body))
            model.withdraw()
            assertEquals(listOf(withdrawForm, withdrawConfirm), client.gets)
            assertEquals(1, client.posts)
            val post = client.sent.single()
            assertEquals(withdrawAction, post.url)
            assertEquals(listOf("_method" to "delete", "authenticity_token" to "withdraw-4-fresh"), post.fields)
            assertEquals("withdraw-4-fresh", post.headers["X-CSRF-Token"])
            assertEquals(withdrawConfirm, post.headers["Referer"])
            assertTrue(post.headers["Cookie"].orEmpty().isNotEmpty())
            assertFalse(post.headers.containsKey("Accept")); assertFalse(post.headers.containsKey("X-Requested-With"))
            assertEquals(typed.requests, model.state.value.form!!.requests)
            assertEquals(typed.offers, model.state.value.form!!.offers)
            assertEquals(typed.servedControls, model.state.value.form!!.servedControls)
            assertEquals(message == null, model.state.value.withdrawn)
            assertEquals(if (message == null) "Sign-up withdrawn." else null, model.state.value.notice)
            assertEquals(if (message == null) typed.generalErrors else listOf(message), model.state.value.form!!.generalErrors)
            assertFalse(model.state.value.withdrawing)
        }
    }

    @Test fun failedOrMissingMetaTokenAndSignedOutSendNothingWithBusyCleared() = runTest {
        for (problem in listOf("403", "missingMeta", "signedOut")) {
            val (auth, client, repo) = withdrawalSetup(signedIn = problem != "signedOut")
            val model = AO3ChallengeSignUpState("winter_exchange", 4, repo, promptMemeWrites(client, auth))
            model.load()
            if (problem != "signedOut") client.replies[withdrawConfirm] = if (problem == "403") AO3Result.Failure(AO3Error.Forbidden)
                else challengeResponse(withdrawConfirm, "<input name='authenticity_token' value='input-only'>")
            model.withdraw()
            assertEquals(if (problem == "signedOut") emptyList<String>() else listOf(withdrawForm, withdrawConfirm), client.gets)
            assertEquals(0, client.posts)
            assertFalse(model.state.value.withdrawing)
            assertNull(model.state.value.notice)
            if (problem == "missingMeta") assertEquals(listOf("Couldn't prepare the request. Try again, or open the work on AO3."), model.state.value.form!!.generalErrors)
            if (problem == "403") {
                assertEquals(listOf("AO3 refused the request (HTTP 403). Wait a while before trying again."), model.state.value.form!!.generalErrors)
                model.withdraw(); model.load(refresh = true)
                assertEquals(listOf(withdrawForm, withdrawConfirm), client.gets)
            }
            if (problem == "signedOut") {
                val answer = promptMemeWrites(client, auth).withdrawSignUp("winter_exchange", 4, auth.generation.value)
                assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), answer)
                assertTrue(client.gets.isEmpty())
            }
        }
    }

    @Test fun sessionMovingBeforePostCancelsDispatchAfterPostIsUnconfirmedAndEveryActiveBusyFlagClears() = runTest {
        for (afterPost in listOf(false, true)) {
            val (auth, client, repo) = withdrawalSetup()
            val model = AO3ChallengeSignUpState("winter_exchange", 4, repo, promptMemeWrites(client, auth))
            model.load()
            val original = model.state.value.form
            if (afterPost) client.afterPost = { auth.logout() } else client.afterGet = { if (it == withdrawConfirm) auth.logout() }
            client.postReply = challengeResponse(withdrawAction, challengeFixture("ao3_demo_signup_withdrawn"))
            model.withdraw()
            assertEquals(listOf(withdrawForm, withdrawConfirm), client.gets)
            assertEquals(if (afterPost) 1 else 0, client.posts)
            assertFalse(model.state.value.withdrawing)
            assertFalse(model.state.value.withdrawn)
            assertNull(model.state.value.notice)
            assertEquals(original!!.requests, model.state.value.form!!.requests)
            assertEquals(if (afterPost) listOf(AO3CollectionFields.UNCONFIRMED) else original.generalErrors,
                model.state.value.form!!.generalErrors)
        }
        // A stale entry never prepares a token, even with a replacement signed-in session.
        val (auth, client, _) = withdrawalSetup()
        val old = auth.generation.value
        auth.logout()
        assertTrue(runCatching { promptMemeWrites(client, auth).withdrawSignUp("winter_exchange", 4, old) }.isFailure)
        assertTrue(client.gets.isEmpty()); assertEquals(0, client.posts)
    }

    @Test fun waitingWithdrawDisablesDuplicatesEditsSaveRefreshAndCloseNeverInstallsResult() = runTest {
        val (auth, client, repo) = withdrawalSetup()
        val model = AO3ChallengeSignUpState("winter_exchange", 4, repo, promptMemeWrites(client, auth))
        model.load()
        val original = model.state.value.form!!
        client.hold = true; client.holdPost = true
        client.postReply = challengeResponse(withdrawAction, challengeFixture("ao3_demo_signup_withdrawn"))
        val task = async { model.withdraw() }
        runCurrent()
        assertTrue(model.state.value.withdrawing)
        model.withdraw(); model.save(); model.load(refresh = true)
        model.update(original.requests.first().copy(description = "Must not replace text"))
        assertEquals(original, model.state.value.form)
        client.release.complete(Unit)
        client.postEntered.await()
        model.withdraw()
        assertEquals(1, client.posts)
        client.postRelease.complete(Unit); task.await()
        assertFalse(model.state.value.withdrawing)
        model.withdraw(); assertEquals(1, client.posts)
        assertEquals(listOf(withdrawForm, withdrawConfirm), client.gets)
        val (otherAuth, other, otherRepo) = withdrawalSetup()
        val departed = AO3ChallengeSignUpState("winter_exchange", 4, otherRepo, promptMemeWrites(other, otherAuth))
        departed.load(); other.hold = true
        val pending = async { departed.withdraw() }; runCurrent(); departed.close()
        runCatching { pending.await() }
        assertEquals(0, other.posts); assertFalse(departed.state.value.withdrawn)
    }

    @Test fun reloadKeepsTypedPromptsTargetAndEveryCarriedControlAndNeverPosts() = runTest {
        val (auth, client, repo) = withdrawalSetup()
        val model = AO3ChallengeSignUpState("winter_exchange", 4, repo, promptMemeWrites(client, auth))
        model.load()
        model.update(model.state.value.form!!.requests.first().copy(description = "A writer's unfinished prompt"))
        model.add(SignUpPromptKind.Request)
        val typed = model.state.value.form
        model.load(refresh = true)
        assertEquals(typed, model.state.value.form)
        assertEquals(listOf(withdrawForm, withdrawForm), client.gets)
        assertEquals(0, client.posts)
    }

    @Test fun realWireHasExactIosBodyHeadersAndNoRetryOn429Or503() = runTest {
        for (status in listOf(200, 429, 503)) {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
            auth.restoreSession()
            val seen = CopyOnWriteArrayList<Request>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request(); seen += request
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1).message("Local withdrawal")
                    .code(if (request.method == "GET") 200 else status)
                    .body((if (request.method == "GET") "<meta name='csrf-token' content='fresh &amp; token+/='>"
                        else challengeFixture("ao3_demo_signup_withdrawn")).toResponseBody()).build()
            }.addInterceptor { throw AssertionError("Withdrawal attempted a socket") }.build()
            val wire = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
            val answer = AO3WriteRepository(DefaultAO3AuthenticatedClient(wire, wire, auth)).withdrawSignUp("winter_exchange", 4, auth.generation.value)
            assertEquals(status == 200, answer is AO3Result.Success)
            assertEquals(listOf("GET", "POST"), seen.map { it.method })
            assertEquals(withdrawConfirm, seen.first().url.toString())
            val post = seen.last()
            assertEquals(withdrawAction, post.url.toString())
            assertEquals(AO3UserAgent.VALUE, post.header("User-Agent"))
            assertTrue(post.header("Cookie").orEmpty().isNotEmpty())
            assertEquals("fresh & token+/=", post.header("X-CSRF-Token"))
            assertEquals(withdrawConfirm, post.header("Referer"))
            assertNull(post.header("X-Requested-With")); assertNull(post.header("Accept"))
            assertEquals("application/x-www-form-urlencoded; charset=UTF-8", post.body!!.contentType().toString())
            val buffer = Buffer(); post.body!!.writeTo(buffer)
            assertEquals("_method=delete&authenticity_token=fresh%20%26%20token%2B%2F%3D", buffer.readUtf8())
        }
    }
}

internal val withdrawForm = AO3ChallengeSignUpUrls.form("winter_exchange", 4)
internal val withdrawConfirm = AO3ChallengeSignUpUrls.confirmDelete("winter_exchange", 4)
internal val withdrawAction = AO3ChallengeSignUpUrls.signUp("winter_exchange", 4)
internal suspend fun withdrawalSetup(signedIn: Boolean = true) = promptMemeSetup(signedIn).also { (_, client, _) ->
    client.replies[withdrawForm] = challengeResponse(withdrawForm, challengeFixture("ao3_demo_signup_winter_edit"))
    client.replies[withdrawConfirm] = challengeResponse(withdrawConfirm, challengeFixture("ao3_demo_signup_4_confirm_delete"))
}
