package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3KudosRepositoryTest {
    @Test
    fun kudosFetchesTokenThenPostsExactlyOneAjaxRequest() = runTest {
        val client = FakeAuthenticatedClient(
            getResults = listOf(success(writeResource("ao3/writes/work_with_forms.html"))),
            postResults = listOf(success("ok"))
        )
        val repository = AO3WriteRepository(client)

        val outcome = (repository.giveKudos(123) as AO3Result.Success).value

        assertEquals(AO3WriteActionKind.Kudos, outcome.kind)
        assertEquals("Kudos left.", outcome.message)
        assertEquals(1, client.posts.size)
        assertEquals("https://archiveofourown.org/kudos.js", client.posts.single().url)
        assertEquals(
            listOf(
                "authenticity_token" to "token-from-input",
                "kudo[commentable_id]" to "123",
                "kudo[commentable_type]" to "Work"
            ),
            client.posts.single().fields
        )
        assertEquals("XMLHttpRequest", client.posts.single().headers["X-Requested-With"])
    }

    @Test
    fun kudosAlreadyLeftIsSuccessfulStateNotFakeRepeat() = runTest {
        val client = FakeAuthenticatedClient(
            getResults = listOf(success(writeResource("ao3/writes/work_with_forms.html"))),
            postResults = listOf(success("You have already left kudos here.", status = 422))
        )
        val repository = AO3WriteRepository(client)

        val outcome = (repository.giveKudos(123) as AO3Result.Success).value

        assertEquals("You've already left kudos here.", outcome.message)
        assertEquals(1, client.posts.size)
    }
}

class AO3SubscribeRepositoryTest {
    @Test
    fun subscribedStatePostsDeleteToUnsubscribePath() = runTest {
        val client = FakeAuthenticatedClient(
            getResults = listOf(success(writeResource("ao3/writes/work_subscribed.html"))),
            postResults = listOf(success("ok"))
        )
        val repository = AO3WriteRepository(client)

        val outcome = (repository.toggleSubscribe(123) as AO3Result.Success).value

        assertEquals(AO3WriteActionKind.Unsubscribe, outcome.kind)
        assertEquals("https://archiveofourown.org/users/AO3_Reader/subscriptions/789", client.posts.single().url)
        assertEquals(
            listOf("_method" to "delete", "authenticity_token" to "subscribed-token"),
            client.posts.single().fields
        )
    }

    @Test
    fun unsubscribedStatePostsSubscribeBodyWithCurrentUsername() = runTest {
        val client = FakeAuthenticatedClient(
            getResults = listOf(success(writeResource("ao3/writes/work_with_forms.html"))),
            postResults = listOf(success("ok"))
        )
        val repository = AO3WriteRepository(client)

        val outcome = (repository.toggleSubscribe(123) as AO3Result.Success).value

        assertEquals(AO3WriteActionKind.Subscribe, outcome.kind)
        assertEquals("https://archiveofourown.org/users/AO3_Reader/subscriptions", client.posts.single().url)
        assertTrue(client.posts.single().fields.contains("subscription[subscribable_id]" to "123"))
    }
}

class AO3MarkForLaterRepositoryTest {
    @Test
    fun markForLaterPostsOnlyTheFreshToken() = runTest {
        val client = FakeAuthenticatedClient(
            getResults = listOf(success(writeResource("ao3/writes/work_with_forms.html"))),
            postResults = listOf(success("ok"))
        )
        val repository = AO3WriteRepository(client)

        val outcome = (repository.markForLater(123) as AO3Result.Success).value

        assertEquals(AO3WriteActionKind.MarkForLater, outcome.kind)
        assertEquals("https://archiveofourown.org/works/123/mark_for_later", client.posts.single().url)
        assertEquals(listOf("authenticity_token" to "token-from-input"), client.posts.single().fields)
    }
}

class AO3BookmarkRepositoryTest {
    @Test
    fun createBookmarkPostsNativeCreateFieldsWhereFeasible() = runTest {
        val client = FakeAuthenticatedClient(
            getResults = listOf(success(writeResource("ao3/writes/work_with_forms.html"))),
            postResults = listOf(success("ok"))
        )
        val repository = AO3WriteRepository(client)

        val outcome = (repository.createBookmark(
            123,
            AO3BookmarkInput(notes = "Loved it", tags = "favorite", isPrivate = true)
        ) as AO3Result.Success).value

        assertEquals(AO3WriteActionKind.Bookmark, outcome.kind)
        assertEquals("https://archiveofourown.org/works/123/bookmarks", client.posts.single().url)
        assertTrue(client.posts.single().fields.contains("bookmark[bookmarker_notes]" to "Loved it"))
        assertTrue(client.posts.single().fields.contains("bookmark[tag_string]" to "favorite"))
        assertTrue(client.posts.single().fields.contains("bookmark[private]" to "1"))
        assertTrue(client.posts.single().fields.contains("bookmark[pseud_id]" to "44"))
    }
}

class AO3WriteValidationErrorTest {
    @Test
    fun missingTokenReturnsTypedValidationErrorWithoutPosting() = runTest {
        val client = FakeAuthenticatedClient(
            getResults = listOf(success("<html></html>")),
            postResults = emptyList()
        )
        val repository = AO3WriteRepository(client)

        val result = repository.markForLater(123)

        assertTrue((result as AO3Result.Failure).error is AO3Error.Validation)
        assertEquals(0, client.posts.size)
    }
}

internal data class RecordedPost(
    val url: String,
    val fields: List<Pair<String, String>>,
    val headers: Map<String, String>
)

internal class FakeAuthenticatedClient(
    getResults: List<AO3Result<AO3HttpResponse>>,
    postResults: List<AO3Result<AO3HttpResponse>>,
    private val username: String? = "AO3_Reader"
) : AO3AuthenticatedClient {
    private val getQueue = ArrayDeque<AO3Result<AO3HttpResponse>>().apply { addAll(getResults) }
    private val postQueue = ArrayDeque<AO3Result<AO3HttpResponse>>().apply { addAll(postResults) }
    val posts = mutableListOf<RecordedPost>()

    override fun username(): String? = username

    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
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

internal fun success(
    body: String,
    status: Int = 200,
    url: String = AO3WriteUrls.workUrl(123)
): AO3Result.Success<AO3HttpResponse> {
    return AO3Result.Success(
        AO3HttpResponse(
            url = url,
            statusCode = status,
            headers = emptyMap(),
            body = body
        )
    )
}
