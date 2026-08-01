package io.github.cidy02.kudos.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReaderProgressDisplayTest {

    @Test
    fun prefersTotalProgressionForPercent() {
        val progress = ReaderProgress(
            spineIndex = 0,
            scrollFraction = 0.1,
            totalProgression = 0.42
        )
        assertEquals(42, ReaderProgressDisplay.percent(progress, spineCount = 10))
        assertEquals("Ch. 1/10 · 42%", ReaderProgressDisplay.label(progress, 10))
    }

    @Test
    fun estimatesFromSpineWhenTotalMissing() {
        // spine 1 of 4 + half way through → (1.5 / 4) = 37%
        val progress = ReaderProgress(spineIndex = 1, scrollFraction = 0.5)
        assertEquals(37, ReaderProgressDisplay.percent(progress, spineCount = 4))
    }

    @Test
    fun nullProgressYieldsNullPercentAndEmptyLabel() {
        assertNull(ReaderProgressDisplay.percent(null, spineCount = 5))
        assertEquals("", ReaderProgressDisplay.label(null, 5))
    }

    @Test
    fun clampsTotalProgression() {
        val progress = ReaderProgress(
            spineIndex = 0,
            scrollFraction = 0.0,
            totalProgression = 1.5
        )
        assertEquals(100, ReaderProgressDisplay.percent(progress, spineCount = 3))
    }
}
