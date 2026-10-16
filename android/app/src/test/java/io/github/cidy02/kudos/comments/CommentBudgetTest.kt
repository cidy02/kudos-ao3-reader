package io.github.cidy02.kudos.comments

import org.junit.Assert.assertEquals
import org.junit.Test

class CommentBudgetTest {
    // BrowseAndWorkDetailRulesTests.commentBudgetCountsCodePoints.
    @Test fun commentBudgetCountsUnicodeCodePoints() {
        val family = "\uD83D\uDC68\u200D\uD83D\uDC69\u200D\uD83D\uDC67"
        assertEquals(10_000 - 6, remainingCommentCharacters("a$family"))
        assertEquals(0, remainingCommentCharacters("x".repeat(10_000)))
        assertEquals(10_000, remainingCommentCharacters(""))
        assertEquals(0, remainingCommentCharacters("\uD83D\uDC68".repeat(10_000)))
        assertEquals(-1, remainingCommentCharacters("x".repeat(10_001)))
    }
}
