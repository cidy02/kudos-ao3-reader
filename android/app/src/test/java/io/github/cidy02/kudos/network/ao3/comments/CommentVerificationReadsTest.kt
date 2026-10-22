package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writes.*
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class CommentVerificationReadsTest {
    private class Client(private val pages: List<AO3Result<AO3HttpResponse>>) : AO3AuthenticatedClient, AO3Client {
        val urls = mutableListOf<String>()
        var generation = 1
        var changeDuringGet = false
        override fun username() = "reader"
        override fun sessionGeneration() = generation
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
            error("Verification must never fall back to a public/cache read")
        override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
            urls += url
            if (changeDuringGet) generation++
            return pages[urls.lastIndex]
        }
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>): AO3Result<AO3HttpResponse> = error("Verification never posts")
    }

    private val entry = CommentSubmissionStore.Entry(CommentSubmissionStore.Phase.Ambiguous, 1_000)
    private val empty = "<div id='comments_placeholder'><ol class='thread'></ol></div>"

    @Test fun topLevelChecksOnlyFirstAndLastWorkPagesEvenFromAChapter() = runTest {
        val client = Client(listOf(success("$empty<ol class='pagination'><li>1</li><li>3</li></ol>"), success(empty)))
        val repository = AO3CommentRepository(client, client)
        val key = CommentSubmissionKey.of(AO3CommentTarget.Chapter(42, 7), null, "original body", "reader")
        assertEquals(CommentVerification.Absent, (repository.verifySubmission(key, entry, 1) as AO3Result.Success).value)
        assertEquals(listOf(AO3CommentTarget.Work(42).pageUrl(1), AO3CommentTarget.Work(42).pageUrl(3)), client.urls)
    }

    @Test fun replyChecksItsExactParentAndNeverGuessesAWorkPage() = runTest {
        val html = """<ol class="thread"><li class="comment" id="comment_5">
            <h4 class="heading byline"><a rel="author" href="/users/other">Other</a></h4>
            <blockquote class="userstuff">Parent</blockquote><ol class="thread">
            <li class="comment" id="comment_6"><h4 class="heading byline"><a rel="author" href="/users/reader">Pseud</a></h4>
            <blockquote class="userstuff">original body</blockquote></li></ol></li></ol>"""
        val client = Client(listOf(success(html)))
        val key = CommentSubmissionKey.of(AO3CommentTarget.Chapter(42, 7), 5, "original body", "reader")
        assertEquals(CommentVerification.Found, (AO3CommentRepository(client, client).verifySubmission(key, entry, 1) as AO3Result.Success).value)
        assertEquals(listOf("https://archiveofourown.org/comments/5"), client.urls)
    }

    @Test fun failedMalformedAndStaleSessionReadsStayUnknownWithoutPublicFallback() = runTest {
        val key = CommentSubmissionKey.of(AO3CommentTarget.Work(42), null, "original body", "reader")
        for (answer in listOf(AO3Result.Failure(AO3Error.Network("lost connection")), success("<p>Maintenance</p>"))) {
            val client = Client(listOf(answer))
            assertEquals(CommentVerification.Unknown, (AO3CommentRepository(client, client).verifySubmission(key, entry, 1) as AO3Result.Success).value)
            assertEquals(1, client.urls.size)
        }
        val expired = Client(listOf(AO3Result.Failure(AO3Error.AuthenticationRequired)))
        assertEquals(AO3Result.Failure(AO3Error.AuthenticationRequired),
            AO3CommentRepository(expired, expired).verifySubmission(key, entry, 1))
        val client = Client(listOf(success(empty))).also { it.changeDuringGet = true }
        assertEquals(CommentVerification.Unknown, (AO3CommentRepository(client, client).verifySubmission(key, entry, 1) as AO3Result.Success).value)
        val before = Client(emptyList())
        assertEquals(CommentVerification.Unknown, (AO3CommentRepository(before, before).verifySubmission(key, entry, 0) as AO3Result.Success).value)
        assertTrue(before.urls.isEmpty())
    }
}
