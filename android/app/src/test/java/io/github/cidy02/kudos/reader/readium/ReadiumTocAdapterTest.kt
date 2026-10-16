package io.github.cidy02.kudos.reader.readium

import io.github.cidy02.kudos.reader.ReaderSectionKind
import io.github.cidy02.kudos.reader.storyChapterCount
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReadiumTocAdapterTest {
    private fun link(href: String, title: String? = null, children: List<Link> = emptyList()) =
        Link(href = Href(href)!!, title = title, children = children)

    // ReadiumReaderTests: same-file parent/child preserves outer title and chapter numbering.
    @Test fun sharedHrefKeepsTheOutermostTitle() {
        val spine = listOf(link("c1.xhtml"), link("c2.xhtml"))
        val toc = listOf(link("c1.xhtml", "Part One", listOf(
            link("c1.xhtml", "Chapter 1"), link("c2.xhtml", "Chapter 2")
        )))
        val sections = ReadiumTocAdapter.sections(toc, spine)
        assertEquals(listOf("Part One", "Chapter 2"), sections.map { it.title })
        assertEquals(listOf(1, 2), sections.map { it.storyChapterIndex })
    }

    @Test fun afterwordSharingAChildsHrefNeverBecomesAChapter() {
        val sections = ReadiumTocAdapter.sections(
            listOf(link("c1.xhtml", "Chapter 1"), link("after.xhtml", "Afterword", listOf(link("after.xhtml", "Chapter 2")))),
            listOf(link("c1.xhtml"), link("after.xhtml"))
        )
        assertEquals(listOf(ReaderSectionKind.CHAPTER, ReaderSectionKind.AFTERWORD), sections.map { it.kind })
        assertEquals(1, sections.storyChapterCount)
    }

    @Test fun distinctNestedChildrenStillBecomeSectionsInDocumentOrder() {
        val sections = ReadiumTocAdapter.sections(
            listOf(link("part.xhtml", "Part One", listOf(link("c1.xhtml", "Chapter 1", listOf(link("c1a.xhtml", "Chapter 1a")))))),
            listOf(link("part.xhtml"), link("c1.xhtml"), link("c1a.xhtml"))
        )
        assertEquals(listOf("Part One", "Chapter 1", "Chapter 1a"), sections.map { it.title })
    }
}
