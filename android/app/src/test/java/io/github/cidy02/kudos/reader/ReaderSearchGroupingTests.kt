package io.github.cidy02.kudos.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Names and expectations ported verbatim from iOS ReaderSearchGroupingTests.swift. */
class ReaderSearchGroupingTests {
    private fun sections() = listOf(
        ReaderSection("ch1.xhtml", "Chapter 1", ReaderSectionKind.CHAPTER, 0, 1),
        ReaderSection("ch2.xhtml", "Chapter 2", ReaderSectionKind.CHAPTER, 1, 2),
        ReaderSection("ch3.xhtml", "Chapter 3", ReaderSectionKind.CHAPTER, 2, 3)
    )

    @Test
    fun currentChapterIsPinnedFirstRegardlessOfIndex() {
        val groups = ReaderSearchGrouping.grouped(
            listOf("ch1.xhtml", "ch2.xhtml", "ch3.xhtml"), { it }, sections(), 2
        )
        assertEquals(listOf("This Chapter (Ch. 3)", "Chapter 1", "Chapter 2"), groups.map { it.title })
    }

    @Test
    fun currentChapterSuffixNamesAO3FrontAndBackMatterHonestly() {
        val sections = listOf(
            ReaderSection("pre.xhtml", "Preface", ReaderSectionKind.PREFACE, 0, null),
            ReaderSection("sum.xhtml", "Summary", ReaderSectionKind.SUMMARY, 1, null),
            ReaderSection("end.xhtml", "Afterword", ReaderSectionKind.AFTERWORD, 2, null),
            ReaderSection("misc.xhtml", "Section 4", ReaderSectionKind.OTHER, 3, null)
        )
        val suffixes = listOf(" (Preface)", " (Summary)", " (Afterword)", "")
        sections.forEachIndexed { index, section ->
            val groups = ReaderSearchGrouping.grouped(listOf(section.href), { it }, sections, index)
            assertEquals("This Chapter" + suffixes[index], groups.first().title)
        }
    }

    @Test
    fun remainingChaptersAreAscendingWhenNoCurrentChapterMatches() {
        val groups = ReaderSearchGrouping.grouped(
            listOf("ch1.xhtml", "ch2.xhtml", "ch3.xhtml"), { it }, sections(), null
        )
        assertEquals(listOf("Chapter 1", "Chapter 2", "Chapter 3"), groups.map { it.title })
        assertEquals(
            listOf("Chapter 1", "Chapter 2", "Chapter 3"),
            ReaderSearchGrouping.grouped(listOf("ch3.xhtml", "ch1.xhtml", "ch2.xhtml"), { it }, sections(), 9)
                .map { it.title }
        )
    }

    @Test
    fun multipleHitsInOneChapterStayInOneGroup() {
        val groups = ReaderSearchGrouping.grouped(
            listOf("ch2.xhtml", "ch2.xhtml", "ch1.xhtml"), { it }, sections(), null
        )
        assertEquals(2, groups.size)
        assertEquals(2, groups.first { it.title == "Chapter 2" }.results.size)
    }

    @Test
    fun unmatchedHrefStillSurfacesRatherThanBeingDropped() {
        val groups = ReaderSearchGrouping.grouped(listOf("unknown.xhtml"), { it }, sections(), null)
        assertEquals(1, groups.size)
        assertEquals(listOf("unknown.xhtml"), groups.first().results)
        assertEquals(-1, groups.first().spineIndex)
        assertEquals("This Work", groups.first().title)
    }

    @Test
    fun emptyResultsProduceNoGroups() {
        assertTrue(ReaderSearchGrouping.grouped(emptyList<String>(), { it }, sections(), 0).isEmpty())
    }

    @Test
    fun hrefKeysNormalizePathsFragmentsAndCaseAndKeepHitOrder() {
        val hits = listOf("Text/CH2.XHTML#first", "../ch1.xhtml", "ch2.xhtml#second", "lost.xhtml")
        val groups = ReaderSearchGrouping.grouped(hits, ReaderSectionBuilder::hrefKey, sections(), 1)
        assertEquals(listOf(1, -1, 0), groups.map { it.spineIndex })
        assertEquals(listOf(hits[0], hits[2]), groups.first().results)
    }

    @Test
    fun duplicateSectionHrefKeysUseLastSectionAndChapterWithoutNumberHasNoSuffix() {
        val sections = sections() + ReaderSection("Text/CH2.XHTML#heading", "Replacement", ReaderSectionKind.CHAPTER, 4, null)
        val group = ReaderSearchGrouping.grouped(listOf("ch2.xhtml"), { it }, sections, 4).single()
        assertEquals(4, group.spineIndex)
        assertEquals("This Chapter", group.title)
    }
}
