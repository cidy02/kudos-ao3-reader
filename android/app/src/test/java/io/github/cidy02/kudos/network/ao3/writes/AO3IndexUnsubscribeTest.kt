package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

/** Terminal in-memory clients only; no AO3 requests can leave this test. */
class AO3IndexUnsubscribeTest {
    private val index = """
        <meta name='csrf-token' content='fresh-index-token'>
        <dl class='subscription'>
        <dt><a href='/works/123'>Work</a></dt>
        <dd><form action='/users/me/subscriptions/987'><input name='_method' value='delete'>
            <input name='authenticity_token' value='row-token'></form></dd>
        <dt><a href='/series/456'>Series</a></dt>
        <dd><form action='/users/me/subscriptions/654'></form></dd>
        <dt><a href='/users/someuser'>someuser</a></dt>
        <dd><form action='/users/me/subscriptions/321'></form></dd>
        </dl>
    """.trimIndent()

    @Test fun workSeriesAndUserUseTheirServedAdjacentFormActionAndFreshIndexToken() = runTest {
        val parser = AO3AccountParser()
        val paths = listOf(
            parser.parseSubscriptionsPage(index, 2).unsubscribePaths.getValue(123),
            parser.parseNamedSubscriptions(index, AO3NamedSubscriptionsScope.Series).rows.single().unsubscribePath!!,
            parser.parseNamedSubscriptions(index, AO3NamedSubscriptionsScope.Users).rows.single().unsubscribePath!!
        )
        assertEquals(listOf("/users/me/subscriptions/987", "/users/me/subscriptions/654", "/users/me/subscriptions/321"), paths)
        for (path in paths) {
            // iOS uses a fresh GENERAL token, not the displayed row's token/method.
            val client = FakeAuthenticatedClient(
                listOf(success("<input name='authenticity_token' value='another-row-token'><meta name='csrf-token' content='fresh-index-token'>")),
                listOf(success("<div class='flash notice'>Unsubscribed.</div>"))
            )
            val result = AO3WriteRepository(client).unsubscribe(path, 2)
            assertTrue(result is AO3Result.Success)
            assertEquals(1, client.posts.size)
            assertEquals("https://archiveofourown.org$path", client.posts.single().url)
            assertEquals(listOf("_method" to "delete", "authenticity_token" to "fresh-index-token"), client.posts.single().fields)
            assertEquals("https://archiveofourown.org/users/AO3_Reader/subscriptions?type=works&page=2", client.gets.single())
            assertEquals(client.gets.single(), client.posts.single().headers["Referer"])
            assertEquals("fresh-index-token", client.posts.single().headers["X-CSRF-Token"])
        }
    }

    @Test fun absentAdjacentFormNeverBorrowsAnotherRowsAction() {
        val parser = AO3AccountParser()
        val html = """<dl class='subscription'><dt><a href='/works/123'>Work</a></dt>
            <dt><a href='/series/456'>Series</a></dt><dd><form action='/users/me/subscriptions/654'></form></dd>
            <dt><a href='/users/someuser'>someuser</a></dt><dd><form action=' '></form></dd></dl>"""
        assertTrue(parser.parseSubscriptionsPage(html, 1).unsubscribePaths.isEmpty())
        assertNull(parser.parseNamedSubscriptions(html, AO3NamedSubscriptionsScope.Users).rows.single().unsubscribePath)
    }

    @Test fun onlyIosPositiveEvidenceConfirmsAndNoFailureRetriesThePost() = runTest {
        val responses = listOf(
            success("<div class='flash notice'>Unsubscribed.</div>") to true,
            success("", status = 302) to true,
            success("<p>successfully deleted in a work summary</p>") to false,
            success("<div class='flash error'>Rejected.</div><div class='flash notice'>Notice.</div>") to false,
            success("<div class='flash error'>Couldn't unsubscribe.</div>", status = 422) to false,
            AO3Result.Failure(AO3Error.RateLimited(1000)) to false,
            AO3Result.Failure(AO3Error.Network("Lost connection")) to false
        )
        for ((response, confirmed) in responses) {
            val client = FakeAuthenticatedClient(
                listOf(success("<meta name='csrf-token' content='fresh'>")), listOf(response)
            )
            val result = AO3WriteRepository(client).unsubscribe("/users/me/subscriptions/987", 1)
            assertEquals(confirmed, result is AO3Result.Success)
            assertEquals(1, client.posts.size)
        }
    }

    @Test fun untrustedActionOrMissingTokenDoesNotPost() = runTest {
        val untrusted = FakeAuthenticatedClient(emptyList(), emptyList())
        assertTrue(AO3WriteRepository(untrusted).unsubscribe("https://archiveofourown.org.evil.com/steal", 1) is AO3Result.Failure)
        assertTrue(untrusted.gets.isEmpty())
        val noToken = FakeAuthenticatedClient(listOf(success("<p>No token</p>")), emptyList())
        assertTrue(AO3WriteRepository(noToken).unsubscribe("/users/me/subscriptions/987", 1) is AO3Result.Failure)
        assertTrue(noToken.posts.isEmpty())
    }
}
