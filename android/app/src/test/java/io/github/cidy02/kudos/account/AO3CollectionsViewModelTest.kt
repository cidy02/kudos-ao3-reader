package io.github.cidy02.kudos.account

import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.viewModelScope
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.job
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/** All requests terminate at this in-memory client; these tests cannot contact AO3. */
@OptIn(ExperimentalCoroutinesApi::class)
class AO3CollectionsViewModelTest {
    private val dispatcher = UnconfinedTestDispatcher()
    private val stores = mutableListOf<ViewModelStore>()
    private val scopes = mutableListOf<Job>()

    @Before fun setUp() { Dispatchers.setMain(dispatcher) }
    @After fun tearDown() {
        stores.forEach { it.clear() }
        // A page is parsed on a real thread, and an unconfined Main carries on from there: a
        // cancelled model can still be unwinding on that thread. Let it finish before Main goes,
        // or its last step lands on no Main at all and fails whichever test starts next.
        runBlocking { withTimeoutOrNull(5_000) { scopes.joinAll() } }
        Dispatchers.resetMain()
    }

    private suspend fun model(client: CollectionsClient): Pair<AO3CollectionsViewModel, AO3AuthRepository> {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val model = AO3CollectionsViewModel(AccountListRepository(client = client, authRepository = auth))
        stores.add(ViewModelStore().apply { put("collections", model) })
        scopes.add(model.viewModelScope.coroutineContext.job)
        model.onAppear()
        model.uiState.first { it is AO3CollectionsUiState.Loaded }
        return model to auth
    }

    private suspend fun whole(model: AO3CollectionsViewModel): AO3CollectionsUiState.Loaded =
        model.uiState.first { it is AO3CollectionsUiState.Loaded && it.wholeIndex != null } as AO3CollectionsUiState.Loaded

    @Test fun reusesPageOneAndFetchesSequentiallyWithoutRefetchingForAnotherFilter() = runTest(dispatcher) {
        val client = CollectionsClient(totalPages = 3)
        val (model, _) = model(client)
        assertEquals(listOf(1), client.pages)
        model.setFilters(AO3CollectionsFilter(sort = AO3CollectionsFilter.Sort.Title))
        val state = whole(model)
        assertEquals(listOf(1, 2, 3), client.pages)
        assertEquals(listOf("page-1", "page-2", "page-3"), state.wholeIndex!!.map { it.name })
        assertEquals(1, client.maximumConcurrent)
        model.setFilters(AO3CollectionsFilter(showsModeratedOnly = true))
        assertEquals(listOf(1, 2, 3), client.pages)
        model.clearFilters()
        model.setFilters(AO3CollectionsFilter(showsOpenOnly = true))
        assertEquals(listOf(1, 2, 3), client.pages)
        model.onDisappear()
    }

    @Test fun filteringFromALaterPageStartsAtPageOneAndFilteredRefreshReusesFreshPageOne() = runTest(dispatcher) {
        val client = CollectionsClient(totalPages = 3)
        val (model, _) = model(client)
        model.loadPage(3)
        model.uiState.first { it is AO3CollectionsUiState.Loaded && it.currentPage == 3 }
        model.setFilters(AO3CollectionsFilter(showsOpenOnly = true))
        whole(model)
        assertEquals(listOf(1, 3, 1, 2, 3), client.pages)
        model.refresh()
        whole(model)
        assertEquals(listOf(1, 3, 1, 2, 3, 1, 2, 3), client.pages)
        client.failingPage = 1
        model.refresh()
        assertTrue(model.uiState.first { it is AO3CollectionsUiState.Failed } is AO3CollectionsUiState.Failed)
        client.failingPage = null
        model.load()
        whole(model)
        assertEquals(listOf(1, 3, 1, 2, 3, 1, 2, 3, 1, 1, 2, 3), client.pages)
        model.onDisappear()
    }

    @Test fun capsAtTwentyFiveAndReportsThePartialList() = runTest(dispatcher) {
        val client = CollectionsClient(totalPages = 31)
        val (model, _) = model(client)
        model.setFilters(AO3CollectionsFilter(showsOpenOnly = true))
        val state = whole(model)
        assertEquals((1..25).toList(), client.pages)
        assertEquals(25, state.wholeIndex!!.size)
        assertEquals("first 25 of 31 pages", state.wholeIndexPartialNote)
        model.onDisappear()
    }

    @Test fun anEmptyPageStopsTheCrawlWithoutACapNote() = runTest(dispatcher) {
        val client = CollectionsClient(totalPages = 31, emptyPage = 2)
        val (model, _) = model(client)
        model.setFilters(AO3CollectionsFilter(showsOpenOnly = true))
        val state = whole(model)
        assertEquals(listOf(1, 2), client.pages)
        assertEquals(listOf("page-1"), state.wholeIndex!!.map { it.name })
        assertNull(state.wholeIndexPartialNote)
        model.onDisappear()
    }

    @Test fun clearingFiltersCancelsTheCrawlAndRestoresTheOrdinaryPage() = runTest(dispatcher) {
        val client = CollectionsClient(totalPages = 3, heldPage = 2)
        val (model, _) = model(client)
        model.setFilters(AO3CollectionsFilter(showsOpenOnly = true))
        client.pageHeld.await()
        model.clearFilters()
        client.finishHeldPage()
        client.pageFinished.await()
        val state = model.uiState.first {
            it is AO3CollectionsUiState.Loaded && !it.wholeIndexLoading
        } as AO3CollectionsUiState.Loaded
        assertNull(state.wholeIndex)
        assertEquals(listOf("page-1"), state.collections.map { it.name })
        assertEquals(listOf(1, 2), client.pages)
        model.onDisappear()
    }

    @Test fun leavingTheScreenCancelsRemainingPages() = runTest(dispatcher) {
        val client = CollectionsClient(totalPages = 3, heldPage = 2)
        val (model, _) = model(client)
        model.setFilters(AO3CollectionsFilter(showsOpenOnly = true))
        client.pageHeld.await()
        model.onDisappear()
        client.finishHeldPage()
        client.pageFinished.await()
        assertEquals(listOf(1, 2), client.pages)
    }

    @Test fun aReplacementCrawlWaitsForTheRetiredRequestToFinish() = runTest(dispatcher) {
        val client = CollectionsClient(totalPages = 3, heldPage = 2)
        val (model, _) = model(client)
        model.setFilters(AO3CollectionsFilter(showsOpenOnly = true))
        client.pageHeld.await()
        model.clearFilters()
        model.setFilters(AO3CollectionsFilter(showsModeratedOnly = true))
        assertEquals(listOf(1, 2), client.pages)
        client.finishHeldPage()
        val state = whole(model)
        assertEquals(listOf(1, 2, 2, 3), client.pages)
        assertEquals(listOf("page-1", "page-2", "page-3"), state.wholeIndex!!.map { it.name })
        assertEquals(1, client.maximumConcurrent)
        model.onDisappear()
    }

    @Test fun wholeIndexFailureHasItsOwnRetryAndDoesNotPublishAPartialAccumulator() = runTest(dispatcher) {
        val client = CollectionsClient(totalPages = 3, failingPage = 2)
        val (model, _) = model(client)
        model.setFilters(AO3CollectionsFilter(showsOpenOnly = true))
        val failed = model.uiState.first {
            it is AO3CollectionsUiState.Loaded && it.wholeIndexError != null
        } as AO3CollectionsUiState.Loaded
        assertNull(failed.wholeIndex)
        // Cancel resolves to the same filter; editing an already-active rule
        // does not change iOS's whole-index task ID or implicitly retry a failure.
        model.setFilters(model.filters.value)
        model.setFilters(model.filters.value.copy(showsModeratedOnly = true))
        assertEquals(listOf(1, 2), client.pages)
        client.failingPage = null
        model.load()
        whole(model)
        assertEquals(listOf(1, 2, 2, 3), client.pages)
        model.onDisappear()
    }

    @Test fun aSessionChangeCancelsTheCrawlAndHidesAccountRows() = runTest(dispatcher) {
        val client = CollectionsClient(totalPages = 3, heldPage = 2)
        val (model, auth) = model(client)
        model.setFilters(AO3CollectionsFilter(showsOpenOnly = true))
        client.pageHeld.await()
        auth.logout()
        client.finishHeldPage()
        client.pageFinished.await()
        assertEquals(AO3CollectionsUiState.AuthRequired, model.uiState.first { it == AO3CollectionsUiState.AuthRequired })
        assertEquals(listOf(1, 2), client.pages)
        assertTrue(model.filters.value.showsOpenOnly)
        model.onDisappear()
    }

    @Test fun indexParserKeepsUnknownCountsAndPageMetadata() {
        val page = AO3AccountParser().parseCollectionsIndex(
            """<ol class="pagination"><li>1</li><li>4</li></ol><ul class="collection index">
            <li class="collection blurb"><h4 class="heading"><a href="/collections/unknown">Unknown</a></h4>
            <dl class="stats"><dd class="works">not a count</dd></dl></li>
            <li class="collection blurb"><h4 class="heading"><a href="/collections/zero">Zero</a></h4>
            <dl class="stats"><dd class="works">0</dd><dd class="bookmarks">1,234</dd></dl></li></ul>""",
            page = 2
        )
        assertEquals(2, page.currentPage)
        assertEquals(4, page.totalPages)
        assertNull(page.collections.first().worksCount)
        assertNull(page.collections.first().bookmarksCount)
        assertEquals(0, page.collections.last().worksCount)
        assertEquals(1234, page.collections.last().bookmarksCount)
    }
}

private class CollectionsClient(
    private val totalPages: Int,
    private val emptyPage: Int? = null,
    private val heldPage: Int? = null,
    var failingPage: Int? = null
) : AO3Client {
    val pages = mutableListOf<Int>()
    val pageHeld = CompletableDeferred<Unit>()
    val pageFinished = CompletableDeferred<Unit>()
    private val release = CompletableDeferred<Unit>()
    private var concurrent = 0
    var maximumConcurrent = 0
        private set

    fun finishHeldPage() { release.complete(Unit) }

    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        val page = url.substringAfter("page=", "1").substringBefore('&').toInt()
        pages.add(page)
        concurrent += 1
        maximumConcurrent = maxOf(maximumConcurrent, concurrent)
        try {
            if (page == heldPage) {
                pageHeld.complete(Unit)
                try { release.await() } finally { pageFinished.complete(Unit) }
            }
            if (page == failingPage) return AO3Result.Failure(AO3Error.Parse("Unreadable page"))
            val row = if (page == emptyPage) "" else """
                <li class="collection blurb"><h4 class="heading"><a href="/collections/page-$page">Page $page</a></h4>
                <p class="type">Open, Moderated</p><dl class="stats"><dd class="works">$page</dd></dl></li>
            """
            return AO3Result.Success(AO3HttpResponse(
                url, 200, emptyMap(),
                "<ol class='pagination'><li>$totalPages</li></ol><ul class='collection index'>$row</ul>"
            ))
        } finally { concurrent -= 1 }
    }
}
