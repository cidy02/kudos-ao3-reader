package io.github.cidy02.kudos.reader.readium

import io.github.cidy02.kudos.reader.ReaderViewport
import org.junit.Assert.*
import org.junit.Test

class ReaderPageSampleTest {
    // ReaderPageSampleTests.theGuardIsOnTheBodyAndTheWindow.
    @Test fun sampleGuardRejectsBlankBodyAndTinyWindowBeforeReadingExtents() {
        assertTrue(SCROLL_EXTENT_SCRIPT.contains("!document.body.firstChild"))
        assertTrue(SCROLL_EXTENT_SCRIPT.contains("window.innerWidth || 0) < 32"))
        assertTrue(SCROLL_EXTENT_SCRIPT.contains("window.innerHeight || 0) < 32"))
        assertTrue(SCROLL_EXTENT_SCRIPT.indexOf("return null") < SCROLL_EXTENT_SCRIPT.indexOf("return vertical"))
    }

    @Test fun tinyAndInvalidSamplesNeverPublishAPageCount() {
        for (extent in listOf(0.0, 1.0, 31.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertNull(ReaderViewport.scrolled(0, 0.0, extent, 1000.0))
        }
        assertNotNull(ReaderViewport.scrolled(0, 0.0, 32.0, 1000.0))
    }
}
