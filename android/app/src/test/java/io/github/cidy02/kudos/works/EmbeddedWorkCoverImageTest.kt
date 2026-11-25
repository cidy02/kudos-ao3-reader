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

    @Test
    fun readEntryBoundedIgnoresTheDeclaredSizeAndStopsAtTheCap() {
        val payload = ByteArray(5_000) { (it % 251).toByte() }
        val epub = tempFolder.newFile("bounded.zip")
        ZipOutputStream(epub.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry("data.bin"))
            zip.write(payload)
            zip.closeEntry()
        }
        java.util.zip.ZipFile(epub).use { zip ->
            val real = zip.getEntry("data.bin")
            // getInputStream looks the entry up by name, so these copies model unknown (-1) and spoofed sizes.
            fun withSize(size: Long) = if (size < 0) ZipEntry("data.bin") else ZipEntry(real).apply { this.size = size }
            for (declared in listOf(-1L, 0L, 1L, 4_999L, 5_000L)) {
                assertArrayEquals(
                    "declared $declared",
                    payload,
                    EmbeddedWorkCoverImage.readEntryBounded(zip, withSize(declared), maxBytes = 5_000)
                )
            }
            // One byte over the cap fails whatever the entry claims; exactly at the cap is fine (checked above).
            assertNull(EmbeddedWorkCoverImage.readEntryBounded(zip, withSize(-1L), maxBytes = 4_999))
            assertNull(EmbeddedWorkCoverImage.readEntryBounded(zip, withSize(10L), maxBytes = 4_999))
            // A declared size over the cap is rejected without reading.
            assertNull(EmbeddedWorkCoverImage.readEntryBounded(zip, withSize(5_001L), maxBytes = 5_000))
        }
    }

    @Test
    fun anImageThatLiesAboutItsSizeAndOverrunsTheCapFallsBackToChapterOne() {
        val frontArt = png(320, Color.RED)
        val chapterArt = png(400, Color.BLUE)
        val lyingFront = frontArt + ByteArray(EmbeddedWorkCoverImage.MAX_IMAGE_BYTES + 1_000_000)
        val epub = tempFolder.newFile("lying.epub")
        val entries = listOf(
            "mimetype" to "application/epub+zip".toByteArray(),
            "META-INF/container.xml" to """<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>""".toByteArray(),
            "OEBPS/content.opf" to opf("chapter.xhtml").toByteArray(),
            "OEBPS/nav.xhtml" to nav("""<nav epub:type="toc"><a href="preface.xhtml">Preface</a><a href="chapter.xhtml">Chapter 1</a></nav>"""),
            "OEBPS/preface.xhtml" to "<html><body><img src='front.png'/></body></html>".toByteArray(),
            "OEBPS/chapter.xhtml" to "<html><body><img src='chapter.png'/></body></html>".toByteArray(),
            "OEBPS/front.png" to lyingFront,
            "OEBPS/chapter.png" to chapterArt
        )
        ZipOutputStream(epub.outputStream()).use { zip ->
            for ((name, bytes) in entries) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        // Forge the front image's central-directory uncompressed size so it passes the declared-size check.
        val raw = epub.readBytes()
        val needle = "OEBPS/front.png".toByteArray()
        var patched = false
        var i = 0
        while (i <= raw.size - 46 - needle.size) {
            // Central directory header signature PK\u0001\u0002; name starts 46 bytes in.
            if (raw[i] == 0x50.toByte() && raw[i + 1] == 0x4b.toByte() && raw[i + 2] == 1.toByte() && raw[i + 3] == 2.toByte() &&
                raw.copyOfRange(i + 46, i + 46 + needle.size).contentEquals(needle)
            ) {
                for (b in 0 until 4) raw[i + 24 + b] = (if (b == 0) 1_000 and 0xFF else if (b == 1) 1_000 shr 8 else 0).toByte()
                patched = true
            }
            i += 1
        }
        assertTrue(patched)
        epub.writeBytes(raw)

        // Front matter wins only if its bytes really read: this one overruns the cap, so Chapter 1's art is used.
        assertArrayEquals(chapterArt, EmbeddedWorkCoverImage.data(epub))
    }

    @Test
    fun tocHrefsMatchSpineDocumentsWhoseNamesContainPercentAndPlus() {
        val art = png(320, Color.GREEN)
        // The document's own name is "a%20b+c.xhtml" (OPF href "a%2520b+c.xhtml"); the nav says "a b+c.xhtml".
        val epub = zip(
            "percent-name.epub",
            "OEBPS/content.opf" to opf("a%2520b+c.xhtml"),
            "OEBPS/nav.xhtml" to nav("""<nav epub:type="toc"><a href="preface.xhtml">Preface</a><a href="a b+c.xhtml">Chapter 1</a></nav>"""),
            "OEBPS/preface.xhtml" to "<html><body><p>Preface</p></body></html>".toByteArray(),
            "OEBPS/a%20b+c.xhtml" to "<html><body><img src='art.png'/></body></html>".toByteArray(),
            "OEBPS/art.png" to art
        )
        assertArrayEquals(art, EmbeddedWorkCoverImage.data(epub))
        assertEquals("a b+c.xhtml", EmbeddedWorkCoverImage.percentDecode("a%20b+c.xhtml"))
        assertEquals("ch+1 a.xhtml", EmbeddedWorkCoverImage.percentDecode("ch+1%20a.xhtml"))
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
