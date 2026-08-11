package io.github.cidy02.kudos.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderTocBuilderTest {

    @Test
    fun prefersFlattenedTocOverReadingOrder() {
        val toc = listOf(
            ReaderTocBuilder.SourceLink(
                title = "Part 1",
                href = "part1.xhtml",
                children = listOf(
                    ReaderTocBuilder.SourceLink("Chapter 1", "ch1.xhtml"),
                    ReaderTocBuilder.SourceLink("Chapter 2", "ch2.xhtml")
                )
            )
        )
        val readingOrder = listOf(
            ReaderTocBuilder.SourceLink("Spine only", "spine.xhtml")
        )

        val entries = ReaderTocBuilder.build(toc, readingOrder)
        assertEquals(
            listOf(
                ReaderTocEntry("Part 1", "part1.xhtml", depth = 0),
                ReaderTocEntry("Chapter 1", "ch1.xhtml", depth = 1),
                ReaderTocEntry("Chapter 2", "ch2.xhtml", depth = 1)
            ),
            entries
        )
    }

    @Test
    fun fallsBackToReadingOrderWhenTocEmpty() {
        val readingOrder = listOf(
            ReaderTocBuilder.SourceLink(title = null, href = "a.xhtml"),
            ReaderTocBuilder.SourceLink(title = "Named", href = "b.xhtml")
        )
        val entries = ReaderTocBuilder.build(emptyList(), readingOrder)
        assertEquals("Section 1", entries[0].title)
        assertEquals("a.xhtml", entries[0].href)
        assertEquals("Named", entries[1].title)
        assertEquals(0, entries[1].depth)
    }

    @Test
    fun emptySourcesYieldEmptyList() {
        assertTrue(ReaderTocBuilder.build(emptyList(), emptyList()).isEmpty())
    }

    @Test
    fun skipsBlankHrefButKeepsChildren() {
        val toc = listOf(
            ReaderTocBuilder.SourceLink(
                title = "Container",
                href = "",
                children = listOf(ReaderTocBuilder.SourceLink("Child", "child.xhtml"))
            )
        )
        val entries = ReaderTocBuilder.build(toc, emptyList())
        assertEquals(listOf(ReaderTocEntry("Child", "child.xhtml", depth = 1)), entries)
    }
}
