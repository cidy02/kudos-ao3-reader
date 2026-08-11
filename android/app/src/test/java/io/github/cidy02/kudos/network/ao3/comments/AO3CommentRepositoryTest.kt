package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteActionKind
import io.github.cidy02.kudos.network.ao3.writes.FakeAuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.RecordedPost
import io.github.cidy02.kudos.network.ao3.writes.success
import io.github.cidy02.kudos.network.ao3.writes.writeResource
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3CommentRepositoryTest {
    @Test
    fun publicLoadReadsCommentsWithoutAuthenticatedPost() = runTest {
        val repository = AO3CommentRepository(
            publicClient = FakePublicClient(success(writeResource("ao3/comments/comments_basic.html"))),
            // Signed-out path: authenticated GET fails, repository falls back to public HTML.
            authenticatedClient = FakeAuthenticatedClient(
                getResults = listOf(AO3Result.Failure(AO3Error.AuthenticationRequired)),
                postResults = emptyList()
            )
        )

        val thread = (repository.loadThread(AO3CommentTarget.Work(123)) as AO3Result.Success).value

        // Tree model: 3 top-level (registered w/ nested reply, guest, anonymous creator).
        assertEquals(3, thread.comments.size)
        assertEquals(1, thread.comments[0].replies.size)
    }

    @Test
    fun authenticatedLoadUsesSessionHtmlWhenAvailable() = runTest {
        val repository = AO3CommentRepository(
            publicClient = FakePublicClient(AO3Result.Failure(AO3Error.Network("should not use public"))),
            authenticatedClient = FakeAuthenticatedClient(
                getResults = listOf(success(writeResource("ao3/comments/comments_basic.html"))),
                postResults = emptyList()
            )
        )

        val thread = (repository.loadThread(AO3CommentTarget.Work(123)) as AO3Result.Success).value
        assertEquals(3, thread.comments.size)
        assertEquals(1, thread.comments[0].replies.size)
        assertEquals("comment-token", thread.form?.authenticityToken)
    }

    @Test
    fun loadThreadRequestsPageQueryOnlyWhenPastFirst() = runTest {
        val public = RecordingPublicClient(
            success(writeResource("ao3/comments/comments_paginated.html"))
        )
        val repository = AO3CommentRepository(
            publicClient = public,
            // One auth-required failure per loadThread call (page 1 + page 2).
            authenticatedClient = FakeAuthenticatedClient(
                getResults = listOf(
                    AO3Result.Failure(AO3Error.AuthenticationRequired),
                    AO3Result.Failure(AO3Error.AuthenticationRequired)
                ),
                postResults = emptyList()
            )
        )

        val page1 = (repository.loadThread(AO3CommentTarget.Work(123), page = 1) as AO3Result.Success).value
        assertEquals(5, page1.totalPages)
        assertFalse(public.urls.single().contains("page="))

        public.urls.clear()
        repository.loadThread(AO3CommentTarget.Work(123), page = 2)
        assertTrue(public.urls.single().contains("page=2"))
    }

    @Test
    fun emptyCommentCannotBeSubmitted() = runTest {
        val repository = AO3CommentRepository(
            publicClient = FakePublicClient(success("")),
            authenticatedClient = FakeAuthenticatedClient(emptyList(), emptyList())
        )

        val result = repository.submitComment(AO3CommentTarget.Work(123), "   ")

        assertEquals(AO3Error.Validation("Write a comment first."), (result as AO3Result.Failure).error)
    }

    @Test
    fun submitCommentFetchesFormThenPostsOneBody() = runTest {
        val auth = TrackingAuthenticatedClient(
            getResults = listOf(success(writeResource("ao3/comments/comments_basic.html"))),
            postResults = listOf(success("ok"))
        )
        val repository = AO3CommentRepository(
            publicClient = FakePublicClient(success("")),
            authenticatedClient = auth
        )

        val outcome = (repository.submitComment(AO3CommentTarget.Work(123), "Thanks!") as AO3Result.Success).value

        assertEquals(AO3WriteActionKind.Comment, outcome.kind)
        assertEquals("https://archiveofourown.org/works/123?view_adult=true", auth.gets.single())
        assertEquals("https://archiveofourown.org/works/123/comments", auth.posts.single().url)
        assertEquals(
            listOf(
                "authenticity_token" to "comment-token",
                "comment[comment_content]" to "Thanks!",
                "comment[pseud_id]" to "5"
            ),
            auth.posts.single().fields
        )
        assertEquals("Comment posted.", outcome.message)
    }

    @Test
    fun submitReplyUsesParentThreadForCsrfAndReplyEndpoint() = runTest {
        val parentId = 1_252_794_206L
        val auth = TrackingAuthenticatedClient(
            getResults = listOf(
                success(
                    body = writeResource("ao3/comments/comment_thread_reply_form.html"),
                    url = AO3CommentUrls.commentThreadUrl(parentId, isReply = true)
                )
            ),
            postResults = listOf(success("ok"))
        )
        val repository = AO3CommentRepository(
            publicClient = FakePublicClient(success("")),
            authenticatedClient = auth
        )

        val outcome = (
            repository.submitComment(
                target = AO3CommentTarget.Work(123),
                content = "A thoughtful reply",
                parentCommentId = parentId
            ) as AO3Result.Success
            ).value

        assertEquals(AO3WriteActionKind.Comment, outcome.kind)
        assertEquals("Reply posted.", outcome.message)
        assertEquals(AO3CommentUrls.commentThreadUrl(parentId, isReply = true), auth.gets.single())
        assertEquals(AO3CommentUrls.commentReplyEndpoint(parentId), auth.posts.single().url)
        assertEquals(
            listOf(
                "authenticity_token" to "reply-csrf-token",
                "comment[comment_content]" to "A thoughtful reply",
                "comment[pseud_id]" to "7"
            ),
            auth.posts.single().fields
        )
        assertEquals(AO3CommentUrls.commentThreadUrl(parentId, isReply = true), auth.posts.single().headers["Referer"])
    }

    @Test
    fun validationErrorFromAo3Surfaces() = runTest {
        val auth = FakeAuthenticatedClient(
            getResults = listOf(success(writeResource("ao3/comments/comments_basic.html"))),
            postResults = listOf(success(writeResource("ao3/comments/comment_validation_error.html"), status = 422))
        )
        val repository = AO3CommentRepository(
            publicClient = FakePublicClient(success("")),
            authenticatedClient = auth
        )

        val result = repository.submitComment(AO3CommentTarget.Work(123), "Thanks!")

        assertTrue((result as AO3Result.Failure).error is AO3Error.Validation)
        assertEquals(
            AO3Error.Validation("Comment content can't be blank"),
            result.error
        )
    }

    @Test
    fun pageUrlOmitsPageOneIncludesHigherPages() {
        val work = AO3CommentTarget.Work(123)
        assertFalse(work.pageUrl(1).contains("page="))
        assertTrue(work.pageUrl(2).contains("page=2"))

        val chapter = AO3CommentTarget.Chapter(123, 456)
        assertFalse(chapter.pageUrl().contains("page="))
        assertTrue(chapter.pageUrl(4).contains("page=4"))
    }
}

private class FakePublicClient(
    private val result: AO3Result<AO3HttpResponse>
) : AO3Client {
    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> = result
}

/** Public client that records requested URLs (for pagination query-param checks). */
private class RecordingPublicClient(
    private val result: AO3Result<AO3HttpResponse>
) : AO3Client {
    val urls = mutableListOf<String>()

    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        urls += url
        return result
    }
}

/**
 * Authenticated client that records GET URLs so reply CSRF-source selection can
 * be asserted without changing the shared FakeAuthenticatedClient.
 */
private class TrackingAuthenticatedClient(
    getResults: List<AO3Result<AO3HttpResponse>>,
    postResults: List<AO3Result<AO3HttpResponse>>,
    private val username: String? = "AO3_Reader"
) : AO3AuthenticatedClient {
    private val getQueue = ArrayDeque(getResults)
    private val postQueue = ArrayDeque(postResults)
    val gets = mutableListOf<String>()
    val posts = mutableListOf<RecordedPost>()

    override fun username(): String? = username

    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
        gets += url
        return getQueue.removeFirst()
    }

    override suspend fun postAuthenticated(
        url: String,
        formFields: List<Pair<String, String>>,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        posts += RecordedPost(url, formFields, headers)
        return postQueue.removeFirst()
    }
}
