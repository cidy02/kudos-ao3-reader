package io.github.cidy02.kudos.ui.subject

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

class WorkLibraryComponentsTest {
    @Test
    fun partialSwipeSettlesOpenWithoutCommittingAnAction() {
        assertEquals(0f, settleSwipeOffset(56f, 78f, 78f))
        assertEquals(78f, settleSwipeOffset(57f, 78f, 78f))
        assertEquals(-78f, settleSwipeOffset(-57f, 78f, 78f))
        assertEquals(0f, settleSwipeOffset(100f, 0f, 78f))
    }

    @Test
    fun homeCardMetricsMatchSpecification() {
        assertEquals(164.dp, HomeCardMetrics.width)
        assertEquals(16.dp, HomeCardMetrics.radius)
        assertEquals(12.dp, HomeCardMetrics.tileRadius)
    }
}

