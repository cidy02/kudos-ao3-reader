package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AO3ChallengeSignUpWritesTest {
    @Test fun everyOpeningIsOneReadNoPostAndSavesAreOneFreshTokenReadOnePostWithIosHeaders() = runTest {
        for (fixture in signUpFixtures) {
            val (auth, client, repo) = promptMemeSetup()
            val form = signUpForm(fixture)
            val url = AO3ChallengeSignUpUrls.form(form.slug, form.signUpID)
            client.replies[url] = challengeResponse(url, challengeFixture(fixture))
            val model = AO3ChallengeSignUpState(form.slug, form.signUpID, repo, promptMemeWrites(client, auth))
            model.load(); model.load()
            assertEquals(listOf(url), client.gets)
            assertEquals(0, client.posts)
            client.replies[url] = challengeResponse(url, "<meta name='csrf-token' content='fresh &amp; 星'><input name='authenticity_token' value='stale'>")
            client.postReply = challengeResponse(form.actionUrl, challengeFixture("ao3_demo_signup_saved"))
            model.save()
            assertEquals(listOf(url, url), client.gets)
            assertEquals(1, client.posts)
            val post = client.sent.single()
            assertEquals(form.actionUrl, post.url)
            assertEquals(form.copy(token = "fresh & 星").parameters(), post.fields)
            assertEquals("fresh & 星", post.headers["X-CSRF-Token"])
            assertEquals(url, post.headers["Referer"])
            assertTrue(post.headers["Cookie"].orEmpty().isNotEmpty())
            assertFalse(post.headers.containsKey("X-Requested-With"))
            assertFalse(post.headers.containsKey("Accept"))
            assertEquals("Sign-up submitted successfully!", model.state.value.notice)
        }
    }

    @Test fun newRouteReturningExistingFormUsesEditForTheSaveToken() = runTest {
        val (auth, client, repo) = promptMemeSetup()
        val new = AO3ChallengeSignUpUrls.form("winter_exchange")
        val edit = AO3ChallengeSignUpUrls.form("winter_exchange", 4)
        client.replies[new] = challengeResponse(new, challengeFixture(signUpFixtures[1]))
        client.replies[edit] = challengeResponse(edit, "<meta name='csrf-token' content='fresh'>")
        client.postReply = challengeResponse(edit, "<div class='flash notice'>Confirmed.</div>")
        val model = AO3ChallengeSignUpState("winter_exchange", null, repo, promptMemeWrites(client, auth))
        model.load(); model.save()
        assertEquals(listOf(new, edit), client.gets)
        assertEquals(1, client.posts)
        assertEquals("put", client.sent.single().fields.first { it.first == "_method" }.second)
        for (fixture in signUpFixtures.take(2)) {
            val (fallbackAuth, fallbackClient, _) = promptMemeSetup()
            val form = signUpForm(fixture).copy(actionUrl = "")
            val referer = AO3ChallengeSignUpUrls.form(form.slug, form.signUpID)
            fallbackClient.replies[referer] = challengeResponse(referer, "<meta name='csrf-token' content='fresh'>")
            fallbackClient.postReply = challengeResponse(referer, "<div class='flash notice'>Saved.</div>")
            promptMemeWrites(fallbackClient, fallbackAuth).saveChallengeSignUp(form, fallbackAuth.generation.value)
            assertEquals("${AO3CollectionFormUrls.show(form.slug)}/signups" + (form.signUpID?.let { "/$it" } ?: ""), fallbackClient.sent.single().url)
            assertEquals(listOf(referer), fallbackClient.gets)
        }
    }

    @Test fun signedOutRefusedAndClosedLoadsRememberAttemptsAndNeverProbeAgain() = runTest {
        for (failure in listOf<AO3Error?>(null, AO3Error.Forbidden, AO3Error.Parse("Sign-ups closed"), AO3Error.Validation("Sign-ups closed"))) {
            val (auth, client, repo) = promptMemeSetup(signedIn = failure != null)
            val url = AO3ChallengeSignUpUrls.form("winter_exchange")
            if (failure != null) client.replies[url] = AO3Result.Failure(failure)
            val model = AO3ChallengeSignUpState("winter_exchange", null, repo, promptMemeWrites(client, auth))
            model.load(); model.load(); model.load(refresh = true); model.save()
            assertEquals(if (failure == null) emptyList<String>() else listOf(url), client.gets)
            assertEquals(0, client.posts)
            assertTrue(model.state.value.terminal)
            assertNotNull(model.state.value.failure)
        }
    }

    @Test fun eachLocalValidationBlocksTokenAndPostWithIosWords() = runTest {
        for (kind in SignUpPromptKind.entries) for (issue in listOf("minimum", "maximum", "tag")) {
            val (auth, client, _) = promptMemeSetup()
            var form = signUpForm()
            val range = if (kind == SignUpPromptKind.Request) form.limits!!.requests else form.limits!!.offers
            val prompt = form.live(kind).single()
            val list = when (issue) {
                "minimum" -> emptyList()
                "maximum" -> (0..range.last).map { prompt.copy(id = -(it + 1)) }
                else -> listOf(prompt.copy(tags = emptyMap()))
            }
            form = if (kind == SignUpPromptKind.Request) form.copy(requests = list) else form.copy(offers = list)
            val answer = promptMemeWrites(client, auth).saveChallengeSignUp(form, auth.generation.value)
            assertTrue(answer is AO3Result.Success)
            assertEquals(form.validated(), ((answer as AO3Result.Success).value as AO3SignUpSaveOutcome.Invalid).form)
            assertTrue(client.gets.isEmpty())
            assertEquals(0, client.posts)
        }
    }

    @Test fun allVerdictsHaveIosWordsErrorsWinNoPostRetryOrReadAfterwardsAndRefusalKeepsEveryTypedField() = runTest {
        val unconfirmed = AO3CollectionFields.UNCONFIRMED
        for ((status, body, errors) in listOf(
            Triple(200, "<div class='flash notice'>Saved.</div>", emptyList()),
            Triple(302, "", emptyList()),
            Triple(200, "<div class='flash error'>Refused.</div>", listOf("Refused.")),
            Triple(302, "<div class='flash notice'>Saved.</div><div class='flash error'>Refused.</div>", listOf("Refused.")),
            Triple(200, "<p>No confirmation.</p>", listOf(unconfirmed)),
            Triple(422, "", listOf(unconfirmed)),
            Triple(422, challengeFixture("ao3_demo_signup_refused"), listOf("Description contains Uncharted Lantern, which is not accepted for this challenge.")),
            Triple(422, challengeFixture(signUpFixtures[1]).replace("</main>", challengeFixture("ao3_demo_signup_refused") + "</main>"),
                listOf("Description contains Uncharted Lantern, which is not accepted for this challenge.", "Please revise your prompt and submit again."))
        )) {
            val (auth, client, repo) = promptMemeSetup()
            val url = AO3ChallengeSignUpUrls.form("winter_exchange")
            client.replies[url] = challengeResponse(url, challengeFixture(signUpFixtures[0]))
            val model = AO3ChallengeSignUpState("winter_exchange", null, repo, promptMemeWrites(client, auth))
            model.load()
            model.update(model.state.value.form!!.requests[0].copy(description = "Entire typed prompt & 星", title = "Typed title"))
            val typed = model.state.value.form!!
            client.postReply = AO3Result.Success(AO3HttpResponse(typed.actionUrl, status, emptyMap(), body))
            model.save()
            assertEquals(listOf(url, url), client.gets)
            assertEquals(1, client.posts)
            assertEquals(errors, model.state.value.form!!.generalErrors)
            assertEquals(typed.requests, model.state.value.form!!.requests)
            assertEquals(typed.servedControls, model.state.value.form!!.servedControls)
            assertEquals(if (errors.isEmpty()) "Sign-up submitted successfully!" else null, model.state.value.notice)
        }
    }

    @Test fun pendingTokenAndPostKeepFormUntilConfirmationAndIgnoreRepeatedSubmitAndEdits() = runTest {
        val (auth, client, repo) = promptMemeSetup()
        val url = AO3ChallengeSignUpUrls.form("winter_exchange")
        client.replies[url] = challengeResponse(url, challengeFixture(signUpFixtures[0]))
        val model = AO3ChallengeSignUpState("winter_exchange", null, repo, promptMemeWrites(client, auth))
        model.load()
        val original = model.state.value.form
        client.hold = true
        client.holdPost = true
        client.postReply = challengeResponse(url, challengeFixture(signUpFixtures[1]) + "<div class='flash notice'>Saved.</div>")
        val save = async { model.save() }
        runCurrent()
        assertTrue(model.state.value.saving)
        assertEquals(original, model.state.value.form)
        assertEquals(0, client.posts)
        model.save(); model.add(SignUpPromptKind.Request)
        client.release.complete(Unit)
        client.postEntered.await()
        assertEquals(original, model.state.value.form)
        model.update(original!!.requests[0].copy(description = "Ignored"))
        model.save()
        assertEquals(1, client.posts)
        client.postRelease.complete(Unit); save.await()
        assertEquals(4, model.state.value.form?.signUpID)
        assertFalse(model.state.value.saving)
        assertEquals(listOf(url, url), client.gets)
    }

    @Test fun tokenFailuresWriteFailuresAndSessionChangesNeverRetryOrInstallStaleResponses() = runTest {
        for (problem in listOf("token403", "missingMeta", "post429", "changeAtGet", "changeAtPost")) {
            val (auth, client, repo) = promptMemeSetup()
            val url = AO3ChallengeSignUpUrls.form("winter_exchange")
            client.replies[url] = challengeResponse(url, challengeFixture(signUpFixtures[0]))
            val model = AO3ChallengeSignUpState("winter_exchange", null, repo, promptMemeWrites(client, auth))
            model.load()
            val original = model.state.value.form
            when (problem) {
                "token403" -> client.replies[url] = AO3Result.Failure(AO3Error.Forbidden)
                "missingMeta" -> client.replies[url] = challengeResponse(url, "<input name='authenticity_token' value='input-only'>")
                "changeAtGet" -> client.afterGet = { auth.logout() }
                "changeAtPost" -> client.afterPost = { auth.logout() }
            }
            client.postReply = if (problem == "post429") AO3Result.Failure(AO3Error.RateLimited(1000))
                else challengeResponse(url, "<div class='flash notice'>Saved.</div>")
            model.save()
            assertEquals(2, client.gets.size)
            assertEquals(if (problem in listOf("post429", "changeAtPost")) 1 else 0, client.posts)
            assertNull(model.state.value.notice)
            assertEquals(original!!.requests, model.state.value.form?.requests)
            if (problem.startsWith("change")) assertEquals(original, model.state.value.form)
            if (problem == "missingMeta") assertEquals(listOf("Couldn't prepare the request. Try again, or open the work on AO3."), model.state.value.form?.generalErrors)
            if (problem == "token403") {
                assertEquals(listOf("AO3 refused the request (HTTP 403). Wait a while before trying again."), model.state.value.form?.generalErrors)
                model.save(); model.load(refresh = true)
                assertEquals(2, client.gets.size)
                assertEquals(0, client.posts)
            }
        }
    }
    @Test fun sharedWireHasExactEncodingCookieContactUaAndOnePostEvenOn429Or503() = runTest {
        for (status in listOf(200, 429, 503)) {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
            auth.restoreSession()
            val requests = CopyOnWriteArrayList<Request>()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request(); requests += request
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                    .code(if (request.method == "GET") 200 else status).message("Local sign-up answer")
                    .body((if (request.method == "GET") "<meta name='csrf-token' content='fresh &amp; token'>"
                        else "<div class='flash notice'>Confirmed.</div>").toResponseBody()).build()
            }.addInterceptor { throw AssertionError("Sign-up test attempted a socket") }.build()
            val wire = OkHttpAO3Client(http, AO3NetworkConfig(minDelayBetweenRequestsMillis = 0))
            val form = signUpForm(signUpFixtures[1])
            val answer = AO3WriteRepository(DefaultAO3AuthenticatedClient(wire, wire, auth))
                .saveChallengeSignUp(form, auth.generation.value)
            assertEquals(status == 200, answer is AO3Result.Success)
            assertEquals(listOf("GET", "POST"), requests.map { it.method })
            assertEquals(AO3ChallengeSignUpUrls.form(form.slug, 4), requests.first().url.toString())
            val post = requests.last()
            assertEquals(form.actionUrl, post.url.toString())
            assertEquals(AO3UserAgent.VALUE, post.header("User-Agent"))
            assertTrue(post.header("Cookie").orEmpty().isNotEmpty())
            assertEquals("fresh & token", post.header("X-CSRF-Token"))
            assertEquals(AO3ChallengeSignUpUrls.form(form.slug, 4), post.header("Referer"))
            assertNull(post.header("X-Requested-With")); assertNull(post.header("Accept"))
            assertEquals("application/x-www-form-urlencoded; charset=UTF-8", post.body!!.contentType().toString())
            val buffer = Buffer(); post.body!!.writeTo(buffer)
            val body = buffer.readUtf8()
            assertTrue(body.startsWith("authenticity_token=fresh%20%26%20token&_method=put&challenge_signup%5Bpseud_id%5D=101&"))
            assertTrue(body.contains("future_text=Harbor%20%26%20%E6%98%9F"))
            val decoded = body.split('&').map { pair -> pair.split('=', limit = 2).let {
                java.net.URLDecoder.decode(it[0], "UTF-8") to java.net.URLDecoder.decode(it.getOrElse(1) { "" }, "UTF-8")
            } }
            assertEquals(form.copy(token = "fresh & token").parameters(), decoded)
        }
    }

}
