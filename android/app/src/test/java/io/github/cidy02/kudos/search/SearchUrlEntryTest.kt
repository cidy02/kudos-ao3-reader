package io.github.cidy02.kudos.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SearchUrlEntryTest {
    @Test
    fun explicitUrlsOpenAndQueriesStayQueries() {
        assertEquals(
            "https://archiveofourown.org/works/1",
            SearchUrlEntry.normalize("https://archiveofourown.org/works/1")
        )
        assertEquals(
            "http://example.com/a",
            SearchUrlEntry.normalize("  http://example.com/a  ")
        )
        assertEquals(
            "https://www.archiveofourown.org/media",
            SearchUrlEntry.normalize("www.archiveofourown.org/media")
        )
        assertEquals(
            "https://archiveofourown.org/tags/Doctor%20Who/works",
            SearchUrlEntry.normalize("archiveofourown.org/tags/Doctor%20Who/works")
        )
        assertEquals(
            "https://download.archiveofourown.org/downloads/1/work.epub",
            SearchUrlEntry.normalize("download.archiveofourown.org/downloads/1/work.epub")
        )
        assertNull(SearchUrlEntry.normalize("dr. who"))
        assertNull(SearchUrlEntry.normalize("archiveofourown.org.evil.com/works/1"))
        assertNull(SearchUrlEntry.normalize("notarchiveofourown.org/works/1"))
        assertNull(SearchUrlEntry.normalize("   "))
    }
}
