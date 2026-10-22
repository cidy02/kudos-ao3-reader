package io.github.cidy02.kudos.comments

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.comments.CommentCache
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.success
import io.github.cidy02.kudos.network.ao3.writes.writeResource
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Comments read without a connection are a kept copy, and the screen is told so and from when. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class OfflineCommentsCopyTest {
    private class Page : AO3Client, AO3AuthenticatedClient {
        var offline = false
        var failure: AO3Error = AO3Error.Network("offline")
        private fun answer(): AO3Result<AO3HttpResponse> =
            if (offline) AO3Result.Failure(failure) else success(writeResource("ao3/comments/comments_basic.html"))
        override fun username() = "alice"
        override suspend fun get(url: String, headers: Map<String, String>) = answer()
        override suspend fun getAuthenticated(url: String) = answer()
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>) = AO3Result.Failure(AO3Error.NotFound)
    }

    @Test fun aPageAO3ServedIsNotMarkedAndTheCopyShownWithoutAConnectionIs() = runBlocking<Unit> {
        val page = Page()
        val repository = AO3CommentRepository(page, page, cache = CommentCache(RuntimeEnvironment.getApplication()))
        val work = AO3CommentTarget.Work(123L)

        val live = repository.loadThread(work, 1, null) as AO3Result.Success
        assertNull("today's page carries no stamp", live.value.fetchedAt)
        assertEquals(false, live.isStale)

        val before = System.currentTimeMillis()
        page.offline = true
        val kept = repository.loadThread(work, 1, null) as AO3Result.Success
        assertTrue(kept.isStale)
        assertNotNull(kept.value.fetchedAt)
        assertTrue("stamped when it was read, not when it is shown", kept.value.fetchedAt!! in 1..before)
        assertEquals(live.value.comments.size, kept.value.comments.size)
    }

    /** iOS's two lines: offline, or AO3 not reached (a timeout said "offline" too, A74 / §5c 6c). */
    @Test fun theKeptCopySaysWhetherThePhoneIsOfflineOrAO3WasNotReached() = runBlocking<Unit> {
        val page = Page()
        val repository = AO3CommentRepository(page, page, cache = CommentCache(RuntimeEnvironment.getApplication()))
        val work = AO3CommentTarget.Work(124L)
        repository.loadThread(work, 1, null)
        page.offline = true
        page.failure = AO3Error.Network("timed out")
        val timedOut = (repository.loadThread(work, 1, null) as AO3Result.Success).value
        assertEquals(false, timedOut.keptWhileOffline)
        assertTrue(offlineCommentsLine(1, 2, timedOut.keptWhileOffline).startsWith("AO3 couldn't be reached. "))
        page.failure = AO3Error.Network("offline", offline = true)
        val offline = (repository.loadThread(work, 1, null) as AO3Result.Success).value
        assertEquals(true, offline.keptWhileOffline)
        assertTrue(offlineCommentsLine(1, 2, offline.keptWhileOffline).startsWith("You're offline. "))
    }

    @Test fun theLineSaysHowOldTheCopyIs() {
        val minute = 60_000L; val now = 1_000_000_000_000L
        fun from(age: Long) = offlineCommentsLine(now - age, now).removePrefix("You're offline. These comments are from ")
            .removeSuffix(" and may be out of date.")
        assertEquals("a moment ago", from(20_000))
        assertEquals("1 minute ago", from(minute))
        assertEquals("59 minutes ago", from(59 * minute))
        assertEquals("1 hour ago", from(60 * minute))
        assertEquals("23 hours ago", from(23 * 60 * minute + 59 * minute))
        assertEquals("1 day ago", from(24 * 60 * minute))
        assertEquals("3 days ago", from(3 * 24 * 60 * minute))
        // A copy kept before its time was recorded: iOS's own word for an unknown age.
        assertEquals("You're offline. These comments are from earlier and may be out of date.", offlineCommentsLine(0, now))
    }
}
