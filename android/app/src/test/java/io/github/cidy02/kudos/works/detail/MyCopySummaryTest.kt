package io.github.cidy02.kudos.works.detail

import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `WorkDetailComponents.myCopySummary`. */
class MyCopySummaryTest {
    // iOS WorkOriginTests known-host/unknown/no-source assertions, using the My Copy sentence.
    @Test fun knownImportedOriginsRemainVisible() {
        fun sentence(source: String) = myCopyOriginSentence(io.github.cidy02.kudos.core.model.SavedWork(
            title = "Imported", author = "Writer", sourceUrl = source,
            dateAdded = java.time.Instant.ofEpochMilli(1_700_000_000_000)))
        assertEquals("From Archive of Our Own.", sentence("https://archiveofourown.org/works/1"))
        assertEquals("Imported work, originally posted on FanFiction.net.", sentence("https://m.fanfiction.net/s/123/1/"))
        assertEquals("Imported work, originally posted on Wattpad.", sentence("https://www.wattpad.com/story/123"))
        assertEquals("Imported work, originally posted on Other site.", sentence("https://example.com/fanfiction.net"))
        assertEquals("This imported work doesn't include the website where it was first posted.", sentence(""))
    }

    @Test
    fun theLineCountsWhatIsKeptInIosOrder() {
        assertEquals("Downloaded · 1 queue · 1 collection", myCopySummary(true, 1, 1, 0))
        assertEquals("2 queues · 3 collections · 1 tag", myCopySummary(false, 2, 3, 1))
        assertEquals("You haven't saved anything on this device yet", myCopySummary(false, 0, 0, 0))
    }
}
