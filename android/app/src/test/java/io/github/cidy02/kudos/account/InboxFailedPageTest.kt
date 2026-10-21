package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxBulkAction
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
        var generation = 1
        var posts = 0
        var empty = false
        var inboxReads = 0
        var postedFields: List<Pair<String, String>> = emptyList()
        override fun username() = "tester"
        override fun sessionGeneration() = generation
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            if (url.contains("/inbox")) inboxReads++
            failing?.let { return AO3Result.Failure(it) }
            val name = if (url.contains("show_comments=true")) "ao3_comments_empty" else "ao3_inbox_manage"
            var html = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
                .map { File("$it/fixtures/$name.html") }.first(File::isFile).readText()
            if (empty && url.contains("/inbox")) {
                val doc = org.jsoup.Jsoup.parse(html)
                doc.select("li.comment").remove()
                html = doc.outerHtml()
            }
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
        }
        override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            posts++
            postedFields = formFields
            return AO3Result.Failure(AO3Error.NotFound)
        }
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

    @Test fun firstAndLaterFailedPullsKeepBothNonemptyAndEmptyShownPages() = runTest {
        for (empty in listOf(false, true)) {
            val client = Client().also { it.empty = empty }
            // No stale fallback: exercise a real failure while a page is on screen.
            val cache = AO3PageCache(ttlMillis = 0, staleMillis = 0)
            val model = AccountInboxViewModel(AO3InboxRepository(client, pageCache = cache),
                AO3CommentRepository(client, client)).also { this@InboxFailedPageTest.model = it }
            model.load(1)!!.join()
            val shown = model.uiState.value
            assertEquals(AccountInboxUiState.Phase.Loaded, shown.phase)
            assertEquals(empty, shown.items.isEmpty())
            client.failing = AO3Error.Network("offline", offline = true)
            repeat(2) {
                val before = client.inboxReads
                model.refresh()
                val now = model.uiState.value
                assertEquals(before + 1, client.inboxReads)
                assertEquals(shown.items, now.items)
                assertEquals(shown.pageUrl, now.pageUrl)
                assertEquals(shown.bulkForm, now.bulkForm)
                assertEquals(AccountInboxUiState.Phase.Loaded, now.phase)
                assertEquals(1, now.failedPage)
                assertNull(now.actionError)
            }
            model.viewModelScope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    @Test fun aFailedFirstPullWithAStaleFallbackAlsoReportsRefreshFailure() = runTest {
        val client = Client()
        val model = AccountInboxViewModel(AO3InboxRepository(client, pageCache = AO3PageCache()),
            AO3CommentRepository(client, client)).also { this@InboxFailedPageTest.model = it }
        model.load(1)!!.join()
        val shown = model.uiState.value
        client.failing = AO3Error.Network("offline", offline = true)
        val before = client.inboxReads
        model.refresh()
        assertEquals(before + 1, client.inboxReads)
        assertEquals(shown.items, model.uiState.value.items)
        assertEquals(AccountInboxUiState.Phase.Loaded, model.uiState.value.phase)
        assertEquals(1, model.uiState.value.failedPage)
    }

    /** Codex's A59 review: a Delete confirmed after the session changed sends nothing. */
    @Test fun aConfirmationFromAnEndedSessionSendsNothing() = runTest {
        val client = Client()
        val model = AccountInboxViewModel(AO3InboxRepository(client, pageCache = AO3PageCache()),
            AO3CommentRepository(client, client)).also { this@InboxFailedPageTest.model = it }
        model.load(1)!!.join()
        val item = model.uiState.value.items.first { it.bulkSelectionField != null }
        val openedIn = model.viewerScope()
        client.generation = 2 // signed out and in again while the dialog was up
        model.startItemAction(AO3InboxBulkAction.Delete, item, openedIn)
        assertEquals(0, client.posts)
        assertEquals(false, model.uiState.value.isPerformingBulkAction)
    }

    /** A reload that clears the selection must not change which items a confirmed delete sends. */
    @Test fun aConfirmedMultiDeleteSendsTheItemsTheDialogCaptured() = runTest {
        val client = Client()
        val model = AccountInboxViewModel(AO3InboxRepository(client, pageCache = AO3PageCache()),
            AO3CommentRepository(client, client)).also { this@InboxFailedPageTest.model = it }
        model.load(1)!!.join()
        model.beginSelection()
        val captured = model.uiState.value.items.filter { it.bulkSelectionField?.value in setOf("501", "502") }
        assertEquals(2, captured.size)
        captured.forEach { model.toggleSelection(it) }
        assertEquals(setOf("501", "502"), model.uiState.value.selectedItemIds.mapNotNull { id ->
            model.uiState.value.items.firstOrNull { it.id == id }?.bulkSelectionField?.value
        }.toSet())
        val openedIn = model.viewerScope()
        model.load(1, bypassCache = true)!!.join()
        assertTrue(model.uiState.value.selectedItemIds.isEmpty())
        model.startBulkAction(AO3InboxBulkAction.Delete, openedIn, captured)
        assertEquals(1, client.posts)
        assertEquals(
            setOf("501", "502"),
            client.postedFields.filter { it.first == "inbox_comments[]" }.map { it.second }.toSet()
        )
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
