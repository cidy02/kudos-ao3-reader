package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import androidx.lifecycle.viewModelScope
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** A page of the Inbox that will not load does not take away the page the reader is on (iOS T91-RF8). */
@OptIn(ExperimentalCoroutinesApi::class)
class InboxFailedPageTest {
    private class Client : AO3Client, AO3AuthenticatedClient {
        var failing: AO3Error? = null
        override fun username() = "tester"
        override fun sessionGeneration() = 1
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
            failing?.let { AO3Result.Failure(it) } ?: AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
                listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
                    .map { File("$it/fixtures/${if (url.contains("show_comments=true")) "ao3_comments_empty" else "ao3_inbox_manage"}.html") }
                    .first(File::isFile).readText()))
        override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>) = AO3Result.Failure(AO3Error.NotFound)
    }

    private var model: AccountInboxViewModel? = null
    @Before fun main() = Dispatchers.setMain(UnconfinedTestDispatcher())
    @After fun reset() {
        // Nothing of this model is left to answer after the test: the Inbox goes on reading each
        // work's authors in the background, and an answer after Main is put back fails whichever
        // test is running by then. Cancelled and waited for: a cancelled read still has to come
        // back to Main to end, so cancelling alone was not enough.
        runBlocking { model?.viewModelScope?.coroutineContext?.get(Job)?.cancelAndJoin() }
        Dispatchers.resetMain()
    }

    @Test fun aFailedPageTurnKeepsThePageAndSaysWhichPageFailedAndASessionThatEndedKeepsNothing() = runTest {
        val client = Client()
        val model = AccountInboxViewModel(AO3InboxRepository(client, pageCache = AO3PageCache()),
            AO3CommentRepository(client, client)).also { this@InboxFailedPageTest.model = it }
        model.load(1)!!.join()
        val first = model.uiState.value
        assertTrue(first.items.isNotEmpty())

        // Page 2 was never read, so there is no kept copy to fall back on: a true failure.
        client.failing = AO3Error.Server(500)
        model.goToPage(2)
        var now = model.uiState.value
        assertEquals("page 1 is still what is shown", first.items, now.items)
        assertEquals(AccountInboxUiState.Phase.Loaded, now.phase)
        assertEquals(1, now.currentPage)
        assertEquals(2, now.failedPage)
        assertNull("no dialog as well as the card", now.actionError)

        // Try Again, with AO3 answering: the card goes.
        client.failing = null
        model.goToPage(2)
        assertNull(model.uiState.value.failedPage)

        // A session that ended is not a page that failed: nothing of it stays on screen.
        client.failing = AO3Error.AuthenticationRequired
        model.load(3, bypassCache = true)!!.join()
        now = model.uiState.value
        assertTrue(now.items.isEmpty())
        assertEquals(AccountInboxUiState.Phase.Failed, now.phase)
        assertNull(now.failedPage)
    }

    /** iOS `aFailedPillRequestKeepsThePillOfTheRowsShown`: the lit pill is the page on screen. */
    @Test fun aFailedPillRequestKeepsThePillOfTheRowsShown() = runTest {
        val client = Client()
        val model = AccountInboxViewModel(AO3InboxRepository(client, pageCache = AO3PageCache()),
            AO3CommentRepository(client, client)).also { this@InboxFailedPageTest.model = it }
        model.load(1)!!.join()
        val shown = model.uiState.value.currentFilterValues
        assertEquals("all", shown["filters[replied_to]"])

        client.failing = AO3Error.Server(500)
        model.applyFilters(mapOf("filters[replied_to]" to "true"))
        val now = model.uiState.value
        assertTrue("the rows stay", now.items.isNotEmpty())
        assertEquals("true", now.filterValues["filters[replied_to]"])
        assertEquals(shown, now.currentFilterValues)
    }
}
