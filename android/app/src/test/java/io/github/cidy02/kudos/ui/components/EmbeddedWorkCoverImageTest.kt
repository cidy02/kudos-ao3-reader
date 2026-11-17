package io.github.cidy02.kudos.ui.components

import java.awt.Color
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.util.Collections
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
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
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
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

    @Test
    fun coverArtFileStatRunsOffTheCallerThread() = runBlocking {
        val dir = tempFolder.newFolder("loader-stat")
        val statThreads = Collections.synchronizedList(mutableListOf<String>())
        val file = object : File(dir, "work.epub") {
            override fun isFile(): Boolean {
                statThreads.add(Thread.currentThread().name)
                return super.isFile()
            }

            override fun lastModified(): Long {
                statThreads.add(Thread.currentThread().name)
                return super.lastModified()
            }
        }
        file.writeBytes(byteArrayOf(1))
        val loader = GeneratedCoverArtLoader(
            directory = File(dir, "cache"),
            scan = { null },
            downsample = { it },
            decode = { it }
        )
        val caller = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "cover-caller") }
        val dispatcher = caller.asCoroutineDispatcher()
        try {
            withContext(dispatcher) {
                assertNull(loader.image(UUID.randomUUID().toString(), file))
            }
        } finally {
            caller.shutdown()
        }
        assertTrue(statThreads.isNotEmpty())
        assertTrue(statThreads.none { it == "cover-caller" })
    }

    @Test
    fun jpegQualityMatchesIosAndUnknownImageSizeIsSkipped() {
        assertEquals(100, EmbeddedWorkCoverImage.JPEG_QUALITY)
        assertTrue(EmbeddedWorkCoverImage.imageEntrySkipped(-1L))
        assertTrue(EmbeddedWorkCoverImage.imageEntrySkipped(20_000_001L))
        assertFalse(EmbeddedWorkCoverImage.imageEntrySkipped(20_000_000L))
        assertFalse(EmbeddedWorkCoverImage.imageEntrySkipped(32_000L))

        val art = solidPng(width = 320, red = 70)
        val epub = storedZip(
            "unknown-size.epub",
            listOf(
                "mimetype" to "application/epub+zip".toByteArray(StandardCharsets.UTF_8),
                "META-INF/container.xml" to containerXml("OEBPS/content.opf"),
                "OEBPS/content.opf" to idTocOpf(),
                "OEBPS/nav.xhtml" to """
                    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
                    <nav epub:type="toc"><a href="chapter.xhtml">Chapter 1</a></nav></body></html>
                """.trimIndent().toByteArray(StandardCharsets.UTF_8),
                "OEBPS/preface.xhtml" to "<html><body><p>Preface</p></body></html>".toByteArray(),
                "OEBPS/chapter.xhtml" to "<html><body><img src='art.png'/></body></html>".toByteArray(),
                "OEBPS/art.png" to art
            )
        )
        assertArrayEquals(art, EmbeddedWorkCoverImage.data(epub, imageCodec = jvmCodec))
        assertNull(
            EmbeddedWorkCoverImage.data(
                epubFile = epub,
                imageCodec = jvmCodec,
                entrySize = { entry -> if (entry.name == "OEBPS/art.png") -1L else entry.size }
            )
        )
    }

    @Test
    fun percentDecodeKeepsSurrogatePairsIntactAndMatchesAstralTocHref() {
        assertEquals("📖 1.xhtml", EmbeddedWorkCoverImage.percentDecode("📖%201.xhtml"))
        assertEquals("📖+1.xhtml", EmbeddedWorkCoverImage.percentDecode("📖%2B1.xhtml"))
        assertEquals("📖 1.xhtml", EmbeddedWorkCoverImage.percentDecode("%F0%9F%93%96%201.xhtml"))
        assertEquals("📖%ZZ1.xhtml", EmbeddedWorkCoverImage.percentDecode("📖%ZZ1.xhtml"))
        assertEquals("📖%FF1.xhtml", EmbeddedWorkCoverImage.percentDecode("📖%FF1.xhtml"))

        val art = solidPng(width = 320, red = 55)
        val epub = storedZip(
            "astral-toc.epub",
            listOf(
                "mimetype" to "application/epub+zip".toByteArray(StandardCharsets.UTF_8),
                "META-INF/container.xml" to containerXml("OEBPS/content.opf"),
                "OEBPS/content.opf" to """
                    <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
                    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Astral</dc:title>
                    <dc:creator>Author</dc:creator><dc:language>en</dc:language></metadata>
                    <manifest>
                    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                    <item id="preface" href="preface.xhtml" media-type="application/xhtml+xml"/>
                    <item id="chapter" href="📖 1.xhtml" media-type="application/xhtml+xml"/>
                    </manifest>
                    <spine><itemref idref="preface"/><itemref idref="chapter"/></spine>
                    </package>
                """.trimIndent().toByteArray(StandardCharsets.UTF_8),
                "OEBPS/nav.xhtml" to """
                    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
                    <nav epub:type="toc">
                    <a href="preface.xhtml">Preface</a>
                    <a href="📖%201.xhtml">Chapter 1</a>
                    </nav></body></html>
                """.trimIndent().toByteArray(StandardCharsets.UTF_8),
                "OEBPS/preface.xhtml" to "<html><body><p>Preface</p></body></html>".toByteArray(),
                "OEBPS/📖 1.xhtml" to "<html><body><img src='art.png'/></body></html>".toByteArray(),
                "OEBPS/art.png" to art
            )
        )
        assertArrayEquals(art, EmbeddedWorkCoverImage.data(epub, imageCodec = jvmCodec))
    }

    @Test
    fun tocHrefPercentDecodesPlusWithoutTreatingPlusAsSpace() {
        val art = solidPng(width = 320, red = 40)
        val epub = storedZip(
            "plus.epub",
            listOf(
                "mimetype" to "application/epub+zip".toByteArray(StandardCharsets.UTF_8),
                "META-INF/container.xml" to containerXml("OEBPS/content.opf"),
                "OEBPS/content.opf" to plusOpf(),
                "OEBPS/nav.xhtml" to """
                    <html xmlns="http://www.w3.org/1999/xhtml"><body>
                    <nav epub:type="toc">
                    <a href="preface.xhtml">Preface</a>
                    <a href="ch%2B1.xhtml">Chapter 1</a>
                    </nav></body></html>
                """.trimIndent().toByteArray(StandardCharsets.UTF_8),
                "OEBPS/preface.xhtml" to "<html><body><p>Preface</p></body></html>".toByteArray(),
                "OEBPS/ch+1.xhtml" to "<html><body><img src='art.png'/></body></html>".toByteArray(),
                "OEBPS/art.png" to art
            )
        )
        assertArrayEquals(art, EmbeddedWorkCoverImage.data(epub, imageCodec = jvmCodec))
    }

    @Test
    fun navIdentifiedByIdTocIsUsedWhenItIsNotFirst() {
        val art = solidPng(width = 400, red = 90)
        val epub = storedZip(
            "id-toc.epub",
            listOf(
                "mimetype" to "application/epub+zip".toByteArray(StandardCharsets.UTF_8),
                "META-INF/container.xml" to containerXml("OEBPS/content.opf"),
                "OEBPS/content.opf" to idTocOpf(),
                "OEBPS/nav.xhtml" to """
                    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
                    <nav epub:type="landmarks"><a href="preface.xhtml">Landmarks</a></nav>
                    <nav id="toc">
                    <a href="preface.xhtml">Preface</a>
                    <a href="chapter.xhtml">Chapter 1</a>
                    </nav></body></html>
                """.trimIndent().toByteArray(StandardCharsets.UTF_8),
                "OEBPS/preface.xhtml" to "<html><body><p>Preface</p></body></html>".toByteArray(),
                "OEBPS/chapter.xhtml" to "<html><body><img src='art.png'/></body></html>".toByteArray(),
                "OEBPS/art.png" to art
            )
        )
        assertArrayEquals(art, EmbeddedWorkCoverImage.data(epub, imageCodec = jvmCodec))
    }

    private fun solidPng(width: Int, red: Int): ByteArray {
        val image = BufferedImage(width, 800, BufferedImage.TYPE_INT_RGB)
        val graphics = image.createGraphics()
        graphics.color = Color(red, 0, 0)
        graphics.fillRect(0, 0, width, 800)
        graphics.dispose()
        val out = ByteArrayOutputStream()
        assertTrue(ImageIO.write(image, "png", out))
        return out.toByteArray()
    }

    private fun containerXml(opfPath: String): ByteArray = """
        <?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
    """.trimIndent().toByteArray(StandardCharsets.UTF_8)

    private fun plusOpf(): ByteArray = """
        <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Plus</dc:title>
        <dc:creator>Author</dc:creator><dc:language>en</dc:language></metadata>
        <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="preface" href="preface.xhtml" media-type="application/xhtml+xml"/>
        <item id="chapter" href="ch+1.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine><itemref idref="preface"/><itemref idref="chapter"/></spine>
        </package>
    """.trimIndent().toByteArray(StandardCharsets.UTF_8)

    private fun idTocOpf(): ByteArray = """
        <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Id Toc</dc:title>
        <dc:creator>Author</dc:creator><dc:language>en</dc:language></metadata>
        <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="preface" href="preface.xhtml" media-type="application/xhtml+xml"/>
        <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine><itemref idref="preface"/><itemref idref="chapter"/></spine>
        </package>
    """.trimIndent().toByteArray(StandardCharsets.UTF_8)

    private fun storedZip(name: String, entries: List<Pair<String, ByteArray>>): File {
        val epub = tempFolder.newFile(name)
        ZipOutputStream(epub.outputStream()).use { zip ->
            for ((entryName, bytes) in entries) {
                val entry = ZipEntry(entryName).apply {
                    method = ZipEntry.STORED
                    size = bytes.size.toLong()
                    compressedSize = bytes.size.toLong()
                    crc = CRC32().apply { update(bytes) }.value
                }
                zip.putNextEntry(entry)
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        return epub
    }
}
