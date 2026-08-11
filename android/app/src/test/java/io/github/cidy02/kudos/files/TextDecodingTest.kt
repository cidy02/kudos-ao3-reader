package io.github.cidy02.kudos.files

import io.github.cidy02.kudos.works.converters.ArchiveWorkConverter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class TextDecodingTest {

    @Test
    fun `utf8 round trips`() {
        val text = "Kudos — “quoted”, naïve, 日本語"
        assertEquals(text, TextDecoding.decode(text.toByteArray(Charsets.UTF_8)))
    }

    @Test
    fun `latin1 with an even byte count is not misread as utf16`() {
        // The defect this guards: without the BOM gate, a UTF-16 decode succeeds on
        // almost any even-length input and returns CJK-looking mojibake, so an
        // ordinary Latin-1 file would import as garbage.
        val bytes = byteArrayOf(0xE9.toByte(), 0xE8.toByte(), 0xFC.toByte(), 0xF1.toByte())
        assertEquals(4, bytes.size % 2 + 4)
        val decoded = TextDecoding.decode(bytes)
        assertNotNull(decoded)
        assertEquals("éèüñ", decoded)
    }

    @Test
    fun `utf16 is honoured behind a BOM and the BOM is stripped`() {
        val bytes = byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + "Hi".toByteArray(Charsets.UTF_16LE)
        assertEquals("Hi", TextDecoding.decode(bytes))
    }

    @Test
    fun `empty input decodes to null`() {
        assertNull(TextDecoding.decode(ByteArray(0)))
    }

    @Test
    fun `archive stitches members in natural order, not lexical`() {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zos ->
            listOf("chapter10.txt" to "Tenth.", "chapter2.txt" to "Second.").forEach { (name, body) ->
                zos.putNextEntry(ZipEntry(name))
                zos.write(body.toByteArray())
                zos.closeEntry()
            }
        }
        val epub = ArchiveWorkConverter.convert("Story", out.toByteArray())
        assertNotNull("readable members should build an EPUB", epub)
        // The EPUB's documents are deflated, so read the entry rather than the bytes.
        val content = java.util.zip.ZipInputStream(java.io.ByteArrayInputStream(epub!!)).use { zis ->
            generateSequence { zis.nextEntry }
                .firstOrNull { it.name.endsWith("content.html") }
                ?.let { zis.readBytes().toString(Charsets.UTF_8) }
        }
        assertNotNull("EPUB should contain content.html", content)
        assertTrue(
            "chapter2 must precede chapter10",
            content!!.indexOf("Second.") < content.indexOf("Tenth.")
        )
    }

    @Test
    fun `archive prefers a nested epub over stitching`() {
        val inner = ByteArrayOutputStream()
        ZipOutputStream(inner).use { zos ->
            zos.putNextEntry(ZipEntry("mimetype")); zos.write("application/epub+zip".toByteArray()); zos.closeEntry()
            zos.putNextEntry(ZipEntry("META-INF/container.xml")); zos.write("<container/>".toByteArray()); zos.closeEntry()
        }
        val outer = ByteArrayOutputStream()
        ZipOutputStream(outer).use { zos ->
            zos.putNextEntry(ZipEntry("readme.txt")); zos.write("ignore me".toByteArray()); zos.closeEntry()
            zos.putNextEntry(ZipEntry("story.epub")); zos.write(inner.toByteArray()); zos.closeEntry()
        }
        val result = ArchiveWorkConverter.convert("Story", outer.toByteArray())
        assertNotNull(result)
        assertEquals(ImportedFileFormat.EPUB, ImportedFileFormat.sniff(result!!, "story.epub"))
    }

    @Test
    fun `archive with nothing readable fails rather than making an empty work`() {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zos ->
            zos.putNextEntry(ZipEntry("cover.png")); zos.write(byteArrayOf(1, 2, 3)); zos.closeEntry()
        }
        assertNull(ArchiveWorkConverter.convert("Story", out.toByteArray()))
    }
}
