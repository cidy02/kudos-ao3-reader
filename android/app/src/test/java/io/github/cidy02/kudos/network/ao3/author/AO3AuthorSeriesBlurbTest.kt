package io.github.cidy02.kudos.network.ao3.author

import org.junit.Assert.*
import org.junit.Test
import java.io.File

class AO3AuthorSeriesBlurbTest {
    private val page = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
        .map { File("$it/fixtures/ao3_author_series.html") }.first(File::isFile).readText()
    private fun series(html: String, id: Long) = AO3AuthorParser().parseSeriesPage(html, 1).series.first { it.id == id }

    @Test fun aSeriesKeepsItsLockItsBookmarksAndWhetherItIsComplete() {
        val dawn = series(page, 321)
        assertTrue(dawn.isRestricted); assertEquals(62, dawn.bookmarkCount); assertEquals(true, dawn.isComplete)
        val hidden = series(page, 322)
        assertFalse(hidden.isRestricted); assertNull(hidden.bookmarkCount); assertEquals(false, hidden.isComplete)
    }

    @Test fun aSummaryThatSaysRestrictedIsNotALock() {
        val html = page.replace(Regex("<img[^>]*lockblue[^>]*>"), "")
            .replace("Three stories about a difficult sunrise.", "A restricted garden.")
        assertNotEquals(page, html)
        assertEquals("A restricted garden.", series(html, 321).summary)
        assertFalse(series(html, 321).isRestricted)
    }

    /** AO3 labels each figure. Where the label carries the figure's class, the label was read. */
    @Test fun aFigureIsReadPastALabelOfTheSameClass() {
        val html = page.replace(Regex("""<dd class="(words|works|bookmarks)">""")) {
            """<dt class="${it.groupValues[1]}">${it.groupValues[1].replaceFirstChar(Char::uppercase)}:</dt>${it.value}"""
        }
        assertTrue(html.contains("""<dt class="words">Words:</dt><dd class="words">45,678"""))
        val dawn = series(html, 321)
        assertEquals(45_678, dawn.words); assertEquals(3, dawn.workCount); assertEquals(62, dawn.bookmarkCount)
    }
}
