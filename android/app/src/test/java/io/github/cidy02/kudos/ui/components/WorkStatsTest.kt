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
    fun listRowStats_honoursShowsZeroStats() {
        // When showsZeroStats is false, zeroes and unknowns are omitted (iOS WorkStatLabel)
        val hidden = listRowStats(
            language = null,
            wordCount = 0,
            chapters = "",
            comments = 0,
            kudos = 0,
            bookmarks = 0,
            hits = 0,
            showsZeroStats = false
        )
        assertEquals(0, hidden.size)

        // When showsZeroStats is true, zeroes and unknowns are included
        val shown = listRowStats(
            language = null,
            wordCount = 0,
            chapters = "",
            comments = 0,
            kudos = 0,
            bookmarks = 0,
            hits = 0,
            showsZeroStats = true
        )
        assertEquals(7, shown.size)
        // Language
        assertEquals("—", shown[0].text)
        // Words
        assertEquals("0", shown[1].text)
        // Chapters
        assertEquals("—", shown[2].text)
        // Comments
        assertEquals("0", shown[3].text)

        // A known language and a one-chapter work show, as on iOS ("English", "1/1").
        val known = listRowStats(
            language = "English", wordCount = 100, chapters = "1/1",
            comments = null, kudos = null, bookmarks = null, hits = null, showsZeroStats = false
        )
        assertEquals(listOf("English", "100", "1/1"), known.map { it.text })
    }
}
