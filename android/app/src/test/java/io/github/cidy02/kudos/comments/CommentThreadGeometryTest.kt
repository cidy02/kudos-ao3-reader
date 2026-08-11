package io.github.cidy02.kudos.comments

import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentAuthor
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins the thread-size rules ported from iOS `CommentThreadGeometry`.
 *
 * The count is load-bearing: collapse is decided by the size of the whole
 * depth-first stack, not by nesting depth or direct-child count. A root with
 * three children each holding twenty replies is a wall of text however shallow
 * it looks, and Android previously collapsed on `depth > 2` instead.
 */
class CommentThreadGeometryTest {

    private fun comment(id: String, replies: List<AO3Comment> = emptyList()) = AO3Comment(
        id = id,
        author = AO3CommentAuthor(name = "a"),
        date = "",
        body = "b",
        replies = replies
    )

    @Test
    fun `counts every reply in the stack, not just direct children`() {
        val deep = comment(
            "root",
            listOf(
                comment("a", listOf(comment("a1"), comment("a2"))),
                comment("b", listOf(comment("b1", listOf(comment("b1a")))))
            )
        )
        // a, a1, a2, b, b1, b1a
        assertEquals(6, deep.totalReplyCount())
    }

    @Test
    fun `a childless comment counts zero`() {
        assertEquals(0, comment("solo").totalReplyCount())
    }

    @Test
    fun `a shallow but wide thread still exceeds the auto-expand threshold`() {
        // Nine direct children: depth is 1, so the old depth-based rule left this
        // fully expanded. Size-based collapse catches it.
        val wide = comment("root", (1..9).map { comment("c$it") })
        assertEquals(9, wide.totalReplyCount())
    }
}
