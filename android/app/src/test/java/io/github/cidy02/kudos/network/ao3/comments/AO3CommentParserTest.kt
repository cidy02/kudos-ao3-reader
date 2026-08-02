package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.writes.writeResource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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

        // Top-level comments only (nested reply is a separate li.comment with depth).
        assertEquals(4, thread.comments.size)
        assertEquals("AO3_Reader", thread.comments[0].author.name)
        assertEquals("Hello, café ☕", thread.comments[0].body)
        val reply = thread.comments.first { it.author.name == "ReplyUser" }
        assertEquals(1, reply.depth)
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

    @Test
    fun parsesWorkAuthorsFromPrefaceByline() {
        val thread = parser.parseThread(
            html = writeResource("ao3/comments/comments_basic.html"),
            finalUrl = "https://archiveofourown.org/works/123?show_comments=true",
            target = AO3CommentTarget.Work(123)
        )

        assertEquals(1, thread.workAuthors.size)
        assertEquals("Work Author", thread.workAuthors[0].displayName)
        assertEquals("WorkAuthor", thread.workAuthors[0].username)
    }

    @Test
    fun parsesAvatarRejectingDefaultSkinIcon() {
        val thread = parser.parseThread(
            html = writeResource("ao3/comments/comments_basic.html"),
            finalUrl = "https://archiveofourown.org/works/123?show_comments=true",
            target = AO3CommentTarget.Work(123)
        )

        val first = thread.comments.first { it.author.name == "AO3_Reader" }
        assertEquals(
            "https://archiveofourown.org/images/icons/AO3_Reader.png",
            first.avatarUrl
        )
        assertEquals("AO3_Reader", first.author.username)
        assertFalse(first.isGuest)

        val reply = thread.comments.first { it.author.name == "ReplyUser" }
        // Default AO3 skin icon must become null, not a renderable avatar.
        assertNull(reply.avatarUrl)
    }

    @Test
    fun parsesGuestAndAnonymousCreatorFlags() {
        val thread = parser.parseThread(
            html = writeResource("ao3/comments/comments_basic.html"),
            finalUrl = "https://archiveofourown.org/works/123?show_comments=true",
            target = AO3CommentTarget.Work(123)
        )

        val guest = thread.comments.first { it.id == "comment_3" }
        assertTrue(guest.isGuest)
        assertFalse(guest.isAnonymousCreator)
        assertEquals("Curious Guest", guest.author.name)
        assertNull(guest.avatarUrl)
        assertNull(guest.author.username)

        val anon = thread.comments.first { it.id == "comment_4" }
        assertTrue(anon.isAnonymousCreator)
        assertFalse(anon.isGuest)
        assertEquals("Anonymous Creator", anon.author.name)
    }

    @Test
    fun parsesPaginationAndTotalComments() {
        val thread = parser.parseThread(
            html = writeResource("ao3/comments/comments_paginated.html"),
            finalUrl = "https://archiveofourown.org/works/123?show_comments=true",
            target = AO3CommentTarget.Work(123),
            page = 1
        )

        assertEquals(1, thread.currentPage)
        // Max numeric li in ol.pagination is 5; non-numeric "Next →" / "…" skipped.
        assertEquals(5, thread.totalPages)
        assertEquals(42, thread.totalComments)
        assertEquals(2, thread.comments.size)
    }

    @Test
    fun totalPagesNeverBelowRequestedPage() {
        val thread = parser.parseThread(
            html = writeResource("ao3/comments/comments_empty.html"),
            finalUrl = "https://archiveofourown.org/works/123?show_comments=true&page=3",
            target = AO3CommentTarget.Work(123),
            page = 3
        )

        assertEquals(3, thread.currentPage)
        assertEquals(3, thread.totalPages)
    }

    @Test
    fun parsesCanReplyAndNumericId() {
        val thread = parser.parseThread(
            html = writeResource("ao3/comments/comments_paginated.html"),
            finalUrl = "https://archiveofourown.org/works/123?show_comments=true",
            target = AO3CommentTarget.Work(123)
        )

        val withReply = thread.comments.first { it.id == "comment_1252794206" }
        assertTrue(withReply.canReply)
        assertEquals(1_252_794_206L, withReply.numericId)

        val noReply = thread.comments.first { it.id == "comment_99" }
        assertFalse(noReply.canReply)
        assertEquals(99L, noReply.numericId)
    }

    @Test
    fun basicFixtureHasNoReplyActions() {
        val thread = parser.parseThread(
            html = writeResource("ao3/comments/comments_basic.html"),
            finalUrl = "https://archiveofourown.org/works/123?show_comments=true",
            target = AO3CommentTarget.Work(123)
        )

        assertTrue(thread.comments.none { it.canReply })
        assertEquals(1, thread.currentPage)
        assertEquals(1, thread.totalPages)
        assertNull(thread.totalComments)
    }
}
