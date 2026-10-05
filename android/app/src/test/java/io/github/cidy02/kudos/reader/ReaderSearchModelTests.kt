package io.github.cidy02.kudos.reader

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.LocatorCollection
import org.readium.r2.shared.publication.services.search.SearchError
import org.readium.r2.shared.publication.services.search.SearchIterator
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReaderSearchModelTests {
    @Test
    fun emptyQueriesDoNotSearchButOneCharacterQueriesDoAfterDebounce() = runTest {
        val queries = mutableListOf<String>()
        val iterator = TestIterator { Try.success(null) }
        val model = ReaderSearchModel(this, { queries.add(it); iterator }, StandardTestDispatcher(testScheduler))
        model.search(" \n ", null)
        advanceTimeBy(350)
        runCurrent()
        assertTrue(queries.isEmpty())
        model.search("old", null)
        runCurrent()
        advanceTimeBy(100)
        model.search(" a ", null)
        runCurrent()
        advanceTimeBy(349)
        runCurrent()
        assertTrue(queries.isEmpty())
        advanceTimeBy(1)
        runCurrent()
        assertEquals(listOf("a"), queries)
        assertEquals(ReaderSearchPhase.Done, model.state.value.phase)
        assertTrue(iterator.closed)
        model.reset()
    }

    @Test
    fun queryChangesAndResetRejectLateResultsAndCloseBothIterators() = runTest {
        val latePage = CompletableDeferred<Unit>()
        val old = TestIterator {
            withContext(NonCancellable) { latePage.await() }
            page(locator("old.xhtml"))
        }
        val replacement = TestIterator { page(locator("new.xhtml")) }
        val model = ReaderSearchModel(this, { if (it == "old") old else replacement }, StandardTestDispatcher(testScheduler))
        model.search("old", null, debounce = false)
        runCurrent()
        model.search("new", null, debounce = false)
        runCurrent()
        assertEquals("new.xhtml", model.state.value.hits.single().locator.href.toString())
        model.reset()
        runCurrent()
        latePage.complete(Unit)
        runCurrent()
        assertEquals(ReaderSearchState(), model.state.value)
        assertTrue(old.closed)
        assertTrue(replacement.closed)
    }

    @Test
    fun resetCancelsDebounceAndInFlightPage() = runTest {
        var opens = 0
        val iterator = TestIterator { awaitCancellation() }
        val model = ReaderSearchModel(this, { opens++; iterator }, StandardTestDispatcher(testScheduler))
        model.search("query", null)
        runCurrent()
        model.reset()
        advanceTimeBy(350)
        runCurrent()
        assertEquals(0, opens)
        model.search("query", null, debounce = false)
        runCurrent()
        assertEquals(1, iterator.calls)
        model.reset()
        runCurrent()
        assertTrue(iterator.closed)
        assertEquals(ReaderSearchState(), model.state.value)
    }

    @Test
    fun nearEndRequestsNeverOverlapIteratorCalls() = runTest {
        val secondPage = CompletableDeferred<Unit>()
        var pages = 0
        val iterator = TestIterator {
            pages++
            if (pages == 2) secondPage.await()
            page(locator("ch$pages.xhtml"))
        }
        val model = ReaderSearchModel(this, { iterator }, StandardTestDispatcher(testScheduler))
        model.search("query", null, debounce = false)
        runCurrent()
        repeat(5) { model.loadMoreIfNeeded(0) }
        runCurrent()
        repeat(5) { model.loadMoreIfNeeded(0) }
        runCurrent()
        assertEquals(2, iterator.calls)
        assertEquals(1, iterator.maxConcurrentCalls)
        secondPage.complete(Unit)
        runCurrent()
        assertEquals(listOf(0, 1), model.state.value.hits.map { it.id })
        assertFalse(model.state.value.isLoadingMore)
        model.reset()
        runCurrent()
        assertTrue(iterator.closed)
    }

    @Test
    fun currentChapterAutoPagesPastTheOldTwoHundredHitCap() = runTest {
        var pages = 0
        val iterator = TestIterator {
            when (pages++) {
                0 -> Try.success(LocatorCollection(locators = List(250) { locator("ch1.xhtml") }))
                1 -> page(locator("Text/CH2.XHTML#match"))
                else -> Try.success(null)
            }
        }
        val model = ReaderSearchModel(this, { iterator }, StandardTestDispatcher(testScheduler))
        model.search("query", "ch2.xhtml", debounce = false)
        runCurrent()
        assertEquals(2, iterator.calls)
        assertEquals(251, model.state.value.hits.size)
        assertFalse(model.state.value.isSearchingCurrentChapter)
        assertTrue(model.state.value.hasMore)
        model.loadMoreIfNeeded(250)
        runCurrent()
        assertFalse(model.state.value.hasMore)
        assertTrue(iterator.closed)
        model.reset()
    }

    @Test
    fun currentChapterAutoPagingIsBoundedThenContinuesOnDemand() = runTest {
        val iterator = TestIterator { page(locator("ch1.xhtml")) }
        val model = ReaderSearchModel(this, { iterator }, StandardTestDispatcher(testScheduler))
        model.search("query", "deep.xhtml", debounce = false)
        runCurrent()
        assertEquals(41, iterator.calls) // First page + iOS's maxAutoPages (40).
        assertTrue(model.state.value.isSearchingCurrentChapter)
        assertFalse(model.state.value.isLoadingMore)
        model.loadMoreIfNeeded(40)
        runCurrent()
        assertEquals(42, iterator.calls)
        model.reset()
        runCurrent()
    }

    @Test
    fun initialFailureIsShownAndPagingFailureKeepsLoadedHits() = runTest {
        val error = SearchError.Engine(object : org.readium.r2.shared.util.Error {
            override val message = "Unreadable local text"
            override val cause: org.readium.r2.shared.util.Error? = null
        })
        val initial = TestIterator { Try.failure(error) }
        val model = ReaderSearchModel(this, { initial }, StandardTestDispatcher(testScheduler))
        model.search("query", null, debounce = false)
        runCurrent()
        assertEquals(ReaderSearchPhase.Failed, model.state.value.phase)
        assertEquals(error.message, model.state.value.error)
        assertTrue(initial.closed)
        model.reset()
        var pages = 0
        val later = TestIterator { if (pages++ == 0) page(locator("ch1.xhtml")) else Try.failure(error) }
        val next = ReaderSearchModel(this, { later }, StandardTestDispatcher(testScheduler))
        next.search("query", null, debounce = false)
        runCurrent()
        next.loadMoreIfNeeded(0)
        runCurrent()
        assertEquals(ReaderSearchPhase.Done, next.state.value.phase)
        assertEquals(1, next.state.value.hits.size)
        assertFalse(next.state.value.hasMore)
        assertTrue(later.closed)
        next.reset()
    }

    @Test
    fun resultClipsOnlyLongLeadingContextAndCopiesTheUnmodifiedPassage() {
        val before = "Before ".repeat(20)
        val locator = locator("ch1.xhtml").copy(
            title = "Chapter 1",
            text = Locator.Text(before = before, highlight = "match", after = " after.")
        )
        val hit = ReaderSearchHit(0, locator)
        assertEquals("…" + before.takeLast(70), hit.before)
        assertEquals("match", hit.match)
        assertEquals(" after.", hit.after)
        assertEquals(before + "match after.", hit.copyText)
        assertEquals("Chapter 1", hit.chapterTitle)
        assertEquals("Short ", ReaderSearchHit(1, locator.copy(text = Locator.Text(before = "Short "))).before)
        val emoji = "👩‍💻"
        val emojiLocator = locator.copy(text = Locator.Text(before = emoji.repeat(80)))
        assertEquals("…" + emoji.repeat(70), ReaderSearchHit(2, emojiLocator).before)
    }

    private fun locator(href: String) = Locator(href = Url(href)!!, mediaType = MediaType.XHTML)
    private fun page(locator: Locator): Try<LocatorCollection?, SearchError> =
        Try.success(LocatorCollection(locators = listOf(locator)))

    /** Real SearchIterator contract, with controllable pages to exercise cancellation races. */
    private class TestIterator(private val page: suspend () -> Try<LocatorCollection?, SearchError>) : SearchIterator {
        var calls = 0
        var closed = false
        var maxConcurrentCalls = 0
        private var concurrentCalls = 0
        override suspend fun next(): Try<LocatorCollection?, SearchError> {
            calls++
            concurrentCalls++
            maxConcurrentCalls = maxOf(maxConcurrentCalls, concurrentCalls)
            try {
                return page()
            } finally {
                concurrentCalls--
            }
        }
        override fun close() { closed = true }
    }
}
