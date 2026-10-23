package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

/**
 * iOS `deleteReading` (audit A14: the History list's Delete hid the row and told AO3 nothing).
 * Terminal in-memory clients only; no AO3 request can leave this test.
 */
class AO3HistoryDeleteTest {
    private val history = "<meta name='csrf-token' content='fresh-history-token'>" +
        "<form class='ajax-remove' action='/users/AO3_Reader/readings/77'><input name='authenticity_token' value='row-token'></form>"
    private val done = "<div class='flash notice'>Work successfully deleted from your history.</div>"

    @Test fun theRequestIsIosFieldForField() = runTest {
        for ((page, referer, endpoint) in listOf(
            Triple(1, "https://archiveofourown.org/users/AO3_Reader/readings",
                "https://archiveofourown.org/users/AO3_Reader/readings/77"),
            Triple(3, "https://archiveofourown.org/users/AO3_Reader/readings?page=3",
                "https://archiveofourown.org/users/AO3_Reader/readings/77?page=3")
        )) {
            val client = FakeAuthenticatedClient(listOf(success(history)), listOf(success(done)))
            val result = AO3WriteRepository(client).deleteReading(77, page)
            assertEquals("Removed from history.", (result as AO3Result.Success).value.message)
            assertEquals(listOf(referer), client.gets) // the token comes from the page the row is on
            assertEquals(endpoint, client.posts.single().url)
            // The page's general token, never the row's; Rails' method override; the reading's own id.
            assertEquals(listOf("_method" to "delete", "authenticity_token" to "fresh-history-token", "reading" to "77"),
                client.posts.single().fields)
            assertEquals(referer, client.posts.single().headers["Referer"])
            assertEquals("fresh-history-token", client.posts.single().headers["X-CSRF-Token"])
        }
    }

    @Test fun onlyAo3sOwnEvidenceIsDoneAndNothingIsSentTwice() = runTest {
        val answers = listOf(
            success(done) to true,
            success("", status = 302) to true,
            success("<p>The Archive is down for maintenance.</p>") to false, // a page that confirms nothing
            success("<div class='flash error'>Sorry, you don't have permission.</div>") to false,
            success("<div id='error' class='error'><ul><li>Not allowed.</li></ul></div>") to false,
            AO3Result.Failure(AO3Error.RateLimited(1000)) to false,
            AO3Result.Failure(AO3Error.Network("Lost connection")) to false
        )
        for ((answer, confirmed) in answers) {
            val client = FakeAuthenticatedClient(listOf(success(history)), listOf(answer))
            assertEquals(confirmed, AO3WriteRepository(client).deleteReading(77, 1) is AO3Result.Success)
            assertEquals(1, client.posts.size)
        }
    }

    @Test fun noTokenOrNoIdSendsNothing() = runTest {
        val noToken = FakeAuthenticatedClient(listOf(success("<p>History</p>")), emptyList())
        assertTrue(AO3WriteRepository(noToken).deleteReading(77, 1) is AO3Result.Failure)
        assertTrue(noToken.posts.isEmpty())
        val noId = FakeAuthenticatedClient(emptyList(), emptyList())
        assertTrue(AO3WriteRepository(noId).deleteReading(0, 1) is AO3Result.Failure)
        assertTrue(noId.gets.isEmpty() && noId.posts.isEmpty())
    }

    private val confirmPage = "<meta name='csrf-token' content='fresh-confirm-token'>" +
        "<form action='/users/AO3_Reader/readings/clear' method='post'><input name='authenticity_token' value='form-token'></form>"

    /** iOS `clearReadingHistory`: the confirm page's token, one POST with nothing else in it. */
    @Test fun clearingAsksAo3sConfirmPageThenPostsOnce() = runTest {
        val client = FakeAuthenticatedClient(
            listOf(success(confirmPage)),
            listOf(success("<div class='flash notice'>Your history is now cleared.</div>"))
        )
        val result = AO3WriteRepository(client).clearReadingHistory()
        assertEquals("History cleared.", (result as AO3Result.Success).value.message)
        val confirm = "https://archiveofourown.org/users/AO3_Reader/readings/confirm_clear"
        assertEquals(listOf(confirm), client.gets)
        assertEquals("https://archiveofourown.org/users/AO3_Reader/readings/clear", client.posts.single().url)
        assertEquals(listOf("authenticity_token" to "fresh-confirm-token"), client.posts.single().fields)
        assertEquals(confirm, client.posts.single().headers["Referer"])
    }

    @Test fun clearingIsDoneOnlyOnAo3sOwnEvidenceAndIsNeverSentTwice() = runTest {
        val answers = listOf(
            success("", status = 302) to true,
            success("<p>The Archive is down for maintenance.</p>") to false, // a page that confirms nothing
            success("<div class='flash error'>Sorry, you don't have permission.</div>") to false,
            AO3Result.Failure(AO3Error.RateLimited(1000)) to false,
            AO3Result.Failure(AO3Error.Network("Lost connection")) to false
        )
        for ((answer, confirmed) in answers) {
            val client = FakeAuthenticatedClient(listOf(success(confirmPage)), listOf(answer))
            assertEquals(confirmed, AO3WriteRepository(client).clearReadingHistory() is AO3Result.Success)
            assertEquals(1, client.posts.size)
        }
        // No token on the confirm page: nothing is sent.
        val noToken = FakeAuthenticatedClient(listOf(success("<p>Are you sure?</p>")), emptyList())
        assertTrue(AO3WriteRepository(noToken).clearReadingHistory() is AO3Result.Failure)
        assertTrue(noToken.posts.isEmpty())
    }

    @Test fun clearHistoryStopsAndSendsNothingIfSessionChangesDuringGet() = runTest {
        val client = FakeAuthenticatedClient(
            listOf(success(confirmPage)),
            listOf(success("<div class='flash notice'>Your history is now cleared.</div>"))
        )
        client.afterGet = {
            // The session changes (e.g. user signs out or switches accounts) while GET is underway
            client.currentGeneration = 2
        }
        var cancelled = false
        try {
            AO3WriteRepository(client).clearReadingHistory()
        } catch (_: CancellationException) {
            cancelled = true
        }
        assertTrue("Session change during GET cancelled the write", cancelled)
        val confirm = "https://archiveofourown.org/users/AO3_Reader/readings/confirm_clear"
        assertEquals(listOf(confirm), client.gets)
        assertTrue("Nothing was posted", client.posts.isEmpty())
    }

    @Test fun deleteReadingStopsAndSendsNothingIfSessionChangesDuringGet() = runTest {
        val client = FakeAuthenticatedClient(
            listOf(success(history)),
            listOf(success(done))
        )
        client.afterGet = {
            client.currentGeneration = 2
        }
        var cancelled = false
        try {
            AO3WriteRepository(client).deleteReading(77, 1)
        } catch (_: CancellationException) {
            cancelled = true
        }
        assertTrue("Session change during GET cancelled the write", cancelled)
        val referer = "https://archiveofourown.org/users/AO3_Reader/readings"
        assertEquals(listOf(referer), client.gets)
        assertTrue("Nothing was posted", client.posts.isEmpty())
    }

    @Test fun a307Or308AnswerToAWriteIsNotReSentAndFails() = runTest {
        for (code in listOf(307, 308)) {
            // Both when client returns a 307/308 HTTP response, and when transport reports redirect refusal:
            val clientWithStatus = FakeAuthenticatedClient(
                listOf(success(confirmPage)),
                listOf(success("", status = code))
            )
            val resultStatus = AO3WriteRepository(clientWithStatus).clearReadingHistory()
            assertTrue("HTTP $code must fail", resultStatus is AO3Result.Failure)
            assertEquals("one POST, never re-sent", 1, clientWithStatus.posts.size)

            val transportFailure = AO3Result.Failure(AO3Error.Validation(
                "AO3 asked for this to be sent again, and it wasn't. Check on AO3 before trying again."))
            val clientWithFailure = FakeAuthenticatedClient(
                listOf(success(confirmPage)),
                listOf(transportFailure)
            )
            val resultFailure = AO3WriteRepository(clientWithFailure).clearReadingHistory()
            assertTrue("Transport failure for $code must fail", resultFailure is AO3Result.Failure)
            assertEquals("one POST, never re-sent", 1, clientWithFailure.posts.size)
        }
    }
}
