package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.network.ao3.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AO3UnmarkForLaterTest {
    private class Client(var answer: AO3Result<AO3HttpResponse>) : AO3AuthenticatedClient {
        var generation = 1
        var changeDuringGet = false
        val gets = mutableListOf<String>()
        val posts = mutableListOf<RecordedPost>()
        override fun username() = "alice"
        override fun sessionGeneration() = generation
        override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
            gets += url
            if (changeDuringGet) generation++
            return success("<meta name='csrf-token' content='probe-csrf'>")
        }
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            posts += RecordedPost(url, formFields, headers)
            return answer
        }
    }

    @Test fun unmarkForLaterPatchesMarkAsReadOnce() = runTest {
        val client = Client(success("<div class='flash notice'>Unmarked.</div>"))
        val result = AO3WriteRepository(client).unmarkForLater(42, 1) as AO3Result.Success
        assertEquals("Unmarked.", result.value.message)
        assertEquals(listOf("https://archiveofourown.org/works/42?view_adult=true"), client.gets)
        assertEquals("https://archiveofourown.org/works/42/mark_as_read", client.posts.single().url)
        assertEquals(listOf("_method" to "patch", "authenticity_token" to "probe-csrf"), client.posts.single().fields)
        assertEquals(client.gets.single(), client.posts.single().headers["Referer"])
    }

    @Test fun anUnmarkWithoutAO3sNoticeIsNotASuccessAndErrorsAndDropsAreNeverRetried() = runTest {
        for (answer in listOf(success("<p>Maintenance</p>"),
            success("<div class='flash error'>No permission.</div>"),
            AO3Result.Failure(AO3Error.Network("lost answer")),
            AO3Result.Failure(AO3Error.RateLimited(1000)))) {
            val client = Client(answer)
            assertTrue(AO3WriteRepository(client).unmarkForLater(42, 1) is AO3Result.Failure)
            assertEquals(1, client.gets.size)
            assertEquals(1, client.posts.size)
        }
    }

    @Test fun oldTapSendsNothingAndSessionChangeDuringCSRFReadPostsNothing() = runTest {
        for (changeDuringGet in listOf(false, true)) {
            val client = Client(success("<div class='flash notice'>Unmarked.</div>"))
            client.changeDuringGet = changeDuringGet
            if (!changeDuringGet) client.generation++
            try {
                AO3WriteRepository(client).unmarkForLater(42, 1)
                fail("Expected the session fence")
            } catch (_: CancellationException) { }
            assertEquals(if (changeDuringGet) 1 else 0, client.gets.size)
            assertTrue(client.posts.isEmpty())
        }
    }
}
