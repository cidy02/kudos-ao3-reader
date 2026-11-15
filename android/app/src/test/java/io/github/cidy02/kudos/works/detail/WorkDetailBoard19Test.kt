package io.github.cidy02.kudos.works.detail

import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkDetailBoard19Test {
    @Test
    fun tagsDigestCountsThreeWorkGroups() {
        assertEquals(
            "1 relationship · 3 characters · 4 more",
            WorkDetailDisclosure.tagsDigest(relationships = 1, characters = 3, additional = 4)
        )
        assertEquals(
            "2 relationships · 1 character",
            WorkDetailDisclosure.tagsDigest(relationships = 2, characters = 1, additional = 0)
        )
        assertEquals(
            "No AO3 tags",
            WorkDetailDisclosure.tagsDigest(relationships = 0, characters = 0, additional = 0)
        )
    }

    @Test
    fun tagLinksRoundTripAnyTagText() {
        val samples = listOf(
            "Tenth Doctor & Donna Noble",
            "Ben Solo/Rey",
            "Doctor Who (2005)",
            "a?b#c%d+e",
            "Café"
        )
        samples.forEach { tag ->
            val url = WorkDetailTagLink.url(tag)
            assertEquals(tag, WorkDetailTagLink.tagFromUrl(url))
        }
        assertNull(WorkDetailTagLink.tagFromUrl("https://archiveofourown.org"))
        assertEquals(
            "Tenth Doctor, Donna Noble",
            WorkDetailTagLink.joinedText(listOf("Tenth Doctor", "Donna Noble"))
        )
    }

    @Test
    fun seriesDigestClaimsNoTotalOrWordCount() {
        assertEquals(
            "The Coast Road · part 2",
            WorkDetailDisclosure.seriesDigest(title = "The Coast Road", position = 2)
        )
        assertEquals(
            "The Coast Road",
            WorkDetailDisclosure.seriesDigest(title = "The Coast Road", position = 0)
        )
    }

    private fun sampleCells(
        words: Int? = 84_210,
        chapters: String = "12/20",
        kudos: Int? = 3_104,
        kudosGiven: Boolean = false,
        hits: Int? = 41_200,
        comments: Int? = 286,
        bookmarks: Int? = 512,
        published: String = "2024-03-03",
        updated: String = "2024-10-21",
        language: String = "English",
        now: Instant = Instant.ofEpochSecond(1_730_000_000L)
    ) = WorkDetailStats.cells(
        words = words,
        chapters = chapters,
        kudos = kudos,
        kudosGiven = kudosGiven,
        hits = hits,
        comments = comments,
        bookmarks = bookmarks,
        published = published,
        updated = updated,
        language = language,
        now = now
    )

    @Test
    fun statsCardHasNineCellsInBoardOrder() {
        assertEquals(
            listOf("Words", "Chapters", "Kudos", "Hits", "Comments", "Bookmarks", "Published", "Updated", "Language"),
            sampleCells().map { it.label }
        )
    }

    @Test
    fun statsCardFormatsFiguresAndAccessibilityText() {
        val cells = sampleCells()
        assertEquals("84,210", cells[0].value)
        assertEquals("12/20", cells[1].value)
        assertEquals("3,104", cells[2].value)
        assertEquals("41K", cells[3].value)
        assertEquals("286", cells[4].value)
        assertEquals("512", cells[5].value)
        assertEquals("Mar 3", cells[6].value)
        assertEquals("Oct 21", cells[7].value)
        assertEquals("English", cells[8].value)
        assertEquals("84,210 words", cells[0].accessibilityText)
    }

    @Test
    fun statsCardKeepsAllNineCellsWhenUnknown() {
        val cells = sampleCells(
            words = null,
            chapters = " ",
            kudos = null,
            hits = null,
            comments = null,
            bookmarks = null,
            published = "",
            updated = "",
            language = ""
        )
        assertEquals(9, cells.size)
        assertTrue(cells.all { it.value == WorkDetailStats.emptyFigure })
        assertTrue(cells.none { it.showsGivenHeart })
    }

    @Test
    fun kudosHeartShowsWhenGivenEvenWithoutCount() {
        val given = sampleCells(kudosGiven = true)
        assertTrue(given[2].showsGivenHeart)
        assertTrue(given[2].accessibilityText.endsWith("given by you"))
        assertEquals(1, given.count { it.showsGivenHeart })
        assertFalse(sampleCells(kudosGiven = false)[2].showsGivenHeart)

        val unknownCount = sampleCells(kudos = null, kudosGiven = true)[2]
        assertTrue(unknownCount.showsGivenHeart)
        assertEquals(WorkDetailStats.emptyFigure, unknownCount.value)
    }

    @Test
    fun statsCardShortDateOmitsCurrentYearAndAddsPriorYears() {
        val now = Instant.ofEpochSecond(1_730_000_000L) // Oct 2024 UTC
        assertEquals("Mar 3", WorkDetailStats.shortDate("2024-03-03", now))
        assertEquals("Oct 21, 2023", WorkDetailStats.shortDate("21 Oct 2023", now))
        assertEquals("garbled", WorkDetailStats.shortDate("garbled", now))
    }

    @Test
    fun myCopyCellsOmitProgressAndKeepDownloadedFileTagsCollectionsQueues() {
        val date = Instant.ofEpochSecond(1_729_468_800L)
        val rows = WorkDetailPresentation.myCopyRows(
            progress = 0.58,
            chapterNumber = 7,
            downloadedAt = date,
            tags = listOf("coast", "reread"),
            collections = listOf("Comfort Reads"),
            queues = listOf("Summer Reading"),
            hasFile = true,
            fileSize = "1.2 MB",
            zoneId = ZoneOffset.UTC,
            locale = Locale.US
        )
        assertEquals(
            listOf("Progress", "Downloaded", "Your Tags", "Collections", "Queues", "File"),
            rows.map { it.label }
        )
        assertEquals("Ch 7 · 58%", rows[0].value)

        val cells = WorkDetailPresentation.myCopyCells(rows)
        assertEquals(
            listOf(
                WorkDetailPresentation.MyCopyKind.Downloaded,
                WorkDetailPresentation.MyCopyKind.File,
                WorkDetailPresentation.MyCopyKind.Tags,
                WorkDetailPresentation.MyCopyKind.Collections,
                WorkDetailPresentation.MyCopyKind.Queues
            ),
            cells.map { it.kind }
        )
        assertEquals(
            listOf(
                WorkDetailPresentation.MyCopyActionKind.Edit,
                null,
                WorkDetailPresentation.MyCopyActionKind.Add,
                WorkDetailPresentation.MyCopyActionKind.Add,
                WorkDetailPresentation.MyCopyActionKind.Add
            ),
            cells.map { it.action }
        )
        assertEquals("EPUB · 1.2 MB", cells[1].value)
        assertEquals("coast, reread", cells[2].value)
        assertEquals("Comfort Reads", cells[3].value)
        assertEquals("Summer Reading", cells[4].value)
    }
}
