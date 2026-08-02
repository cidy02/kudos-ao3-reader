package io.github.cidy02.kudos.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderSectionBuilderTest {

    private fun raw(title: String, spineIndex: Int) =
        ReaderSectionBuilder.RawTOCEntry(title, spineIndex)

    @Test
    fun classifiesPrefaceSummaryChapterAfterword() {
        val spine = listOf("p.xhtml", "s.xhtml", "c1.xhtml", "c2.xhtml", "a.xhtml")
        val toc = listOf(
            raw("Preface", 0),
            raw("Summary", 1),
            raw("Chapter 1", 2),
            raw("Chapter 2", 3),
            raw("Afterword", 4)
        )
        val sections = ReaderSectionBuilder.build(toc, spine)

        assertEquals(5, sections.size)
        assertEquals(ReaderSectionKind.PREFACE, sections[0].kind)
        assertEquals(ReaderSectionKind.SUMMARY, sections[1].kind)
        assertEquals(ReaderSectionKind.CHAPTER, sections[2].kind)
        assertEquals(1, sections[2].storyChapterIndex)
        assertEquals(ReaderSectionKind.CHAPTER, sections[3].kind)
        assertEquals(2, sections[3].storyChapterIndex)
        assertEquals(ReaderSectionKind.AFTERWORD, sections[4].kind)
        assertNull(sections[0].storyChapterIndex)
        assertNull(sections[4].storyChapterIndex)
        assertEquals(2, sections.storyChapterCount)
    }

    @Test
    fun synthesizesSummaryGapExactlyOnceAfterPreface() {
        // AO3: TOC has Preface + Chapter 1 + Afterword; Summary sits in the
        // untitled spine gap between Preface and Chapter 1.
        val spine = listOf("preface.xhtml", "summary.xhtml", "ch1.xhtml", "after.xhtml")
        val toc = listOf(
            raw("Preface", 0),
            raw("Chapter 1", 2),
            raw("Afterword", 3)
        )
        val sections = ReaderSectionBuilder.build(toc, spine)

        assertEquals(ReaderSectionKind.PREFACE, sections[0].kind)
        assertEquals(ReaderSectionKind.SUMMARY, sections[1].kind)
        assertEquals("Summary", sections[1].title)
        assertEquals(ReaderSectionKind.CHAPTER, sections[2].kind)
        assertEquals(1, sections[2].storyChapterIndex)
        assertEquals(ReaderSectionKind.AFTERWORD, sections[3].kind)
        assertEquals(1, sections.storyChapterCount)
    }

    @Test
    fun doesNotSynthesizeSummaryWhenAlreadyInToc() {
        val spine = listOf("p.xhtml", "s.xhtml", "c1.xhtml")
        val toc = listOf(
            raw("Preface", 0),
            raw("Summary", 1),
            raw("Chapter 1", 2)
        )
        val sections = ReaderSectionBuilder.build(toc, spine)
        assertEquals(ReaderSectionKind.SUMMARY, sections[1].kind)
        // No extra synthetic summary — still exactly three sections.
        assertEquals(3, sections.size)
        assertEquals(1, sections.count { it.kind == ReaderSectionKind.SUMMARY })
    }

    @Test
    fun doesNotSynthesizeSecondGapAsSummary() {
        // Preface, untitled gap (Summary), another untitled gap, Chapter 1.
        val spine = listOf("p.xhtml", "s.xhtml", "x.xhtml", "c1.xhtml")
        val toc = listOf(
            raw("Preface", 0),
            raw("Chapter 1", 3)
        )
        val sections = ReaderSectionBuilder.build(toc, spine)
        assertEquals(ReaderSectionKind.SUMMARY, sections[1].kind)
        assertEquals(ReaderSectionKind.OTHER, sections[2].kind)
        assertEquals(ReaderSectionKind.CHAPTER, sections[3].kind)
    }

    @Test
    fun nonAo3EpubEveryTocMatchIsChapterNumberedOneToN() {
        // Plain EPUB: TOC entry per spine item, none titled Preface/Summary/Afterword.
        val spine = listOf("a.xhtml", "b.xhtml", "c.xhtml")
        val toc = listOf(
            raw("Intro", 0),
            raw("Middle", 1),
            raw("End", 2)
        )
        val sections = ReaderSectionBuilder.build(toc, spine)
        assertTrue(sections.all { it.kind == ReaderSectionKind.CHAPTER })
        assertEquals(listOf(1, 2, 3), sections.map { it.storyChapterIndex })
        assertEquals(3, sections.storyChapterCount)
    }

    @Test
    fun nonAo3UntitledSpineWithoutPrefaceBecomesOther() {
        // No Preface → Summary synthesis never fires; unmatched spine → .other.
        val spine = listOf("cover.xhtml", "ch1.xhtml")
        val toc = listOf(raw("Chapter 1", 1))
        val sections = ReaderSectionBuilder.build(toc, spine)
        assertEquals(ReaderSectionKind.OTHER, sections[0].kind)
        assertEquals(ReaderSectionKind.CHAPTER, sections[1].kind)
        assertEquals(1, sections[1].storyChapterIndex)
        assertEquals(1, sections.storyChapterCount)
    }

    @Test
    fun classifyIsExactCaseInsensitive() {
        assertEquals(ReaderSectionKind.PREFACE, ReaderSectionBuilder.classify("Preface"))
        assertEquals(ReaderSectionKind.PREFACE, ReaderSectionBuilder.classify("  PREFACE  "))
        assertEquals(ReaderSectionKind.SUMMARY, ReaderSectionBuilder.classify("summary"))
        assertEquals(ReaderSectionKind.AFTERWORD, ReaderSectionBuilder.classify("Afterword"))
        // Epilogues and numbered chapter titles are real story content.
        assertEquals(ReaderSectionKind.CHAPTER, ReaderSectionBuilder.classify("Chapter 1"))
        assertEquals(ReaderSectionKind.CHAPTER, ReaderSectionBuilder.classify("Epilogue: Chapter 1"))
        assertEquals(ReaderSectionKind.CHAPTER, ReaderSectionBuilder.classify("My Preface Notes"))
    }

    @Test
    fun hrefKeyStripsFragmentPathPrefixAndCase() {
        assertEquals(
            "chapter01.xhtml",
            ReaderSectionBuilder.hrefKey("OEBPS/Text/Chapter01.xhtml#heading")
        )
        assertEquals(
            "chapter01.xhtml",
            ReaderSectionBuilder.hrefKey("Text/chapter01.xhtml")
        )
        assertEquals(
            "chapter01.xhtml",
            ReaderSectionBuilder.hrefKey("CHAPTER01.XHTML")
        )
        assertEquals(
            ReaderSectionBuilder.hrefKey("OEBPS/ch1.xhtml#frag"),
            ReaderSectionBuilder.hrefKey("../ch1.xhtml")
        )
    }

    @Test
    fun emptySpineYieldsEmptySections() {
        assertTrue(ReaderSectionBuilder.build(listOf(raw("Preface", 0)), emptyList()).isEmpty())
    }

    @Test
    fun storyChapterCountExcludesFrontAndBackMatter() {
        val sections = ReaderSectionBuilder.build(
            tocEntries = listOf(
                raw("Preface", 0),
                raw("Chapter 1", 2),
                raw("Chapter 2", 3),
                raw("Afterword", 4)
            ),
            spineHrefs = listOf("p", "s", "c1", "c2", "a")
        )
        assertEquals(2, sections.storyChapterCount)
        assertEquals(ReaderSectionKind.SUMMARY, sections[1].kind) // synthesized
    }

    @Test
    fun lastTocEntryWinsForDuplicateSpineIndex() {
        val sections = ReaderSectionBuilder.build(
            tocEntries = listOf(
                raw("Old Title", 0),
                raw("Preface", 0)
            ),
            spineHrefs = listOf("p.xhtml", "c1.xhtml")
        )
        assertEquals(ReaderSectionKind.PREFACE, sections[0].kind)
        assertEquals("Preface", sections[0].title)
    }
}
