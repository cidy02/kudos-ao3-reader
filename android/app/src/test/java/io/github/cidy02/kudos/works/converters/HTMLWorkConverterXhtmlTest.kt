package io.github.cidy02.kudos.works.converters

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.xml.sax.InputSource

/**
 * Fix 2: HTML → EPUB chapters must be well-formed XHTML. A plain Jsoup.clean
 * emits unclosed void elements (`<br>`); XML output settings yield `<br />`.
 */
class HTMLWorkConverterXhtmlTest {

    @Test
    fun brSerialisesAsSelfClosingAndChapterParsesAsXml() {
        val html = """
            <html><body>
              <div id="workskin">
                <p>Line one<br>Line two<br/>Line three</p>
              </div>
            </body></html>
        """.trimIndent()

        val body = HTMLWorkConverter().sanitizedBody(html)
        assertTrue(
            "void <br> must serialise self-closing for XHTML, got: $body",
            body.contains("<br />") || body.contains("<br/>")
        )
        // Bare HTML void form: <br> not followed by / (self-close) — reject it.
        assertTrue(
            "must not emit bare HTML-style unclosed <br>: $body",
            !Regex("""<br(?!\s*/)""").containsMatchIn(body)
        )

        // Prefer strict XML well-formedness of the chapter body fragment
        // wrapped the same way EpubBuilder embeds it.
        // Declaration must be the very first characters of the document.
        val chapterXml =
            """<?xml version="1.0" encoding="UTF-8"?>""" +
                """<html xmlns="http://www.w3.org/1999/xhtml">""" +
                """<head><title>t</title></head><body>$body</body></html>"""
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            isValidating = false
        }
        val builder = factory.newDocumentBuilder()
        builder.setErrorHandler(object : org.xml.sax.ErrorHandler {
            override fun warning(exception: org.xml.sax.SAXParseException) = Unit
            override fun error(exception: org.xml.sax.SAXParseException) = throw exception
            override fun fatalError(exception: org.xml.sax.SAXParseException) = throw exception
        })
        val parsed = builder.parse(InputSource(chapterXml.reader()))
        assertNotNull(parsed.documentElement)

        // Full convert path: chapter inside the EPUB zip also parses as XML.
        val epub = HTMLWorkConverter().convert("Title", html.toByteArray(Charsets.UTF_8))
        assertNotNull(epub)
        val chapterBytes = readZipEntry(epub!!, "OEBPS/content.html")
        assertNotNull(chapterBytes)
        val chapterText = chapterBytes!!.toString(Charsets.UTF_8).trimStart()
        assertTrue(chapterText.contains("<br />") || chapterText.contains("<br/>"))
        builder.parse(InputSource(chapterText.reader()))
    }

    private fun readZipEntry(zipBytes: ByteArray, name: String): ByteArray? {
        ZipInputStream(ByteArrayInputStream(zipBytes)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.name == name) {
                    return zip.readBytes()
                }
            }
        }
        return null
    }
}
