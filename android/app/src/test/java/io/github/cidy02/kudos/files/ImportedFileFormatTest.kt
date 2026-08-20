package io.github.cidy02.kudos.files

import io.github.cidy02.kudos.works.converters.KudosMuPDF
import io.github.cidy02.kudos.works.converters.PDFWorkConverter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class ImportedFileFormatTest {

    private fun zip(vararg entries: String): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zos ->
            entries.forEach { name ->
                zos.putNextEntry(ZipEntry(name))
                zos.write("x".toByteArray())
                zos.closeEntry()
            }
        }
        return out.toByteArray()
    }

    @Test
    fun `renamed epub is rescued by its container entry`() {
        // The case this exists for: a real EPUB that arrived as fic.epub.zip.
        val bytes = zip("mimetype", "META-INF/container.xml", "OEBPS/content.opf")
        assertEquals(ImportedFileFormat.EPUB, ImportedFileFormat.sniff(bytes, "fic.epub.zip"))
    }

    @Test
    fun `plain zip without a container is not an epub`() {
        val bytes = zip("notes.txt", "photo.jpg")
        assertEquals(ImportedFileFormat.ZIP, ImportedFileFormat.sniff(bytes, "bundle.zip"))
    }

    @Test
    fun `a file named epub stays epub even when structurally bogus`() {
        // Structure is validated downstream; sniffing must not pre-empt that,
        // or WorkImporter's "not a valid EPUB" message never fires.
        val bogus = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3)
        assertEquals(ImportedFileFormat.EPUB, ImportedFileFormat.sniff(bogus, "story.epub"))
    }

    @Test
    fun `pdf is detected by magic bytes regardless of name`() {
        val bytes = "%PDF-1.7\nnonsense".toByteArray(Charsets.ISO_8859_1)
        assertEquals(ImportedFileFormat.PDF, ImportedFileFormat.sniff(bytes, "story.txt"))
    }

    @Test
    fun `html is detected by content not extension`() {
        val bytes = "<!DOCTYPE html><html><body>hi</body></html>".toByteArray()
        assertEquals(ImportedFileFormat.HTML, ImportedFileFormat.sniff(bytes, "chapter.txt"))
    }

    private fun converter() = PDFWorkConverter(Files.createTempDirectory("kudos-pdf-tests").toFile())

    @Test
    fun `pdf conversion refuses honestly when the native MuPDF library isn't loaded`() {
        // KudosMuPDF.isAvailable is always false here: this is a plain JVM unit
        // test, and libkudosmupdf.so is an Android .so the JVM can't load. That's
        // exactly the "checkout hasn't run build-mupdf.sh" case PDFWorkConverter
        // is documented to handle by refusing rather than guessing — assert that
        // path directly instead of asserting something that happens to look like
        // a parse failure for the wrong reason.
        assertFalse(
            "expected native MuPDF to be unavailable in a JVM unit test",
            KudosMuPDF.isAvailable
        )
        val bytes = "%PDF-1.4\nBT (Hello there, reader.) Tj ET".toByteArray(Charsets.ISO_8859_1)
        assertNull(converter().convert("Story", bytes))
    }

    @Test
    fun `uncompressed pdf text still converts when the native library is present`() {
        // Only meaningful on a device/emulator with the real .so — see
        // android/Scripts/build-mupdf.sh. Skips (not fails) under a plain JVM run.
        assumeTrue(KudosMuPDF.isAvailable)
        val simple = "%PDF-1.4\nBT (Hello there, reader.) Tj ET".toByteArray(Charsets.ISO_8859_1)
        val epub = converter().convert("Story", simple)
        assertNotNull("plain literal text should still be extractable", epub)
        assertEquals(ImportedFileFormat.EPUB, ImportedFileFormat.sniff(epub!!, "Story.epub"))
    }
}
