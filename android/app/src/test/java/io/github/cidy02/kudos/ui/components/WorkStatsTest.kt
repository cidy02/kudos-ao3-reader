package io.github.cidy02.kudos.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WorkStatsTest {
    @Test
    fun ratingDisplayName_shortensKnownAO3Ratings() {
        assertEquals("General", ratingDisplayName("General Audiences"))
        assertEquals("Teen", ratingDisplayName("Teen And Up Audiences"))
        assertEquals("Mature", ratingDisplayName("Mature"))
        assertEquals("Explicit", ratingDisplayName("Explicit"))
        assertEquals("Not Rated", ratingDisplayName("Not Rated"))
        assertNull(ratingDisplayName(""))
        assertEquals("Custom Rating", ratingDisplayName("Custom Rating"))
    }

    @Test
    fun chapterStatText_spellsOutNoun() {
        assertEquals("1 chapter", chapterStatText("1"))
        assertEquals("3/5 chapters", chapterStatText("3/5"))
        assertEquals("", chapterStatText("  "))
    }

    @Test
    fun wordStatText_compactAndSpelledOut() {
        assertEquals("", wordStatText(0))
        assertEquals("1 word", wordStatText(1))
        assertEquals("999 words", wordStatText(999))
        assertEquals("1.5K words", wordStatText(1_500))
        assertEquals("12K words", wordStatText(12_000))
    }

    @Test
    fun completionStatText_matchesHigReviewWording() {
        assertEquals("Complete", completionStatText(true))
        assertEquals("In Progress", completionStatText(false))
        assertNull(completionStatText(null))
    }

    @Test
    fun listRowStats_showsBothPublishedAndUpdatedWhenTheyDiffer() {
        val stats = listRowStats(
            rating = "", wordCount = null, chapters = "", kudos = null,
            datePublished = "2024-01-15", dateUpdated = "2024-03-02"
        )
        assertEquals(listOf("01/15/2024", "03/02/2024"), stats.map { it.text })
    }

    @Test
    fun listRowStats_omitsUpdatedWhenNeverUpdated() {
        val stats = listRowStats(
            rating = "", wordCount = null, chapters = "", kudos = null,
            datePublished = "2024-01-15", dateUpdated = ""
        )
        assertEquals("01/15/2024", stats.single().text)
    }

    @Test
    fun listRowStats_omitsDateStatsWhenNeitherIsKnown() {
        val stats = listRowStats(rating = "", wordCount = null, chapters = "", kudos = null)
        assertEquals(emptyList<WorkStatItem>(), stats)
    }

    @Test
    fun displayDate_parsesTheWorkDetailPageISOFormat() {
        assertEquals("11/01/2025", displayDate("2025-11-01"))
    }

    @Test
    fun displayDate_parsesTheSearchBlurbFormat() {
        assertEquals("11/01/2025", displayDate("01 Nov 2025"))
    }

    @Test
    fun displayDate_fallsBackToTheRawStringWhenUnrecognized() {
        assertEquals("not a date", displayDate("not a date"))
    }
}
