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
    fun endDetectedByTotalProgression() {
        val progress = ReaderProgress(
            spineIndex = 3,
            scrollFraction = 0.5,
            totalProgression = 0.99
        )
        assertTrue(EndOfWorkActions.isAtEndOfPublication(progress, spineCount = 10))
    }

    @Test
    fun notAtEndInMiddle() {
        val progress = ReaderProgress(
            spineIndex = 2,
            scrollFraction = 0.4,
            totalProgression = 0.4
        )
        assertFalse(EndOfWorkActions.isAtEndOfPublication(progress, spineCount = 10))
    }

    @Test
    fun endDetectedByLastSpineScroll() {
        val progress = ReaderProgress(
            spineIndex = 4,
            scrollFraction = 0.97,
            totalProgression = null
        )
        assertTrue(EndOfWorkActions.isAtEndOfPublication(progress, spineCount = 5))
    }
}
