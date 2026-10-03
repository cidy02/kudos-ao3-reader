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

    @Test
    fun `flattenedReplies traverses depth-first preserving parent author`() {
        val root = AO3Comment(
            id = "100",
            author = AO3CommentAuthor(name = "AuthorRoot"),
            date = "",
            body = "root body",
            replies = listOf(
                AO3Comment(
                    id = "101",
                    author = AO3CommentAuthor(name = "Author1"),
                    date = "",
                    body = "reply 1",
                    replies = listOf(
                        AO3Comment(
                            id = "102",
                            author = AO3CommentAuthor(name = "Author2"),
                            date = "",
                            body = "reply 2"
                        )
                    )
                ),
                AO3Comment(
                    id = "103",
                    author = AO3CommentAuthor(name = "Author3"),
                    date = "",
                    body = "reply 3"
                )
            )
        )

        val flattened = CommentThreadGeometry.flattenedReplies(root)
        assertEquals(3, flattened.size)
        // Depth-first: 101, then 102 (child of 101), then 103
        assertEquals("101", flattened[0].id)
        assertEquals(1, flattened[0].depth)
        assertEquals("AuthorRoot", flattened[0].parentAuthor)

        assertEquals("102", flattened[1].id)
        assertEquals(2, flattened[1].depth)
        assertEquals("Author1", flattened[1].parentAuthor)

        assertEquals("103", flattened[2].id)
        assertEquals(1, flattened[2].depth)
        assertEquals("AuthorRoot", flattened[2].parentAuthor)
    }

    @Test
    fun `conversation builder auto-collapses threads with more than 8 replies`() {
        val root = AO3Comment(
            id = "100",
            author = AO3CommentAuthor(name = "Root"),
            date = "",
            body = "Root",
            replies = (1..10).map { comment("child-$it") }
        )
        val replies = CommentThreadGeometry.flattenedReplies(root)
        val repliesByRoot = mapOf(100L to replies)

        val rowsInitial = CommentConversationBuilder.rows(
            roots = listOf(root),
            repliesByRoot = repliesByRoot,
            expandedRootIds = emptySet(),
            visibleReplyCounts = emptyMap(),
            collapsedRootIds = emptySet()
        )

        // Root post + 1 Expander ("10 replies")
        assertEquals(2, rowsInitial.size)
        val firstRow = rowsInitial[0]
        val secondRow = rowsInitial[1]
        assert(firstRow.item is CommentConversationItem.Post)
        assert(secondRow.item is CommentConversationItem.Expander)
        val expander = secondRow.item as CommentConversationItem.Expander
        assertEquals(10, expander.hiddenCount)
        assertEquals(false, expander.showsVerb)

        // When expanded, all 10 replies should show as Posts
        val rowsExpanded = CommentConversationBuilder.rows(
            roots = listOf(root),
            repliesByRoot = repliesByRoot,
            expandedRootIds = setOf(100L),
            visibleReplyCounts = emptyMap(),
            collapsedRootIds = emptySet()
        )
        assertEquals(11, rowsExpanded.size) // 1 root + 10 replies
    }

    @Test
    fun `geometry clamps depth to maxInlineDepth 5`() {
        assertEquals(CommentThreadGeometry.avatarSize(0), CommentThreadGeometry.avatarSize(0))
        // Depth 0: 30dp, Depth 1: 26dp, Depth 2+: 22dp
        assertEquals(30f, CommentThreadGeometry.avatarSize(0).value)
        assertEquals(26f, CommentThreadGeometry.avatarSize(1).value)
        assertEquals(22f, CommentThreadGeometry.avatarSize(2).value)
        assertEquals(22f, CommentThreadGeometry.avatarSize(10).value) // clamped
    }
}
