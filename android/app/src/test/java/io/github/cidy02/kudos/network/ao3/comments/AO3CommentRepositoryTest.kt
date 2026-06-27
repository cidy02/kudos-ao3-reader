package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteActionKind
import io.github.cidy02.kudos.network.ao3.writes.FakeAuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.success
import io.github.cidy02.kudos.network.ao3.writes.writeResource
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3CommentRepositoryTest {
    @Test
    fun publicLoadReadsCommentsWithoutAuthenticatedPost() = runTest {
        val repository = AO3CommentRepository(
            publicClient = FakePublicClient(success(writeResource("ao3/comments/comments_basic.html"))),
            authenticatedClient = FakeAuthenticatedClient(emptyList(), emptyList())
        )

        val thread = (repository.loadThread(AO3CommentTarget.Work(123)) as AO3Result.Success).value

        assertEquals(2, thread.comments.size)
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
        val auth = FakeAuthenticatedClient(
            getResults = listOf(success(writeResource("ao3/comments/comments_basic.html"))),
            postResults = listOf(success("ok"))
        )
        val repository = AO3CommentRepository(
            publicClient = FakePublicClient(success("")),
            authenticatedClient = auth
        )

        val outcome = (repository.submitComment(AO3CommentTarget.Work(123), "Thanks!") as AO3Result.Success).value

        assertEquals(AO3WriteActionKind.Comment, outcome.kind)
        assertEquals("https://archiveofourown.org/works/123/comments", auth.posts.single().url)
        assertEquals(
            listOf(
                "authenticity_token" to "comment-token",
                "comment[comment_content]" to "Thanks!",
                "comment[pseud_id]" to "5"
            ),
            auth.posts.single().fields
        )
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
}

private class FakePublicClient(
    private val result: AO3Result<AO3HttpResponse>
) : AO3Client {
    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> = result
}
