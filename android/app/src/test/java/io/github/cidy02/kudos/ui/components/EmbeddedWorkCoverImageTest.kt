package io.github.cidy02.kudos.ui.components

import java.awt.Color
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import javax.imageio.ImageIO
import kotlin.math.max
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class EmbeddedWorkCoverImageTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private val jvmCodec = object : EmbeddedImageCodec {
        override fun dimensions(bytes: ByteArray): Pair<Int, Int>? {
            val image = ImageIO.read(ByteArrayInputStream(bytes)) ?: return null
            return image.width to image.height
        }

        override fun downsampledJpeg(bytes: ByteArray, maxPixelSize: Int): ByteArray? {
            val src = ImageIO.read(ByteArrayInputStream(bytes)) ?: return null
            val longSide = max(src.width, src.height)
            val scaled = if (longSide > maxPixelSize) {
                val factor = maxPixelSize.toDouble() / longSide.toDouble()
                val w = max(1, (src.width * factor).roundToInt())
                val h = max(1, (src.height * factor).roundToInt())
                val dst = BufferedImage(w, h, BufferedImage.TYPE_INT_RGB)
                val g = dst.createGraphics()
                g.drawImage(src, 0, 0, w, h, null)
                g.dispose()
                dst
            } else {
                val dst = BufferedImage(src.width, src.height, BufferedImage.TYPE_INT_RGB)
                val g = dst.createGraphics()
                g.drawImage(src, 0, 0, null)
                g.dispose()
                dst
            }
            val out = ByteArrayOutputStream()
            return if (ImageIO.write(scaled, "jpg", out)) out.toByteArray() else null
        }
    }

    @Test
    fun embeddedArtPrefersFrontMatterThenLargest() {
        assertTrue(EmbeddedWorkCoverImage.accepts(width = 320, height = 800))
        assertTrue(EmbeddedWorkCoverImage.accepts(width = 740, height = 400))
        assertFalse(EmbeddedWorkCoverImage.accepts(width = 320, height = 801))
        assertFalse(EmbeddedWorkCoverImage.accepts(width = 741, height = 400))
        assertFalse(EmbeddedWorkCoverImage.accepts(width = 319, height = 800))
        assertFalse(EmbeddedWorkCoverImage.accepts(width = 800, height = 320))
        assertFalse(EmbeddedWorkCoverImage.accepts(width = 0, height = 500))

        val images = listOf(
            EmbeddedWorkCoverImage.Candidate(byteArrayOf(1), frontMatter = false, pixelArea = 3_000_000),
            EmbeddedWorkCoverImage.Candidate(byteArrayOf(2), frontMatter = true, pixelArea = 500_000),
            EmbeddedWorkCoverImage.Candidate(byteArrayOf(3), frontMatter = true, pixelArea = 1_000_000)
        )
        val chosen = images.fold(null as EmbeddedWorkCoverImage.Candidate?) { acc, candidate ->
            EmbeddedWorkCoverImage.preferred(acc, candidate)
        }
        assertArrayEquals(byteArrayOf(3), chosen?.data)
    }

    @Test
    fun embeddedArtScansFrontMatterInRealEpub() {
        fun png(width: Int, red: Int): ByteArray {
            val image = BufferedImage(width, 800, BufferedImage.TYPE_INT_RGB)
            val g = image.createGraphics()
            g.color = Color(red, 0, 0)
            g.fillRect(0, 0, width, 800)
            g.dispose()
            val out = ByteArrayOutputStream()
            assertTrue(ImageIO.write(image, "png", out))
            return out.toByteArray()
        }

        val front = png(width = 320, red = 255)
        val chapter = png(width = 400, red = 128)
        val container = """
            <?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
        """.trimIndent()
        val opf = """
            <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Art Test</dc:title>
            <dc:creator>Author</dc:creator><dc:language>en</dc:language></metadata>
            <manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="front" href="front.xhtml" media-type="application/xhtml+xml"/>
            <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
            <spine toc="ncx"><itemref idref="front"/><itemref idref="chapter"/></spine>
            </package>
        """.trimIndent()
        val toc = """
            <?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
            <navMap><navPoint id="front" playOrder="1"><navLabel><text>Preface</text></navLabel>
            <content src="front.xhtml"/></navPoint><navPoint id="chapter" playOrder="2">
            <navLabel><text>Chapter 1</text></navLabel><content src="chapter.xhtml"/></navPoint></navMap>
            </ncx>
        """.trimIndent()

        val epub = tempFolder.newFile("art-test.epub")
        ZipOutputStream(epub.outputStream()).use { zip ->
            fun addStored(name: String, bytes: ByteArray) {
                val entry = ZipEntry(name).apply {
                    method = ZipEntry.STORED
                    size = bytes.size.toLong()
                    compressedSize = bytes.size.toLong()
                    crc = CRC32().apply { update(bytes) }.value
                }
                zip.putNextEntry(entry)
                zip.write(bytes)
                zip.closeEntry()
            }
            addStored("mimetype", "application/epub+zip".toByteArray(StandardCharsets.UTF_8))
            addStored("META-INF/container.xml", container.toByteArray(StandardCharsets.UTF_8))
            addStored("OEBPS/content.opf", opf.toByteArray(StandardCharsets.UTF_8))
            addStored("OEBPS/toc.ncx", toc.toByteArray(StandardCharsets.UTF_8))
            addStored("OEBPS/front.xhtml", "<html><body><img src='front%2520.png'/></body></html>".toByteArray())
            addStored("OEBPS/chapter.xhtml", "<html><body><img src='chapter.png'/></body></html>".toByteArray())
            addStored("OEBPS/front%20.png", front)
            addStored("OEBPS/chapter.png", chapter)
            // Selective entry reads never extract unrelated entries.
            addStored("unrelated.bin", byteArrayOf(0, 1, 2, 3))
        }

        val extracted = EmbeddedWorkCoverImage.data(epub, imageCodec = jvmCodec)
        assertArrayEquals(front, extracted)
        val thumb = EmbeddedWorkCoverImage.downsampledJPEG(extracted, imageCodec = jvmCodec)
        assertNotNull(thumb)
        val decoded = ImageIO.read(ByteArrayInputStream(thumb))
        assertNotNull(decoded)
        assertTrue(max(decoded.width, decoded.height) <= 600)
    }

    @Test
    fun coverArtLoaderScansOneFileOnce() = runBlocking {
        val dir = tempFolder.newFolder("loader-once")
        val file = File(dir, "work.epub").apply { writeBytes(byteArrayOf(1)) }
        val workId = UUID.randomUUID().toString()
        val scans = AtomicInteger(0)
        val cacheDir = File(dir, "GeneratedCoverArt")

        val loader = GeneratedCoverArtLoader(
            directory = cacheDir,
            scan = {
                scans.incrementAndGet()
                Thread.sleep(30)
                null
            },
            downsample = { it },
            decode = { it }
        )

        val first = async { loader.image(workId, file) }
        val second = async { loader.image(workId, file) }
        assertNull(first.await())
        assertNull(second.await())
        assertEquals(1, scans.get())

        assertNull(loader.image(workId, file))
        assertEquals(1, scans.get())

        val restarted = GeneratedCoverArtLoader(
            directory = cacheDir,
            scan = {
                scans.incrementAndGet()
                null
            },
            downsample = { it },
            decode = { it }
        )
        assertNull(restarted.image(workId, file))
        assertEquals(1, scans.get())

        assertTrue(file.setLastModified(file.lastModified() + 10_000L))
        assertNull(restarted.image(workId, file))
        assertEquals(2, scans.get())

        val cacheFiles = cacheDir.listFiles().orEmpty()
        assertEquals(1, cacheFiles.size)
    }

    @Test
    fun cancelledQueuedCoverDoesNotScan() = runBlocking {
        val dir = tempFolder.newFolder("loader-cancel")
        val firstFile = File(dir, "first.epub").apply { writeBytes(byteArrayOf(1)) }
        val secondFile = File(dir, "second.epub").apply { writeBytes(byteArrayOf(2)) }
        val scans = AtomicInteger(0)
        val started = CountDownLatch(1)
        val gate = CountDownLatch(1)

        val loaderJob = SupervisorJob()
        val loader = GeneratedCoverArtLoader(
            directory = File(dir, "cache"),
            scan = { file ->
                scans.incrementAndGet()
                if (file == firstFile) {
                    started.countDown()
                    gate.await(5, TimeUnit.SECONDS)
                }
                null
            },
            downsample = { it },
            decode = { it },
            scope = CoroutineScope(loaderJob + Dispatchers.IO)
        )

        val first = launch(Dispatchers.IO) { loader.image(UUID.randomUUID().toString(), firstFile) }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        val second = launch(Dispatchers.IO) { loader.image(UUID.randomUUID().toString(), secondFile) }
        delay(50)
        second.cancelAndJoin()
        gate.countDown()
        first.join()
        loaderJob.children.toList().forEach { it.join() }
        assertEquals(1, scans.get())
    }
}
