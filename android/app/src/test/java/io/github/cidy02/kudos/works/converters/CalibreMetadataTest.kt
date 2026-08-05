package io.github.cidy02.kudos.works.converters

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CalibreMetadataTest {

    private val exported = """
        Story: In the Service of the Queen
        Storylink: https://www.fanfiction.net/s/10251701/1/
        Category: Frozen
        Genre: Romance/Fantasy
        Rating: M
        Status: Complete
        Summary: Anna lives a rugged life.
    """.trimIndent().lines()

    @Test
    fun `parses an exported label block`() {
        val meta = CalibreMetadata.parse(exported)!!
        assertEquals("In the Service of the Queen", meta.title)
        assertEquals(listOf("Frozen"), meta.fandoms)
        assertEquals(listOf("Romance", "Fantasy"), meta.freeforms)
        assertEquals("M", meta.rating)
        assertEquals(true, meta.isComplete)
        assertEquals("Anna lives a rugged life.", meta.summary)
    }

    @Test
    fun `Storylink is not swallowed by Story`() {
        // Label order is load-bearing: longest first. If "Story:" matched first,
        // the source URL would be lost and the work stranded with no origin.
        val meta = CalibreMetadata.parse(exported)!!
        assertEquals("https://www.fanfiction.net/s/10251701/1/", meta.sourceUrl)
        assertTrue(meta.title!!.startsWith("In the Service"))
    }

    @Test
    fun `an ordinary chapter opening with Summary is not a metadata page`() {
        val chapter = listOf("Summary: he thought about it.", "", "The rain kept falling.")
        assertNull(CalibreMetadata.parse(chapter))
    }

    @Test
    fun `a non-http storylink is rejected rather than stored`() {
        val meta = CalibreMetadata.parse(
            listOf("Story: X", "Storylink: not-a-url", "Category: Y", "Rating: T")
        )!!
        assertNull(meta.sourceUrl)
    }
}
