package io.github.cidy02.kudos.works.converters

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * HTML imports must mark AO3 author's notes as `<aside class="author-note">`
 * and ship the matching stylesheet (iOS HTMLWorkSanitizer / EPUBBuilder parity).
 */
class AuthorNoteMarkupTest {

    @Test
    fun ao3NotesDivBecomesAuthorNoteAside() {
        val html = """
            <html><body>
              <div id="workskin">
                <div class="preface group">
                  <div class="notes module">
                    <h3 class="heading">Notes:</h3>
                    <blockquote class="userstuff">
                      <p>Thanks to my beta!</p>
                    </blockquote>
                  </div>
                </div>
                <div class="userstuff">
                  <p>Once upon a time the story began.</p>
                </div>
              </div>
            </body></html>
        """.trimIndent()

        val body = HTMLWorkConverter().sanitizedBody(html)
        assertTrue(
            "notes container must become aside.author-note, got: $body",
            body.contains("""class="author-note"""") || body.contains("class='author-note'")
        )
        assertTrue(
            "must use aside tag, got: $body",
            body.contains("<aside") && body.contains("</aside>")
        )
        assertTrue(body.contains("Thanks to my beta!"))
        assertTrue(body.contains("Once upon a time"))
        // Summary-like prose must not be forced into a note by heuristics.
        assertFalse(
            "story prose must not be wrapped as author-note",
            body.indexOf("Once upon a time").let { proseAt ->
                proseAt >= 0 && body.lastIndexOf("author-note", proseAt) >
                    body.lastIndexOf("</aside>", proseAt).coerceAtLeast(0)
            }
        )
    }

    @Test
    fun endNotesDivBecomesAuthorNoteAside() {
        val html = """
            <html><body>
              <div id="workskin">
                <p>Chapter body.</p>
                <div class="end notes module">
                  <p>A/N: next chapter soon.</p>
                </div>
              </div>
            </body></html>
        """.trimIndent()

        val body = HTMLWorkConverter().sanitizedBody(html)
        assertTrue(body.contains("author-note"))
        assertTrue(body.contains("next chapter soon"))
    }

    @Test
    fun htmlWithoutNotesProducesNoAuthorNoteMarkup() {
        val html = """
            <html><body>
              <div id="workskin">
                <div class="userstuff">
                  <p>Just ordinary prose with no notes module.</p>
                  <p>She walked into the room and sat down.</p>
                </div>
              </div>
            </body></html>
        """.trimIndent()

        val body = HTMLWorkConverter().sanitizedBody(html)
        assertFalse(
            "plain prose must not invent author-note markup: $body",
            body.contains("author-note")
        )
        assertFalse(body.contains("<aside"))
        assertTrue(body.contains("ordinary prose"))
    }

    @Test
    fun convertShipsAuthorNoteCssAndMarkupInEpub() {
        val html = """
            <html><body>
              <div id="workskin">
                <div class="notes">
                  <p>Author note text.</p>
                </div>
                <p>Story text.</p>
              </div>
            </body></html>
        """.trimIndent()

        val epub = HTMLWorkConverter().convert("Titled Work", html.toByteArray(Charsets.UTF_8))
        assertNotNull(epub)

        val chapter = readZipEntry(epub!!, "OEBPS/content.html")?.toString(Charsets.UTF_8)
        assertNotNull(chapter)
        assertTrue(chapter!!.contains("author-note"))
        assertTrue(chapter.contains("""href="style.css""""))

        val css = readZipEntry(epub, "OEBPS/style.css")?.toString(Charsets.UTF_8)
        assertNotNull(css)
        assertTrue(
            "EPUB must include .author-note rules: $css",
            css!!.contains(".author-note")
        )
        assertTrue(css.contains("font-style: italic"))
    }

    @Test
    fun convertWithoutNotesShipsCssButNoAuthorNoteMarkup() {
        val html = """
            <html><body>
              <div id="workskin"><p>Only story.</p></div>
            </body></html>
        """.trimIndent()

        val epub = HTMLWorkConverter().convert("Titled Work", html.toByteArray(Charsets.UTF_8))
        assertNotNull(epub)
        val chapter = readZipEntry(epub!!, "OEBPS/content.html")?.toString(Charsets.UTF_8)
        assertNotNull(chapter)
        assertFalse(chapter!!.contains("author-note"))
        // Stylesheet is always present (harmless when unused).
        assertNotNull(readZipEntry(epub, "OEBPS/style.css"))
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
