package io.github.cidy02.kudos.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderLinkHandlerTest {
    private val handler = ReaderLinkHandler()

    @Test
    fun ao3WorkUrlBecomesWorkDetail() {
        assertEquals(
            ReaderLinkDestination.WorkDetail(12345L),
            handler.classify("https://archiveofourown.org/works/12345")
        )
        assertEquals(
            ReaderLinkDestination.WorkDetail(678L),
            handler.classify("https://archiveofourown.org/works/678/chapters/99")
        )
    }

    @Test
    fun ao3TagUrlBecomesTagSearchDecoded() {
        assertEquals(
            ReaderLinkDestination.TagSearch("Fluff"),
            handler.classify("https://archiveofourown.org/tags/Fluff/works")
        )
        assertEquals(
            ReaderLinkDestination.TagSearch("Alternate Universe"),
            handler.classify("https://archiveofourown.org/tags/Alternate%20Universe/works")
        )
    }

    @Test
    fun ao3TagNamesAreReadAsAo3WritesThem() {
        assertEquals(
            ReaderLinkDestination.TagSearch("Harry Potter/Ginny Weasley & Friends"),
            handler.classify("https://archiveofourown.org/tags/Harry%20Potter*s*Ginny%20Weasley%20*a*%20Friends/works")
        )
        assertEquals(ReaderLinkDestination.TagSearch("C++"), handler.classify("https://archiveofourown.org/tags/C++/works"))
    }

    @Test
    fun ao3UserAndPseudLinksOpenTheAuthor() {
        assertEquals(ReaderLinkDestination.Author("avery"), handler.classify("https://archiveofourown.org/users/avery"))
        assertEquals(
            ReaderLinkDestination.Author("avery"),
            handler.classify("https://archiveofourown.org/users/avery/pseuds/Avery%20Writes/works")
        )
    }

    @Test
    fun externalUrlBecomesExternal() {
        val result = handler.classify("https://example.com/page")
        assertTrue(result is ReaderLinkDestination.External)
        assertEquals("https://example.com/page", (result as ReaderLinkDestination.External).url)
    }

    @Test
    fun externalUrlContainingAo3HostIsStillExternal() {
        val url = "https://example.com/redirect?next=https://archiveofourown.org/works/12345"
        val result = handler.classify(url)
        assertTrue(result is ReaderLinkDestination.External)
        assertEquals(url, (result as ReaderLinkDestination.External).url)
    }

    @Test
    fun relativeOrEmptyLinksAreUnhandled() {
        assertEquals(ReaderLinkDestination.Unhandled, handler.classify("chapter2.xhtml"))
        assertEquals(ReaderLinkDestination.Unhandled, handler.classify("#footnote-1"))
        assertEquals(ReaderLinkDestination.Unhandled, handler.classify("   "))
    }
}
