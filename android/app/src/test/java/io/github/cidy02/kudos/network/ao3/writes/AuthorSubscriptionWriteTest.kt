package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorSubscriptionForm
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Brief 3ci: Subscribe and Unsubscribe on an author's page are one write each, of AO3's own form. */
class AuthorSubscriptionWriteTest {
    private class Session : AO3AuthenticatedClient {
        var name: String? = "reader"
        var generation = 1
        val gets = mutableListOf<String>()
        val posts = mutableListOf<Triple<String, List<Pair<String, String>>, Map<String, String>>>()
        var afterGet: () -> Unit = {}
        var reply = "<div class='flash notice'>You are now following this user.</div>"
        override fun username() = name
        override fun sessionGeneration(): Int = generation
        override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
            gets += url
            afterGet()
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), "<meta name='csrf-token' content='fresh'>"))
        }
        override suspend fun postAuthenticated(
            url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>
        ): AO3Result<AO3HttpResponse> {
            posts += Triple(url, formFields, headers)
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), reply))
        }
    }

    private val page = "https://archiveofourown.org/users/Avery_Archive"
    private val join = AO3AuthorSubscriptionForm(
        label = "Subscribe", actionUrl = "https://archiveofourown.org/users/reader/subscriptions",
        fields = listOf("authenticity_token" to "served-with-the-page", "subscription[subscribable_type]" to "User",
            "subscription[subscribable_id]" to "4242"),
        csrfToken = "served-with-the-page", referer = page)
    private val leave = join.copy(label = "Unsubscribe", actionUrl = join.actionUrl + "/77",
        fields = listOf("_method" to "delete") + join.fields)

    @Test fun subscribingSendsTheServedFieldsOnceWithAFreshToken() = runTest {
        val session = Session()
        val result = AO3WriteRepository(session).submitAuthorSubscription(join, 1)
        assertEquals("Subscribed.", (result as AO3Result.Success).value.message)
        assertEquals(AO3WriteActionKind.Subscribe, result.value.kind)
        assertEquals("the token is read from the page the form was on", listOf(page), session.gets)
        val (url, fields, headers) = session.posts.single()
        assertEquals(join.actionUrl, url)
        assertEquals(listOf("subscription[subscribable_type]" to "User", "subscription[subscribable_id]" to "4242",
            "authenticity_token" to "fresh"), fields)
        assertEquals(page, headers["Referer"])
    }

    @Test fun unsubscribingSendsTheFormThatEndsIt() = runTest {
        val session = Session().apply { reply = "<div class='flash notice'>You have successfully unsubscribed.</div>" }
        val result = AO3WriteRepository(session).submitAuthorSubscription(leave, 1)
        assertEquals("Unsubscribed.", (result as AO3Result.Success).value.message)
        assertEquals(AO3WriteActionKind.Unsubscribe, result.value.kind)
        val (url, fields, _) = session.posts.single()
        assertEquals(leave.actionUrl, url)
        assertTrue("_method" to "delete" in fields)
        assertEquals("fresh", fields.single { it.first == "authenticity_token" }.second)
    }

    @Test fun aFormFromAnotherSessionOrASignedOutReaderOrAnotherSiteSendsNothing() = runTest {
        val session = Session()
        val writes = AO3WriteRepository(session)
        try { writes.submitAuthorSubscription(join, 2); fail("another session's form must not be sent") }
        catch (_: CancellationException) { }

        session.name = null
        assertEquals(AO3Error.AuthenticationRequired, (writes.submitAuthorSubscription(join, 1) as AO3Result.Failure).error)

        session.name = "reader"
        val elsewhere = join.copy(actionUrl = "https://example.org/users/reader/subscriptions")
        assertTrue((writes.submitAuthorSubscription(elsewhere, 1) as AO3Result.Failure).error is AO3Error.Validation)

        assertEquals("none of the three asked AO3 for anything", emptyList<String>(), session.gets)
        assertTrue(session.posts.isEmpty())
    }

    @Test fun aSessionThatChangesWhileTheTokenIsReadSendsNothing() = runTest {
        val session = Session()
        session.afterGet = { session.generation = 2 }
        try { AO3WriteRepository(session).submitAuthorSubscription(join, 1); fail("the write must stop") }
        catch (_: CancellationException) { }
        assertEquals(1, session.gets.size)
        assertTrue(session.posts.isEmpty())
    }

    @Test fun anAnswerThatDoesNotConfirmIsNotCalledASuccessAndIsNotSentAgain() = runTest {
        val session = Session().apply { reply = "<html><body>Something else.</body></html>" }
        val result = AO3WriteRepository(session).submitAuthorSubscription(join, 1)
        assertTrue(result is AO3Result.Failure)
        assertEquals("one POST, never a second", 1, session.posts.size)
    }
}
