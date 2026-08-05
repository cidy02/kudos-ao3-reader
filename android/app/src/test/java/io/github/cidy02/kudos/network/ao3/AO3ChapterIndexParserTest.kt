package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterIndexParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3ChapterIndexParserTest {

    private val navigateHtml = """
        <html><body>
        <ol class="chapter index group">
          <li><a href="/works/123/chapters/1001">1. The Beginning</a> <span class="datetime">(2026-01-02)</span></li>
          <li><a href="/works/123/chapters/1002">2. Middle Things</a> <span class="datetime">(2026-01-09)</span></li>
          <li><a href="/works/123/chapters/1003">4. After a Deletion</a></li>
        </ol>
        </body></html>
    """.trimIndent()

    @Test
    fun `parses id, position and title from each row`() {
        val chapters = AO3ChapterIndexParser.parse(navigateHtml)
        assertEquals(3, chapters.size)
        assertEquals(1001L, chapters[0].chapterId)
        assertEquals(1, chapters[0].position)
        assertEquals("The Beginning", chapters[0].title)
        assertEquals("2026-01-02", chapters[0].dateText)
    }

    @Test
    fun `AO3's own number wins over the running count`() {
        // A work with a deleted chapter still numbers the survivors correctly, so
        // the third row is chapter 4 — using the row index would mis-target comments.
        val chapters = AO3ChapterIndexParser.parse(navigateHtml)
        assertEquals(4, chapters[2].position)
        assertEquals("After a Deletion", chapters[2].title)
    }

    @Test
    fun `display name collapses AO3's repeated default title`() {
        val chapters = AO3ChapterIndexParser.parse(
            """<ol class="chapter index"><li><a href="/works/1/chapters/5">3. Chapter 3</a></li></ol>"""
        )
        assertEquals("Chapter 3", chapters.single().displayName)
    }

    @Test
    fun `a page without a chapter index yields nothing rather than throwing`() {
        assertTrue(AO3ChapterIndexParser.parse("<html><body>Log in</body></html>").isEmpty())
    }
}
