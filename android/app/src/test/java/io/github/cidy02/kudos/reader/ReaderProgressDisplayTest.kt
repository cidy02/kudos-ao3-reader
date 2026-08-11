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
        assertEquals(42, ReaderProgressDisplay.percent(progress, spineCount = 10))
        assertEquals("Ch. 1/10 · 42%", ReaderProgressDisplay.label(progress, sections))
    }

    @Test
    fun estimatesFromSpineWhenTotalMissing() {
        // spine 1 of 4 + half way through → (1.5 / 4) = 37%
        val progress = ReaderProgress(spineIndex = 1, scrollFraction = 0.5)
        assertEquals(37, ReaderProgressDisplay.percent(progress, spineCount = 4))
    }

    @Test
    fun nullProgressYieldsNullPercentAndEmptyLabel() {
        assertNull(ReaderProgressDisplay.percent(null, spineCount = 5))
        assertEquals("", ReaderProgressDisplay.label(null, plainChapters(5)))
    }

    @Test
    fun clampsTotalProgression() {
        val progress = ReaderProgress(
            spineIndex = 0,
            scrollFraction = 0.0,
            totalProgression = 1.5
        )
        assertEquals(100, ReaderProgressDisplay.percent(progress, spineCount = 3))
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
            "Preface · 10%",
            ReaderProgressDisplay.label(
                ReaderProgress(0, 0.0, totalProgression = 0.10),
                sections
            )
        )
        assertEquals(
            "Summary · 20%",
            ReaderProgressDisplay.label(
                ReaderProgress(1, 0.0, totalProgression = 0.20),
                sections
            )
        )
        assertEquals(
            "Ch. 1/2 · 50%",
            ReaderProgressDisplay.label(
                ReaderProgress(2, 0.0, totalProgression = 0.50),
                sections
            )
        )
        assertEquals(
            "Ch. 2/2 · 80%",
            ReaderProgressDisplay.label(
                ReaderProgress(3, 0.0, totalProgression = 0.80),
                sections
            )
        )
        assertEquals(
            "Afterword · 95%",
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
            "5%",
            ReaderProgressDisplay.label(
                ReaderProgress(0, 0.0, totalProgression = 0.05),
                sections
            )
        )
    }
}
