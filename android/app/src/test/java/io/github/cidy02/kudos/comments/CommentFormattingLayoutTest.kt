package io.github.cidy02.kudos.comments

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ports iOS `CommentPolishTests.theTrayIsFourColumnsUntilAccessibilitySizes`. */
class CommentFormattingLayoutTest {
    @Test fun theTrayIsFourColumnsUntilAccessibilitySizes() {
        assertEquals(4, CommentFormattingLayout.restingColumnCount)
        for (scale in listOf(0.85f, 1f, 1.15f, 1.3f)) assertEquals(4, CommentFormattingLayout.columnCount(scale))
        for (scale in listOf(1.5f, 1.7f)) assertEquals(2, CommentFormattingLayout.columnCount(scale))
        for (scale in listOf(1.8f, 2f, 3f)) assertEquals(1, CommentFormattingLayout.columnCount(scale))
        assertEquals(7, CommentFormattingLayout.gridGap)
        assertEquals(58, CommentFormattingLayout.tileMinHeight)
        assertTrue(CommentFormattingLayout.tilePaddingH > 0)
        assertTrue(CommentFormattingLayout.tilePaddingV > 0)
    }
}
