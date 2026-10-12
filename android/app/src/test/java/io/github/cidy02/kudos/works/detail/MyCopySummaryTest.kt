package io.github.cidy02.kudos.works.detail

import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `WorkDetailComponents.myCopySummary`. */
class MyCopySummaryTest {
    @Test
    fun theLineCountsWhatIsKeptInIosOrder() {
        assertEquals("Downloaded · 1 queue · 1 collection", myCopySummary(true, 1, 1, 0))
        assertEquals("2 queues · 3 collections · 1 tag", myCopySummary(false, 2, 3, 1))
        assertEquals("You haven't saved anything on this device yet", myCopySummary(false, 0, 0, 0))
    }
}
