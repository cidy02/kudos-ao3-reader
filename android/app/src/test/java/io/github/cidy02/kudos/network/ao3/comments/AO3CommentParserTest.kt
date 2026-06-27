package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.writes.writeResource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3CommentThreadParserTest {
    private val parser = AO3CommentParser()

    @Test
    fun parsesUnicodeCommentsAndNesting() {
        val thread = parser.parseThread(
            html = writeResource("ao3/comments/comments_basic.html"),
            finalUrl = "https://archiveofourown.org/works/123?show_comments=true",
            target = AO3CommentTarget.Work(123)
        )

        assertEquals(2, thread.comments.size)
        assertEquals("AO3_Reader", thread.comments[0].author.name)
        assertEquals("Hello, café ☕", thread.comments[0].body)
        assertEquals(1, thread.comments[1].depth)
        assertEquals("comment-token", thread.form?.authenticityToken)
        assertEquals("5", thread.form?.pseudId)
    }

    @Test
    fun handlesNoCommentsState() {
        val thread = parser.parseThread(
            html = writeResource("ao3/comments/comments_empty.html"),
            finalUrl = "https://archiveofourown.org/works/123?show_comments=true",
            target = AO3CommentTarget.Work(123)
        )

        assertTrue(thread.comments.isEmpty())
        assertEquals("comment-token", thread.form?.authenticityToken)
    }
}
