package io.github.cidy02.kudos.reader

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import io.github.cidy02.kudos.core.model.SavedWork
import org.junit.Assert.assertTrue
import org.junit.Test

class EndOfWorkActionsTest {
    @Test
    fun readerAo3ActionsPreferStoredIdentityThenSourceUrl() {
        val work = SavedWork(title = "Import", author = "Author")
        assertEquals(789L, EndOfWorkActions.forWork(work.copy(ao3WorkID = 789)).workId)
        assertEquals(789L, EndOfWorkActions.forWork(work.copy(
            ao3WorkID = 789, sourceUrl = "https://archiveofourown.org/works/123"
        )).workId)
        assertEquals(123L, EndOfWorkActions.forWork(work.copy(
            sourceUrl = "https://archiveofourown.org/works/123"
        )).workId)
        assertEquals(null, EndOfWorkActions.forWork(work).workId)
    }

    @Test
    fun longWorkAtTheOldTotalThresholdIsNotAtItsEndInEitherMode() {
        val progress = ReaderProgress(
            spineIndex = 3,
            scrollFraction = 0.5,
            totalProgression = 0.985
        )
        assertEquals(99, ReaderProgressDisplay.percent(progress))
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport(3, 50, 100), 10))
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport.scrolled(3, 5000.0, 100.0, 10000.0), 10))
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport(9, 99, 100), 10))
    }

    @Test
    fun notAtEndInMiddle() {
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport(2, 10, 10), 10))
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport.scrolled(2, 900.0, 100.0, 1000.0), 10))
    }

    @Test
    fun theOldLastChapterThresholdIsNotTheScrolledEnd() {
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport.scrolled(4, 9700.0, 100.0, 10000.0), 5))
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport.scrolled(4, 9899.9, 100.0, 10000.0), 5))
        assertTrue(EndOfWorkActions.isAtEndOfPublication(ReaderViewport.scrolled(4, 9900.0, 100.0, 10000.0), 5))
        // iOS can display the last rounded viewport page before its bottom is visible.
        val short = ReaderViewport.scrolled(4, 0.0, 100.0, 140.0)!!
        assertEquals(1, short.pageCount)
        assertFalse(EndOfWorkActions.isAtEndOfPublication(short, 5))
        assertTrue(EndOfWorkActions.isAtEndOfPublication(ReaderViewport.scrolled(4, 40.0, 100.0, 140.0), 5))
    }

    @Test
    fun lastPageSinglePageChapterAndSingleChapterWorkInBothModes() {
        for ((index, count) in listOf(9 to 10, 0 to 1)) {
            assertTrue(EndOfWorkActions.isAtEndOfPublication(ReaderViewport(index, 100, 100), count))
            assertTrue(EndOfWorkActions.isAtEndOfPublication(ReaderViewport(index, 1, 1), count))
            assertTrue(EndOfWorkActions.isAtEndOfPublication(ReaderViewport.scrolled(index, 900.0, 100.0, 1000.0), count))
            assertTrue(EndOfWorkActions.isAtEndOfPublication(ReaderViewport.scrolled(index, 0.0, 100.0, 50.0), count))
        }
    }

    @Test
    fun missingUnknownOrInvalidViewportNeverFinishes() {
        assertFalse(EndOfWorkActions.isAtEndOfPublication(null, 1))
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport(-1, 1, 1), 1))
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport(0, 0, 0), 1))
        assertFalse(EndOfWorkActions.isAtEndOfPublication(ReaderViewport(0, 1, 1), 0))
        assertEquals(null, ReaderViewport.scrolled(0, 0.0, 0.0, 100.0))
    }
}
