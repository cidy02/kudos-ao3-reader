package io.github.cidy02.kudos.works

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Extraction cases that A-524's own extractor test proved, now proved against the shared
 * [EmbeddedWorkCoverImage] (the one the A-573 loader and every cover surface use).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class EmbeddedWorkCoverImageTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private val opfHead = """<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>T</dc:title>
        <dc:creator>Author</dc:creator><dc:language>en</dc:language></metadata><manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="preface" href="preface.xhtml" media-type="application/xhtml+xml"/>"""

    private fun opf(chapterHref: String) = "$opfHead\n" +
        """<item id="chapter" href="$chapterHref" media-type="application/xhtml+xml"/></manifest>
        <spine><itemref idref="preface"/><itemref idref="chapter"/></spine></package>"""

    @Test
    fun percentDecodeKeepsSurrogatePairsIntactAndPlusLiteral() {
        assertEquals("📖 1.xhtml", EmbeddedWorkCoverImage.percentDecode("📖%201.xhtml"))
        assertEquals("📖+1.xhtml", EmbeddedWorkCoverImage.percentDecode("📖%2B1.xhtml"))
        assertEquals("📖 1.xhtml", EmbeddedWorkCoverImage.percentDecode("%F0%9F%93%96%201.xhtml"))
        assertEquals("📖%ZZ1.xhtml", EmbeddedWorkCoverImage.percentDecode("📖%ZZ1.xhtml"))
        assertEquals("📖%FF1.xhtml", EmbeddedWorkCoverImage.percentDecode("📖%FF1.xhtml"))
    }

    @Test
    fun astralTocHrefMatchesItsSpineDocument() {
        val art = png(320, Color.RED)
        val epub = zip(
            "astral.epub",
            "OEBPS/content.opf" to opf("📖 1.xhtml"),
            "OEBPS/nav.xhtml" to nav("""<nav epub:type="toc"><a href="preface.xhtml">Preface</a><a href="📖%201.xhtml">Chapter 1</a></nav>"""),
            "OEBPS/preface.xhtml" to "<html><body><p>Preface</p></body></html>".toByteArray(),
            "OEBPS/📖 1.xhtml" to "<html><body><img src='art.png'/></body></html>".toByteArray(),
            "OEBPS/art.png" to art
        )
        assertArrayEquals(art, EmbeddedWorkCoverImage.data(epub))
    }

    @Test
    fun tocHrefPlusIsNotTreatedAsSpace() {
        val art = png(320, Color.GREEN)
        val epub = zip(
            "plus.epub",
            "OEBPS/content.opf" to opf("ch+1.xhtml"),
            "OEBPS/nav.xhtml" to nav("""<nav epub:type="toc"><a href="preface.xhtml">Preface</a><a href="ch%2B1.xhtml">Chapter 1</a></nav>"""),
            "OEBPS/preface.xhtml" to "<html><body><p>Preface</p></body></html>".toByteArray(),
            "OEBPS/ch+1.xhtml" to "<html><body><img src='art.png'/></body></html>".toByteArray(),
            "OEBPS/art.png" to art
        )
        assertArrayEquals(art, EmbeddedWorkCoverImage.data(epub))
    }

    @Test
    fun navIdentifiedByIdTocIsUsedWhenItIsNotFirst() {
        val art = png(400, Color.BLUE)
        val epub = zip(
            "id-toc.epub",
            "OEBPS/content.opf" to opf("chapter.xhtml"),
            "OEBPS/nav.xhtml" to nav(
                """<nav epub:type="landmarks"><a href="preface.xhtml">Landmarks</a></nav>
                   <nav id="toc"><a href="preface.xhtml">Preface</a><a href="chapter.xhtml">Chapter 1</a></nav>"""
            ),
            "OEBPS/preface.xhtml" to "<html><body><p>Preface</p></body></html>".toByteArray(),
            "OEBPS/chapter.xhtml" to "<html><body><img src='art.png'/></body></html>".toByteArray(),
            "OEBPS/art.png" to art
        )
        // Only the id=toc nav puts the preface before chapter 1, so the art is found only through it.
        assertArrayEquals(art, EmbeddedWorkCoverImage.data(epub))
    }

    @Test
    fun imageLargerThanTheByteCapIsSkippedEvenWithAValidHeader() {
        val oversized = png(320, Color.RED) + ByteArray(EmbeddedWorkCoverImage.MAX_IMAGE_BYTES)
        val epub = zip(
            "oversized.epub",
            "OEBPS/content.opf" to opf("chapter.xhtml"),
            "OEBPS/nav.xhtml" to nav("""<nav epub:type="toc"><a href="preface.xhtml">Preface</a><a href="chapter.xhtml">Chapter 1</a></nav>"""),
            "OEBPS/preface.xhtml" to "<html><body><p>Preface</p></body></html>".toByteArray(),
            "OEBPS/chapter.xhtml" to "<html><body><img src='art.png'/></body></html>".toByteArray(),
            "OEBPS/art.png" to oversized
        )
        assertNull(EmbeddedWorkCoverImage.data(epub))
    }

    private fun nav(body: String) =
        """<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>$body</body></html>"""
            .toByteArray(StandardCharsets.UTF_8)

    private fun png(width: Int, color: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(width, 800, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawColor(color)
        val out = ByteArrayOutputStream()
        assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, out))
        return out.toByteArray()
    }

    private fun zip(name: String, vararg entries: Pair<String, Any>): File {
        val container = """<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>"""
        val all = listOf<Pair<String, Any>>(
            "mimetype" to "application/epub+zip",
            "META-INF/container.xml" to container
        ) + entries
        val epub = tempFolder.newFile(name)
        ZipOutputStream(epub.outputStream()).use { zip ->
            for ((entryName, content) in all) {
                val bytes = if (content is ByteArray) content else content.toString().toByteArray(StandardCharsets.UTF_8)
                zip.putNextEntry(ZipEntry(entryName).apply {
                    method = ZipEntry.STORED
                    size = bytes.size.toLong()
                    compressedSize = bytes.size.toLong()
                    crc = CRC32().apply { update(bytes) }.value
                })
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        return epub
    }
}
