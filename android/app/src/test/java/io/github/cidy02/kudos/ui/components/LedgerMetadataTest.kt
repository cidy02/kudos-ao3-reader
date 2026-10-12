package io.github.cidy02.kudos.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

class LedgerMetadataTest {
    @Test
    fun aFullBlurbSaysItsFiguresInWords() {
        assertEquals(
            listOf("English", "12,345 words", "3/3", "1 comment", "80 kudos", "2 bookmarks", "900 hits"),
            ledgerMetadata("English", 12345, "3/3", 1, 80, 2, 900, showsZeroStats = false)
        )
    }

    @Test
    fun onAFullBlurbAMissingFigureIsAZeroShownOnlyWhenZerosAre() {
        assertEquals(
            listOf("English", "500 words", "1/1", "3 kudos"),
            ledgerMetadata("English", 500, "1/1", null, 3, null, null, showsZeroStats = false)
        )
        assertEquals(
            listOf("English", "500 words", "1/1", "0 comments", "3 kudos", "0 bookmarks", "0 hits"),
            ledgerMetadata("English", 500, "1/1", null, 3, null, null, showsZeroStats = true)
        )
    }

    @Test
    fun aSparseRowWithNoWordCountLeavesUnknownFiguresOut() {
        // Subscriptions and Marked for Later: no word count, so nothing is known to be zero.
        assertEquals(listOf("2/?"), ledgerMetadata(" ", null, "2/?", null, null, null, null, showsZeroStats = true))
    }

    @Test
    fun aBookmarksCardLeavesTheEngagementFiguresOut() {
        assertEquals(
            listOf("English", "12,345 words", "3/3"),
            ledgerMetadata("English", 12345, "3/3", 1, 80, 2, 900, showsZeroStats = true, includesPerformance = false)
        )
    }
}
