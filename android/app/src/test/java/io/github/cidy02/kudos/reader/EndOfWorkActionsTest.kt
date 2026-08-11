package io.github.cidy02.kudos.reader

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EndOfWorkActionsTest {
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
