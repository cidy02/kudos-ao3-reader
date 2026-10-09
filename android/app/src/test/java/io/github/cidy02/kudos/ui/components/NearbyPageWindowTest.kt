package io.github.cidy02.kudos.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `SearchPaginationTests`, the four nearby-window cases, by name. */
class NearbyPageWindowTest {
    @Test fun nearbyWindowCentresOnTheCurrentPage() {
        assertEquals((96..105).toList(), nearbyPageWindow(100, 3_216))
    }

    @Test fun nearbyWindowSlidesInsteadOfTruncatingAtTheEnds() {
        assertEquals((1..10).toList(), nearbyPageWindow(2, 3_216))
        assertEquals((3_207..3_216).toList(), nearbyPageWindow(3_216, 3_216))
    }

    @Test fun nearbyWindowShrinksToShortLists() {
        assertEquals(listOf(1, 2, 3), nearbyPageWindow(2, 3))
        assertEquals(listOf(1), nearbyPageWindow(1, 1))
    }

    @Test fun nearbyWindowIsEmptyWithNoPages() {
        assertTrue(nearbyPageWindow(1, 0).isEmpty())
    }
}
