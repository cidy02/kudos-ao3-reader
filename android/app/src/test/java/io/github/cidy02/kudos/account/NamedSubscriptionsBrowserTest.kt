package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.assertIsNotEnabled
import io.github.cidy02.kudos.network.ao3.AO3FormPostClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.CanonicalWork
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class NamedSubscriptionsBrowserTest {
    @get:Rule val compose = createComposeRule()
    private val client = NamedTabClient()
    private var openedSeries: String? = null
    private var openedAuthor: String? = null

    private lateinit var auth: AO3AuthRepository

    private fun show(signedIn: Boolean = true, initialScope: String = "works", initialPage: Int = 1, withWork: Boolean = false) {
        auth = AO3AuthRepository(MemorySessionStore(if (signedIn) testSession() else null), MemoryCookieStore())
        runBlocking { auth.restoreSession() }
        val repository = AccountListRepository(client, auth)
        val writer = SubscriptionUnsubscribeState(AO3WriteRepository(DefaultAO3AuthenticatedClient(client, client, auth)), auth)
        compose.setContent {
            MaterialTheme {
                var scope by remember { mutableStateOf(initialScope) }
                var page by remember(scope) { mutableStateOf(initialPage) }
                val namedScope = AO3NamedSubscriptionsScope.entries.firstOrNull { it.parameter == scope }
                val loader = remember(namedScope, page) {
                    namedScope?.let { NamedSubscriptionsLoader(repository, it, page) }
                }
                var workRows by remember { mutableStateOf(if (withWork) listOf(CanonicalWork(null,
                    AO3WorkSummary(123, "Work subscription", emptyList(), emptyList(), "", emptyList(), emptyList(), chapters = "1/1")
                )) else emptyList()) }
                SubscriptionsBrowser(
                    works = workRows, watermarks = emptyMap(), scope = scope,
                    onScopeChange = { scope = it }, onUnsubscribeWork = { work -> workRows = workRows.filterNot { it.id == work.id } },
                    unsubscribePaths = mapOf(123L to "/users/me/subscriptions/987"), unsubscribeState = writer,
                    currentPage = 1, totalPages = 1, expandAll = false,
                    palette = SubjectPalette.fromHue(210.0, ReaderTheme.Light),
                    onLoadPage = {}, onOpenWork = {},
                    worksState = AccountListUiState.Loaded(AO3SearchPage(emptyList(), 1, 1)),
                    namedLoader = loader, namedScope = namedScope,
                    onNamedPageChange = { page = it }, onLogin = {},
                    onOpenSeries = { openedSeries = it }, onOpenAuthor = { openedAuthor = it }
                )
            }
        }
    }

    private fun waitForText(text: String) {
        compose.waitUntil(5_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test fun onlyShownTabFetchesAndRowsCountsPagingAndRefreshFollowIt() {
        show()
        compose.waitForIdle()
        assertTrue(client.requests.isEmpty())
        compose.onNodeWithText("Series").performClick()
        waitForText("My Series")
        assertEquals(listOf("series"), client.requests.map { it.toHttpUrl().queryParameter("type") })
        compose.onNodeWithText("1 series · page 1 of 3").assertExists()
        compose.onNodeWithText("by seriesauthor").assertExists()
        compose.onNodeWithText("My Series").performClick()
        assertEquals("https://archiveofourown.org/series/999", openedSeries)
        compose.onAllNodesWithContentDescription("Next Page")[0].performClick()
        waitForText("1 series · page 2 of 3")
        assertEquals("2", client.requests.last().toHttpUrl().queryParameter("page"))
        // Pulling the current tab repeats exactly its current-page address.
        val previous = client.requests.size
        compose.onRoot().performTouchInput { swipeDown(startY = height * 0.2f, endY = height * 0.8f) }
        compose.waitUntil(5_000) { client.requests.size > previous }
        waitForText("1 series · page 2 of 3")
        assertEquals(client.requests[previous - 1], client.requests[previous])
        compose.onNodeWithText("Authors").performClick()
        waitForText("someuser")
        compose.onNodeWithText("1 author").assertExists()
        assertEquals("users", client.requests.last().toHttpUrl().queryParameter("type"))
        assertEquals(null, client.requests.last().toHttpUrl().queryParameter("page"))
        compose.onNodeWithText("someuser").performClick()
        assertEquals("someuser", openedAuthor)
    }

    @Test fun signedOutTabShowsSessionStateWithoutFetchingOrClaimingNone() {
        show(signedIn = false)
        compose.onNodeWithText("Series").performClick()
        waitForText("AO3 session required")
        compose.onNodeWithText("No series subscriptions").assertDoesNotExist()
        assertTrue(client.requests.isEmpty())
    }

    @Test fun waitingForAo3ShowsLoadingRatherThanAnEmptyList() {
        val reply = CompletableDeferred<Unit>()
        client.gate = reply
        show()
        compose.onNodeWithText("Series").performClick()
        waitForText("Loading Subscriptions")
        compose.onNodeWithText("No series subscriptions").assertDoesNotExist()
        compose.onNodeWithText("0 series").assertDoesNotExist()
        reply.complete(Unit)
        waitForText("My Series")
    }

    @Test fun noneResponseShowsEmptyButFailureShowsRetryAndCanRecover() {
        client.fail = true
        show()
        compose.onNodeWithText("Authors").performClick()
        waitForText("Couldn't load your list")
        compose.onNodeWithText("No author subscriptions").assertDoesNotExist()
        compose.onNodeWithText("Try Again").assertExists()
        client.fail = false
        client.empty = true
        compose.onNodeWithText("Try Again").performClick()
        waitForText("No author subscriptions")
        compose.onNodeWithText("Authors you subscribe to on AO3 show up here.").assertExists()
        compose.onNodeWithText("0 authors").assertExists()
        assertEquals(2, client.requests.size)
    }

    private fun confirm() {
        compose.onNode(hasText("Unsubscribe") and hasAnyAncestor(isDialog())).performClick()
    }

    @Test fun namedConfirmationIsRequiredAndCancelNeverPosts() {
        show(initialScope = "series")
        waitForText("My Series")
        assertTrue(client.posts.isEmpty())
        compose.onNodeWithText("Unsubscribe").performClick()
        waitForText("Unsubscribe?")
        compose.onNodeWithText("“My Series” will be removed from your AO3 subscriptions. You will stop getting update emails for it.").assertExists()
        assertTrue(client.posts.isEmpty())
        compose.onNodeWithText("Cancel").performClick()
        compose.waitForIdle()
        assertTrue(client.posts.isEmpty())
        compose.onNodeWithText("My Series").assertExists()
    }

    @Test fun seriesSuccessRemovesLastRowAndStepsBackFromLaterPage() {
        show(initialScope = "series", initialPage = 2)
        waitForText("1 series · page 2 of 3")
        compose.onNodeWithText("Unsubscribe").performClick()
        confirm()
        waitForText("0 series · page 1 of 3")
        compose.onNodeWithText("My Series").assertDoesNotExist()
        assertEquals(1, client.posts.size)
        assertEquals(null, client.requests.last().toHttpUrl().queryParameter("page"))
    }

    @Test fun authorFailureKeepsRowAndShowsIosAlert() {
        client.failWrite = true
        show(initialScope = "users")
        waitForText("someuser")
        compose.onNodeWithText("Unsubscribe").performClick()
        confirm()
        waitForText("Couldn't unsubscribe")
        compose.onNodeWithText("someuser").assertExists()
        assertEquals(1, client.posts.size)
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithText("Unsubscribe").assertExists()
    }

    @Test fun workConfirmationPostsOnceShowsBusyAndRemovesOnlyAfterConfirmationFromAo3() {
        val reply = CompletableDeferred<Unit>()
        client.postGate = reply
        show(withWork = true)
        waitForText("Work subscription")
        compose.onNodeWithText("Unsubscribe").performClick()
        compose.onNodeWithText("“Work subscription” will be removed from your AO3 subscriptions. The work stays on AO3.").assertExists()
        assertTrue(client.posts.isEmpty())
        confirm()
        waitForText("Unsubscribing…")
        compose.onNodeWithText("Unsubscribing…").assertIsNotEnabled()
        compose.onNodeWithText("Work subscription").assertExists()
        assertEquals(1, client.posts.size)
        reply.complete(Unit)
        waitForText("No subscriptions")
        compose.onNodeWithText("Work subscription").assertDoesNotExist()
        assertEquals(1, client.posts.size)
    }

}

/** This is the terminal client; no request can leave the test process. */
private class NamedTabClient : AO3Client, AO3FormPostClient {
    val posts = CopyOnWriteArrayList<String>()
    @Volatile var failWrite = false
    @Volatile var postGate: CompletableDeferred<Unit>? = null
    override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts.add(url)
        postGate?.await()
        if (!failWrite) empty = true
        return AO3Result.Success(AO3HttpResponse(url, if (failWrite) 422 else 200, emptyMap(),
            if (failWrite) "<div class='flash error'>Couldn't unsubscribe.</div>" else "<div class='flash notice'>Unsubscribed.</div>"))
    }
    val requests = CopyOnWriteArrayList<String>()
    @Volatile var fail = false
    @Volatile var empty = false
    @Volatile var gate: CompletableDeferred<Unit>? = null
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        requests.add(url)
        gate?.await()
        if (fail) return AO3Result.Failure(AO3Error.Network("Test failure"))
        val body = if (empty) "<p class='notes'>You have no subscriptions.</p>" +
            (if (url.toHttpUrl().queryParameter("type") == "series") "<ol class='pagination'><li>1</li><li>2</li><li>3</li></ol>" else "") else
            if (url.toHttpUrl().queryParameter("type") == "series") {
                """<dl class="subscription"><dt><a href="/series/999">My Series</a>
                    by <a rel="author" href="/users/seriesauthor/pseuds/seriesauthor">seriesauthor</a></dt><dd><form action="/users/me/subscriptions/987"></form></dd></dl>
                    <ol class="pagination"><li>1</li><li>2</li><li>3</li></ol>"""
            } else "<dl class='subscription'><dt><a href='/users/someuser'>someuser</a></dt><dd><form action='/users/me/subscriptions/987'></form></dd></dl>"
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), "<meta name='csrf-token' content='fresh-test-token'>" + body))
    }
}
