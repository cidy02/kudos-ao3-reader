package io.github.cidy02.kudos.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReaderProgressDisplayTest {

    /** Plain numbered spine — every item is a real story chapter (non-AO3 fallback). */
    private fun plainChapters(count: Int): List<ReaderSection> {
        return (0 until count).map { i ->
            ReaderSection(
                href = "ch${i + 1}.xhtml",
                title = "Chapter ${i + 1}",
                kind = ReaderSectionKind.CHAPTER,
                spineIndex = i,
                storyChapterIndex = i + 1
            )
        }
    }

    @Test
    fun prefersTotalProgressionForPercent() {
        val progress = ReaderProgress(
            spineIndex = 0,
            scrollFraction = 0.1,
            totalProgression = 0.42
        )
        val sections = plainChapters(10)
        assertEquals(42, ReaderProgressDisplay.percent(progress))
        assertEquals("Chapter 1 of 10 · 42% of work", ReaderProgressDisplay.label(progress, sections))
    }

    @Test
    fun missingNavigatorTotalUsesIosZeroRatherThanInventingABookPercent() {
        // iOS defaults the missing total progression to zero, even mid-resource.
        val progress = ReaderProgress(spineIndex = 1, scrollFraction = 0.5)
        assertEquals(0, ReaderProgressDisplay.percent(progress))
    }

    @Test
    fun nullProgressYieldsNullPercentAndEmptyLabel() {
        assertNull(ReaderProgressDisplay.percent(null))
        assertEquals("", ReaderProgressDisplay.label(null, plainChapters(5)))
    }

    @Test
    fun clampsTotalProgression() {
        val progress = ReaderProgress(
            spineIndex = 0,
            scrollFraction = 0.0,
            totalProgression = 1.5
        )
        assertEquals(100, ReaderProgressDisplay.percent(progress))
    }

    @Test
    fun prefaceAndAfterwordAreNotNumberedChapters() {
        val sections = listOf(
            ReaderSection("p.xhtml", "Preface", ReaderSectionKind.PREFACE, 0, null),
            ReaderSection("s.xhtml", "Summary", ReaderSectionKind.SUMMARY, 1, null),
            ReaderSection("c1.xhtml", "Chapter 1", ReaderSectionKind.CHAPTER, 2, 1),
            ReaderSection("c2.xhtml", "Chapter 2", ReaderSectionKind.CHAPTER, 3, 2),
            ReaderSection("a.xhtml", "Afterword", ReaderSectionKind.AFTERWORD, 4, null)
        )
        assertEquals(
            "Preface · 10% of work",
            ReaderProgressDisplay.label(
                ReaderProgress(0, 0.0, totalProgression = 0.10),
                sections
            )
        )
        assertEquals(
            "Summary · 20% of work",
            ReaderProgressDisplay.label(
                ReaderProgress(1, 0.0, totalProgression = 0.20),
                sections
            )
        )
        assertEquals(
            "Chapter 1 of 2 · 50% of work",
            ReaderProgressDisplay.label(
                ReaderProgress(2, 0.0, totalProgression = 0.50),
                sections
            )
        )
        assertEquals(
            "Chapter 2 of 2 · 80% of work",
            ReaderProgressDisplay.label(
                ReaderProgress(3, 0.0, totalProgression = 0.80),
                sections
            )
        )
        assertEquals(
            "Afterword · 95% of work",
            ReaderProgressDisplay.label(
                ReaderProgress(4, 0.0, totalProgression = 0.95),
                sections
            )
        )
    }

    @Test
    fun otherKindShowsPercentOnly() {
        val sections = listOf(
            ReaderSection("cover.xhtml", "Section 1", ReaderSectionKind.OTHER, 0, null)
        )
        assertEquals(
            "5% of work",
            ReaderProgressDisplay.label(
                ReaderProgress(0, 0.0, totalProgression = 0.05),
                sections
            )
        )
    }
    @Test
    fun thumbAndPreviewUseOnlyChapterPages() {
        assertEquals(0.5f, ReaderProgressDisplay.sliderValue(6, 11), 0f)
        assertEquals(6, ReaderProgressDisplay.scrubPage(0.5f, 11))
        assertEquals(1f, ReaderProgressDisplay.sliderValue(1, 1), 0f)
        assertEquals(11, ReaderProgressDisplay.scrubPage(1f, 11))
        assertEquals("Page 6 of 11", ReaderProgressDisplay.pageLabel(6, 11))
        assertEquals("Measuring pages", ReaderProgressDisplay.pageLabel(0, 0))
    }

    @Test
    fun chapterMinutesScaleVisualPagesOntoPositionsAndWorkDurationUsesIosWords() {
        assertEquals(5, ReaderProgressDisplay.chapterRemainingPositions(51, 101, 10))
        assertEquals(5, ReaderProgressDisplay.minutesForPositions(5))
        assertEquals(0, ReaderProgressDisplay.chapterRemainingPositions(101, 101, 10))
        assertEquals("0 min", ReaderProgressDisplay.durationLabel(0))
        assertEquals("1 hr", ReaderProgressDisplay.durationLabel(60))
        assertEquals("1 hr 5 min", ReaderProgressDisplay.durationLabel(65))
        assertEquals("Chapter 2 of 10 · 34% of work",
            ReaderProgressDisplay.label(ReaderProgress(1, 0.2, totalProgression = 0.34), plainChapters(2), "2/10"))
        assertEquals("Chapter 2 of 2 · 34% of work",
            ReaderProgressDisplay.label(ReaderProgress(1, 0.2, totalProgression = 0.34), plainChapters(2), "2/1"))
    }

}
