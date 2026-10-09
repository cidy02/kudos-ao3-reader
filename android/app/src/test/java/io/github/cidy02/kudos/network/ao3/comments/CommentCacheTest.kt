package io.github.cidy02.kudos.network.ao3.comments

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Audit A17-4: what a cached comment thread may hold, and whose it is. */
class CommentCacheTest {
    @Test fun aCachedThreadCarriesNothingThatCanAct() {
        val thread = AO3CommentThread(
            target = AO3CommentTarget.Work(123),
            comments = listOf(AO3Comment(
                id = "9", author = AO3CommentAuthor("writer"), date = "2026-10-01", body = "Thanks!",
                canReply = true, editPath = "/comments/9/edit", deletePath = "/comments/9",
                replies = listOf(AO3Comment(
                    id = "10", author = AO3CommentAuthor("writer"), date = "2026-10-02", body = "A reply",
                    canReply = true, editPath = "/comments/10/edit", deletePath = "/comments/10",
                    replies = listOf(AO3Comment(
                        id = "11", author = AO3CommentAuthor("reader"), date = "2026-10-03", body = "Deeper",
                        canReply = true, editPath = "/comments/11/edit", deletePath = "/comments/11"
                    ))
                ))
            )),
            form = AO3CommentForm(actionUrl = "https://archiveofourown.org/works/123/comments", authenticityToken = "secret-token", pseudId = "1")
        )
        val kept = CommentCache.readOnly(thread)
        assertNull("no form, so no token", kept.form)
        val comment = kept.comments.single()
        assertEquals("Thanks!", comment.body)
        assertNull(comment.editPath)
        assertNull(comment.deletePath)
        assertFalse(comment.canReply)
        // Replies, at every depth (audit A22-5): the words stay, nothing that acts does.
        val reply = comment.replies.single()
        val deeper = reply.replies.single()
        for (nested in listOf(reply, deeper)) {
            assertNull(nested.editPath)
            assertNull(nested.deletePath)
            assertFalse(nested.canReply)
        }
        assertEquals("A reply", reply.body)
        assertEquals("Deeper", deeper.body)
    }

    @Test fun eachViewerHasTheirOwnCopies() {
        assertEquals("anon", CommentCache.viewerKey(null))
        assertEquals("anon", CommentCache.viewerKey("  "))
        assertEquals(CommentCache.viewerKey("Reader"), CommentCache.viewerKey(" reader "))
        assertNotEquals(CommentCache.viewerKey("reader"), CommentCache.viewerKey("someone_else"))
        assertNotEquals("anon", CommentCache.viewerKey("anon")) // a user named "anon" is not the signed-out viewer
    }
}
