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
    fun ratingLetter_abbreviatesForTheDenseTopRow() {
        assertEquals("G", ratingLetter("General Audiences"))
        assertEquals("T", ratingLetter("Teen And Up Audiences"))
        assertEquals("M", ratingLetter("Mature"))
        assertEquals("E", ratingLetter("Explicit"))
        assertEquals("NR", ratingLetter("Not Rated"))
        assertNull(ratingLetter(""))
        // The compact cover cards deliberately keep the spelled-out name.
        assertEquals("General", ratingDisplayName("General Audiences"))
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
    fun completionStatText_spellsOutAllThreeStates() {
        assertEquals("Complete", completionStatText(true))
        assertEquals("In Progress", completionStatText(false))
        assertEquals("Unknown", completionStatText(null))
    }

    @Test
    fun completionShortText_onlyAbbreviatesInProgress() {
        assertEquals("Complete", completionShortText(true))
        assertEquals("WIP", completionShortText(false))
        assertEquals("Unknown", completionShortText(null))
    }

    @Test
    fun realWarnings_filtersOutSentinelValues() {
        assertEquals(emptyList<String>(), realWarnings(listOf("No Archive Warnings Apply")))
        assertEquals(
            emptyList<String>(),
            realWarnings(listOf("Creator Chose Not To Use Archive Warnings"))
        )
        assertEquals(
            listOf("Graphic Depictions Of Violence"),
            realWarnings(listOf("Graphic Depictions Of Violence", "No Archive Warnings Apply"))
        )
    }

    @Test
    fun warningStatus_distinguishesUndisclosedFromNoneFromPresent() {
        assertEquals(WorkWarningStatus.None, WorkWarningStatus.from(emptyList()))
        assertEquals(
            WorkWarningStatus.None,
            WorkWarningStatus.from(listOf("No Archive Warnings Apply"))
        )
        assertEquals(
            WorkWarningStatus.Undisclosed,
            WorkWarningStatus.from(listOf("Creator Chose Not To Use Archive Warnings"))
        )
        assertEquals(
            WorkWarningStatus.Present(2),
            WorkWarningStatus.from(listOf("Graphic Depictions Of Violence", "Major Character Death"))
        )
    }

    @Test
    fun warningStatus_undisclosedIsNotTheSameAsNone() {
        // The bug this guards against: collapsing "creator chose not to warn"
        // (content could include anything) into the same bucket as "no warnings
        // apply" (confirmed clean) would misrepresent the former.
        assertEquals("Not Disclosed", WorkWarningStatus.Undisclosed.text)
        assertEquals("No Warnings", WorkWarningStatus.None.text)
        assertEquals("1 Warning Applies", WorkWarningStatus.Present(1).text)
        assertEquals("3 Warnings Apply", WorkWarningStatus.Present(3).text)
    }

    @Test
    fun topRowStats_alwaysShowsFourBadges() {
        val stats = topRowStats(
            rating = "General Audiences",
            categories = listOf("M/M"),
            warnings = listOf("No Archive Warnings Apply"),
            isComplete = true
        )
        assertEquals(listOf("G", "M/M", "No Warnings", "Complete"), stats.map { it.text })
    }

    @Test
    fun topRowStats_fillsEmptySlotsRatherThanDroppingThem() {
        // An unrecognized category renders nothing, so checking the raw list for
        // emptiness isn't enough — it has to fall back to the N/A badge.
        val stats = topRowStats(
            rating = "",
            categories = listOf("Not A Real Category"),
            warnings = listOf("Creator Chose Not To Use Archive Warnings"),
            isComplete = false
        )
        assertEquals(listOf("N/A", "Not Disclosed", "WIP"), stats.map { it.text })
    }

    @Test
    fun listRowStats_usesAO3sOwnStatOrder() {
        val stats = listRowStats(
            language = "English",
            wordCount = 1_735,
            chapters = "1/?",
            comments = 19,
            kudos = 450,
            bookmarks = 17,
            hits = 24_180,
            datePublished = "2024-01-15"
        )
        assertEquals(
            listOf("English", "1,735", "1/?", "19", "450", "17", "24,180", "01/15/2024"),
            stats.map { it.text }
        )
    }

    @Test
    fun listRowStats_showsZerosRatherThanDroppingTheStat() {
        // AO3 omits a `dd` entirely when its count is zero, so null means zero —
        // dropping the badge made a card's stat row change shape for no visible
        // reason. Language and chapters are the two that can be genuinely
        // absent rather than zero, so they get an em dash.
        val stats = listRowStats(
            language = "",
            wordCount = null,
            chapters = "",
            comments = null,
            kudos = null,
            bookmarks = null,
            hits = null
        )
        assertEquals(listOf("—", "0", "—", "0", "0", "0", "0"), stats.map { it.text })
    }

    @Test
    fun listRowStats_omitsOnlyTheDateWhenUnknown() {
        val stats = listRowStats(
            language = "English",
            wordCount = 10,
            chapters = "1/1",
            comments = 0,
            kudos = 0,
            bookmarks = 0,
            hits = 0,
            datePublished = null
        )
        assertEquals(7, stats.size)
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
