package io.github.cidy02.kudos.network.ao3.work

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS AO3ClientTests work-page fixture; assertions for Android's existing reader fields. */
class WorkPageMetadataParityTest {
    private val parser = AO3WorkMetadataParser()

    @Test
    fun parsesWorkPageMetadata() {
        val metadata = parser.parse(workHtml)
        assertEquals("A Test Work", metadata.title)
        assertEquals(listOf("alice"), metadata.authors)
        assertTrue(metadata.authorIdentitiesJSON.contains("alice"))
        assertEquals("A fuller summary.", metadata.summary)
        assertEquals("Teen And Up Audiences", metadata.rating)
        assertEquals(listOf("Naruto"), metadata.fandoms)
        assertEquals(listOf("Naruto/Hinata"), metadata.relationships)
        assertEquals(listOf("Hinata Hyuuga", "Naruto Uzumaki"), metadata.characters)
        assertEquals(listOf("Fluff"), metadata.freeforms)
        assertEquals(listOf("No Archive Warnings Apply"), metadata.warnings)
        assertEquals(listOf("Gen"), metadata.categories)
        assertEquals("English", metadata.language)
        assertEquals(12345, metadata.words)
        assertEquals("5/10", metadata.chapters)
        assertEquals(890, metadata.kudos)
        assertEquals(76, metadata.comments)
        assertEquals(54321, metadata.hits)
        assertEquals("01 Jan 2026", metadata.datePublished)
        assertEquals("02 Jan 2026", metadata.dateUpdated)
        // AO3's Completed: label wins even though this fixture's chapters say 5/10.
        assertEquals(true, metadata.isComplete)

    }

    @Test
    fun parsesWorkInProgressStatusFromUnclassedLabel() {
        val html = """<html><body><h2 class="title heading">A WIP</h2>
            <dl class="work meta group"><dt>Updated:</dt><dd class="status">03 Jan 2026</dd>
            <dl class="stats"><dd class="chapters">3/?</dd></dl></dl></body></html>"""
        val metadata = parser.parse(html)
        assertEquals("03 Jan 2026", metadata.dateUpdated)
        assertEquals(false, metadata.isComplete)
        // A labelled Updated: wins over an apparently complete ratio too.
        assertEquals(false, parser.parse(html.replace("3/?", "3/3")).isComplete)
    }

    @Test
    fun absentStatusUsesTheChapterRatioAndMissingDataStaysUnknown() {
        for ((chapters, complete) in listOf("1/1" to true, "3/5" to false, "3/?" to false,
            "" to null, "3/0" to null, "unknown" to null)) {
            assertEquals(chapters, complete, parser.parse("<dd class='chapters'>$chapters</dd>").isComplete)
        }
        val metadata = parser.parse("<dd class='updated'>04 Jan 2026</dd>")
        assertEquals("04 Jan 2026", metadata.dateUpdated)
        assertEquals("", metadata.datePublished)
        assertNull(metadata.isComplete)
    }

    private val workHtml = """
        <html><body>
        <h2 class="title heading">A Test Work</h2>
        <h3 class="byline heading"><a rel="author" href="/users/alice">alice</a></h3>
        <div class="summary module">
          <blockquote class="userstuff"><p>A fuller summary.</p></blockquote>
        </div>
        <dl class="work meta group">
          <dd class="rating tags"><ul><li><a class="tag" href="#">Teen And Up Audiences</a></li></ul></dd>
          <dd class="fandom tags"><ul class="commas"><li><a class="tag" href="#">Naruto</a></li></ul></dd>
          <dd class="warning tags"><ul><li><a class="tag" href="#">No Archive Warnings Apply</a></li></ul></dd>
          <dd class="relationship tags"><ul><li><a class="tag" href="#">Naruto/Hinata</a></li></ul></dd>
          <dd class="character tags"><ul>
            <li><a class="tag" href="#">Hinata Hyuuga</a></li>
            <li><a class="tag" href="#">Naruto Uzumaki</a></li>
          </ul></dd>
          <dd class="freeform tags"><ul><li><a class="tag" href="#">Fluff</a></li></ul></dd>
          <dd class="category tags"><ul><li><a class="tag" href="#">Gen</a></li></ul></dd>
          <dd class="language">English</dd>
          <dd class="published">01 Jan 2026</dd>
          <dt>Completed:</dt><dd class="status">02 Jan 2026</dd>
          <dd class="series"><span class="position">Part 2 of <a href="/series/777">My Series</a></span></dd>
          <dl class="stats">
            <dd class="words">12,345</dd>
            <dd class="chapters">5/10</dd>
            <dd class="kudos">890</dd>
            <dd class="comments">76</dd>
            <dd class="hits">54,321</dd>
          </dl>
        </dl>
        </body></html>
    """.trimIndent()
}
