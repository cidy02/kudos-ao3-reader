package io.github.cidy02.kudos.network.ao3.inbox

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Parser + fail-closed bulk/filter form tests for AO3 Inbox.
 * Selectors mirror iOS `AO3Client+Inbox.swift` / `AO3InboxParseTests`.
 */
class AO3InboxParserTest {
    private val parser = AO3InboxParser()

    private val basicHtml = """
        <html><body class="logged-in">
        <h2 class="heading">My Inbox (12 comments, 3 unread)</h2>
        <form id="inbox-form" class="inbox manage" action="/users/tester/inbox" method="post">
          <ol class="comment index group">
            <li class="unread comment group even" role="article" id="feedback_comment_9001">
              <h4 class="heading byline">
                <a href="/users/reader1/pseuds/ReaderOne">ReaderOne</a> on
                <a href="/works/123456/comments/9001">Chapter 3 of My Great Fic</a>
                <span class="posted datetime">3 days ago</span>
              </h4>
              <div class="icon">
                <a href="/users/reader1/pseuds/ReaderOne"><img alt="" class="icon"
                  src="https://example.com/icons/1/standard.png"></a>
              </div>
              <blockquote class="userstuff"><p>Loved this chapter so much!</p></blockquote>
              <ul class="actions" role="menu">
                <li><span class="unread">Unread</span></li>
                <li><a href="/comments/9001/reply">Reply</a></li>
                <li><label><input type="checkbox" name="inbox_comments[]" value="1">Select</label></li>
              </ul>
            </li>
            <li class="read comment group odd" role="article" id="feedback_comment_9002">
              <h4 class="heading byline">
                <span>Driveby Guest</span><span class="role"> (Guest)</span> on
                <a href="/works/123456/comments/9002">My Great Fic</a>
                <span class="posted datetime">5 days ago</span>
              </h4>
              <div class="icon"><span class="visitor icon"></span></div>
              <blockquote class="userstuff"><p>Nice one.</p></blockquote>
              <ul class="actions" role="menu">
                <li><span class="replied" title="replied to">&#10004;</span></li>
              </ul>
            </li>
            <li class="read comment group even" role="article" id="feedback_comment_9003">
              <h4 class="heading byline">
                <a href="/users/tagfan/pseuds/tagfan">tagfan</a> on
                <a href="/tags/Some%20Tag/comments/9003">Some Tag</a>
                <span class="posted datetime">2 weeks ago</span>
              </h4>
              <div class="icon"></div>
              <blockquote class="userstuff"><p>Tag comment body</p></blockquote>
            </li>
          </ol>
        </form>
        <ol class="pagination actions">
          <li>1</li><li><a href="?page=2">2</a></li><li><a href="?page=2">Next</a></li>
        </ol>
        </body></html>
    """.trimIndent()

    @Test
    fun parsesEntriesWithIdentityWorkAndState() {
        val page = parser.parseInboxPage(basicHtml, page = 1)
        assertEquals(3, page.items.size)

        val first = page.items.first()
        assertEquals(9001L, first.id)
        assertEquals("ReaderOne", first.commenterName)
        assertFalse(first.isGuest)
        assertEquals("reader1", first.commenterUsername)
        assertEquals("https://example.com/icons/1/standard.png", first.avatarUrl)
        assertEquals("Chapter 3 of My Great Fic", first.subjectTitle)
        assertEquals(123456L, first.workId)
        assertEquals("Loved this chapter so much!", first.excerpt)
        assertEquals("3 days ago", first.postedAgo)
        assertTrue(first.isUnread)
        assertFalse(first.isReplied)
        assertTrue(first.canReply)
        assertEquals(3, first.chapterPosition)
        assertEquals("Chapter 3", first.chapterIndicatorTitle)
        assertEquals("My Great Fic", first.workTitle)
    }

    @Test
    fun parsesGuestCommentAndRepliedState() {
        val page = parser.parseInboxPage(basicHtml, page = 1)
        val guest = page.items[1]
        assertEquals(9002L, guest.id)
        assertEquals("Driveby Guest", guest.commenterName)
        assertTrue(guest.isGuest)
        assertNull(guest.commenterUsername)
        assertNull(guest.avatarUrl)
        assertEquals(123456L, guest.workId)
        assertFalse(guest.isUnread)
        assertTrue(guest.isReplied)
        assertFalse(guest.canReply)
        assertNull(guest.chapterPosition)
        assertEquals("My Great Fic", guest.workTitle)
    }

    @Test
    fun tagCommentHasNoWorkButKeepsWebLink() {
        val page = parser.parseInboxPage(basicHtml, page = 1)
        val tag = page.items[2]
        assertNull(tag.workId)
        assertEquals("Some Tag", tag.subjectTitle)
        assertTrue(tag.subjectUrl?.contains("/tags/") == true)
    }

    @Test
    fun readsHeadingTotalsAndPagination() {
        val page = parser.parseInboxPage(basicHtml, page = 1)
        assertEquals(12, page.totalComments)
        assertEquals(3, page.unreadCount)
        assertEquals(1, page.currentPage)
        assertEquals(2, page.totalPages)
    }

    @Test
    fun basicPageWithoutCompleteBulkFormLeavesBulkFormNull() {
        // Partial form: POST + checkbox rows but missing submit actions → fail closed.
        val page = parser.parseInboxPage(basicHtml, page = 1)
        assertNull(page.bulkForm)
    }

    @Test
    fun parsesFixtureBulkFormAndDistinctInboxRowIds() {
        val html = fixture("ao3/inbox/ao3_inbox_manage.html")
        val page = parser.parseInboxPage(html, page = 1)
        val form = page.bulkForm
        assertNotNull(form)
        form!!
        assertTrue(form.actionUrl.contains("/users/tester/inbox"))
        assertEquals("post", form.htmlMethod)
        assertEquals("put", form.httpMethodOverride)
        assertEquals("csrf-inbox-123==", form.csrfToken)
        assertTrue(form.hiddenFields.any { it.name == "source" && it.value == "inbox" })
        assertEquals("inbox_comments[]", form.checkboxFieldName)
        assertEquals(
            AO3FormField("read", "Mark Read"),
            form.actionFields[AO3InboxBulkAction.MarkRead]
        )
        assertEquals(
            AO3FormField("unread", "Mark Unread"),
            form.actionFields[AO3InboxBulkAction.MarkUnread]
        )
        assertEquals(
            AO3FormField("delete", "Delete From Inbox"),
            form.actionFields[AO3InboxBulkAction.Delete]
        )
        assertEquals(listOf(9001L, 9002L, 9003L), page.items.map { it.id })
        assertEquals(
            listOf("501", "502", "503"),
            page.items.mapNotNull { it.bulkSelectionField?.value }
        )
    }

    @Test
    fun bulkFormParametersAreFailClosed() {
        val html = fixture("ao3/inbox/ao3_inbox_manage.html")
        val page = parser.parseInboxPage(html, page = 1)
        val form = requireNotNull(page.bulkForm)

        val two = page.items.take(2)
        val body = form.parameters(two, AO3InboxBulkAction.MarkRead)
        assertNotNull(body)
        assertEquals(
            listOf(
                "_method" to "put",
                "authenticity_token" to "csrf-inbox-123==",
                "source" to "inbox",
                "inbox_comments[]" to "501",
                "inbox_comments[]" to "502",
                "read" to "Mark Read"
            ),
            body
        )

        // Item without a checkbox must not produce a partial body.
        val guestNoCheckbox = page.items[1].copy(bulkSelectionField = null)
        assertNull(form.parameters(listOf(guestNoCheckbox), AO3InboxBulkAction.Delete))

        // Empty selection → null.
        assertNull(form.parameters(emptyList(), AO3InboxBulkAction.MarkUnread))

        // Checkbox field name mismatch → null.
        val wrongName = page.items.first().copy(
            bulkSelectionField = AO3FormField("other[]", "501")
        )
        assertNull(form.parameters(listOf(wrongName), AO3InboxBulkAction.MarkRead))
    }

    @Test
    fun incompleteBulkFormIsAbsent() {
        // Only two of three submit buttons → whole form null.
        val html = """
            <html><body class="logged-in">
            <h2 class="heading">My Inbox (1 comments, 1 unread)</h2>
            <form id="inbox-form" action="/users/tester/inbox" method="post">
              <input type="hidden" name="authenticity_token" value="tok">
              <input type="submit" name="read" value="Mark Read">
              <input type="submit" name="unread" value="Mark Unread">
              <ol class="comment index group">
                <li class="unread" id="feedback_comment_1">
                  <h4 class="heading byline">
                    <a href="/users/a">A</a> on
                    <a href="/works/9/comments/1">Work</a>
                    <span class="posted datetime">now</span>
                  </h4>
                  <blockquote class="userstuff"><p>x</p></blockquote>
                  <ul class="actions">
                    <li><input type="checkbox" name="inbox_comments[]" value="1"></li>
                  </ul>
                </li>
              </ol>
            </form>
            </body></html>
        """.trimIndent()
        val page = parser.parseInboxPage(html, page = 1)
        assertEquals(1, page.items.size)
        assertNull(page.bulkForm)
    }

    @Test
    fun parsesFixtureFiltersAndBuildsGetUrl() {
        val html = fixture("ao3/inbox/ao3_inbox_manage.html")
        val page = parser.parseInboxPage(html, page = 1)
        val filters = requireNotNull(page.filterForm)

        val read = requireNotNull(filters.fields.firstOrNull { it.name == "filters[read]" })
        val replied = requireNotNull(filters.fields.firstOrNull { it.name == "filters[replied_to]" })
        val date = requireNotNull(filters.fields.firstOrNull { it.name == "filters[date]" })

        assertEquals("Read", read.title)
        assertEquals(listOf("all", "false", "true"), read.options.map { it.value })
        assertEquals("false", read.selectedValue)
        assertEquals("Replied To", replied.title)
        assertEquals("all", replied.selectedValue)
        assertEquals("Sort by Date", date.title)
        assertEquals("desc", date.selectedValue)

        val url = requireNotNull(
            filters.url(
                values = mapOf(
                    read.name to "true",
                    replied.name to "false",
                    date.name to "asc"
                ),
                page = 2
            )
        )
        val httpUrl = url.toHttpUrl()
        assertEquals("en", httpUrl.queryParameter("locale"))
        assertEquals("true", httpUrl.queryParameter("filters[read]"))
        assertEquals("false", httpUrl.queryParameter("filters[replied_to]"))
        assertEquals("asc", httpUrl.queryParameter("filters[date]"))
        assertEquals("2", httpUrl.queryParameter("page"))

        val page1 = requireNotNull(filters.url(values = filters.selectedValues, page = 1))
        assertNull(page1.toHttpUrl().queryParameter("page"))
    }

    @Test
    fun recognizedEmptyInboxParsesAsEmpty() {
        val empty = """
            <html><body class="logged-in">
            <h2 class="heading">My Inbox (0 comments, 0 unread)</h2>
            <form class="narrow-hidden filters" id="inbox-filters" action="/users/tester/inbox" method="get">
              <input type="radio" name="filters[read]" value="all" checked="checked" id="r1">
              <label for="r1">Show all</label>
            </form>
            </body></html>
        """.trimIndent()
        val page = parser.parseInboxPage(empty, page = 1)
        assertTrue(page.items.isEmpty())
        assertEquals(0, page.totalComments)
        assertEquals(1, page.totalPages)
    }

    @Test(expected = AO3InboxParseException.MissingRequiredStructure::class)
    fun unrecognizedMarkupThrowsInsteadOfFabricatingEmpty() {
        val drifted = "<html><body><h1>Archive of Our Own</h1><p>maintenance</p></body></html>"
        parser.parseInboxPage(drifted, page = 1)
    }

    @Test
    fun buildsInboxUrl() {
        assertEquals(
            "https://archiveofourown.org/users/tester/inbox",
            AO3InboxParser.inboxUrl("tester", 1)
        )
        assertEquals(
            "https://archiveofourown.org/users/tester/inbox?page=3",
            AO3InboxParser.inboxUrl("tester", 3)
        )
        assertNull(AO3InboxParser.inboxUrl("   ", 1))
    }

    @Test
    fun defaultAo3IconIsFilteredFromAvatar() {
        val html = """
            <html><body class="logged-in">
            <h2 class="heading">My Inbox (1 comments, 0 unread)</h2>
            <ol>
              <li id="feedback_comment_7" class="read">
                <h4 class="heading byline">
                  <a href="/users/x">X</a> on
                  <a href="/works/1/comments/7">Work</a>
                  <span class="posted datetime">ago</span>
                </h4>
                <div class="icon">
                  <img src="/images/skins/iconsets/default/icon_user.png">
                </div>
                <blockquote class="userstuff"><p>hi</p></blockquote>
              </li>
            </ol>
            </body></html>
        """.trimIndent()
        val page = parser.parseInboxPage(html, page = 1)
        assertNull(page.items.single().avatarUrl)
    }

    private fun fixture(path: String): String {
        val stream = requireNotNull(javaClass.classLoader?.getResourceAsStream(path)) {
            "Missing test resource: $path"
        }
        return stream.bufferedReader().use { it.readText() }
    }
}
