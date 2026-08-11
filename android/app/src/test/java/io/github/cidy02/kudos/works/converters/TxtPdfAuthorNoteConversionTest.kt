package io.github.cidy02.kudos.works.converters

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * TXT / PDF conversion must mark recognisable author's notes and leave ordinary
 * prose alone. PDF path only works for uncompressed text streams (see
 * [PDFWorkConverter]); tests use synthetic "paragraphs" / a minimal PDF-shaped
 * payload so extraction succeeds.
 */
class TxtPdfAuthorNoteConversionTest {

    @Test
    fun txtWithRecognisableNoteProducesOneAuthorNoteAside() {
        val text = """
            A/N: thanks for reading this chapter.

            Once upon a time the hero left town.
        """.trimIndent()
        val body = PlainTextWorkConverter().paragraphs(text)
        assertTrue(body.contains("""class="author-note""""))
        assertTrue(body.contains("<aside"))
        assertEqualsOneAside(body)
        assertTrue(body.contains("thanks for reading this chapter"))
        assertTrue(body.contains("Once upon a time"))
        // Story must sit outside the aside.
        val asideEnd = body.indexOf("</aside>")
        assertTrue(body.indexOf("Once upon a time") > asideEnd)
    }

    @Test
    fun txtOrdinaryProseProducesNoAuthorNote() {
        val text = """
            She walked into the room and sat down.

            The fire crackled softly in the grate.
        """.trimIndent()
        val body = PlainTextWorkConverter().paragraphs(text)
        assertFalse(body.contains("author-note"))
        assertFalse(body.contains("<aside"))
    }

    @Test
    fun txtConsecutiveNoteParagraphsGroupIntoOneAside() {
        val text = """
            A/N: first line of the note.

            Beta'd by someone lovely.

            Thanks for reading, please review!

            The actual story starts here and runs on for a while.
        """.trimIndent()
        val body = PlainTextWorkConverter().paragraphs(text)
        assertEqualsOneAside(body)
    }

    @Test
    fun txtConvertShipsAuthorNoteCssInEpub() {
        val text = "A/N: note.\n\nStory body."
        val epub = PlainTextWorkConverter().convert("Titled", text.toByteArray(Charsets.UTF_8))
        assertNotNull(epub)
        val chapter = readZipEntry(epub!!, "OEBPS/content.html")?.toString(Charsets.UTF_8)
        assertNotNull(chapter)
        assertTrue(chapter!!.contains("author-note"))
        val css = readZipEntry(epub, "OEBPS/style.css")?.toString(Charsets.UTF_8)
        assertNotNull(css)
        assertTrue(css!!.contains(".author-note"))
    }

    @Test
    fun pdfExtractedParagraphsWithNoteProduceAuthorNoteAside() {
        // Drive the same markup path the converter uses after extraction.
        val paragraphs = listOf(
            "A/N: PDF note before the story.",
            "She opened the book and began to read."
        )
        val body = paragraphsWithAuthorNotes(paragraphs)
        assertTrue(body.contains("""class="author-note""""))
        assertEqualsOneAside(body)
        assertFalse(
            body.indexOf("She opened the book").let { storyAt ->
                storyAt >= 0 && body.lastIndexOf("author-note", storyAt) >
                    body.lastIndexOf("</aside>", storyAt).coerceAtLeast(0)
            }
        )
    }

    @Test
    fun pdfOrdinaryProseProducesNoAuthorNote() {
        val body = paragraphsWithAuthorNotes(
            listOf(
                "She walked into the room and sat down.",
                "The fire crackled softly in the grate."
            )
        )
        assertFalse(body.contains("author-note"))
        assertFalse(body.contains("<aside"))
    }

    @Test
    fun pdfConvertUsesDetectorOnExtractedLiterals() {
        // Minimal uncompressed PDF-ish payload: a text object with two literals.
        val pdf = """
            %PDF-1.1
            1 0 obj<<>>endobj
            2 0 obj<< /Length 80 >>stream
            BT (A/N: note from pdf.) Tj (The story continues here without apparatus.) Tj ET
            endstream
            endobj
        """.trimIndent().toByteArray(Charsets.ISO_8859_1)

        val paragraphs = PDFWorkConverter().extractParagraphs(pdf)
        assertNotNull(paragraphs)
        assertTrue(paragraphs!!.any { it.contains("A/N:") })

        val epub = PDFWorkConverter().convert("PDF Work", pdf)
        assertNotNull(epub)
        val chapter = readZipEntry(epub!!, "OEBPS/content.html")?.toString(Charsets.UTF_8)
        assertNotNull(chapter)
        assertTrue(chapter!!.contains("author-note"))
        assertTrue(chapter.contains("note from pdf"))
    }

    private fun assertEqualsOneAside(body: String) {
        assertEquals(1, Regex("<aside").findAll(body).count())
        assertEquals(1, Regex("</aside>").findAll(body).count())
    }

    private fun readZipEntry(zipBytes: ByteArray, name: String): ByteArray? {
        ZipInputStream(ByteArrayInputStream(zipBytes)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.name == name) return zip.readBytes()
            }
        }
        return null
    }
}
