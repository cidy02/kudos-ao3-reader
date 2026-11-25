package io.github.cidy02.kudos.works

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import io.github.cidy02.kudos.core.model.CoverArtPreference
import io.github.cidy02.kudos.core.model.CoverArtResolution
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CoverArtPreferenceAndExtractionTest {
    private val tempDir = Files.createTempDirectory("kudos-cover-art-test").toFile()

    @After
    fun tearDown() {
        tempDir.deleteRecursively()
    }

    @Test
    fun resolutionRuleCoversGlobalPerWorkUnknownAndMissingArtCases() {
        assertEquals("follow", CoverArtPreference.FOLLOW_RAW)
        assertNull(CoverArtPreference.resolved(null))
        assertNull(CoverArtPreference.resolved(""))
        assertNull(CoverArtPreference.resolved(CoverArtPreference.FOLLOW_RAW))
        assertNull(CoverArtPreference.resolved("sepia-photo"))
        assertNull(CoverArtPreference.resolved("EMBEDDED"))
        assertEquals(CoverArtPreference.Embedded, CoverArtPreference.resolved("embedded"))
        assertEquals(CoverArtPreference.Generated, CoverArtPreference.resolved("generated"))

        assertEquals(CoverArtPreference.FollowSettings, CoverArtPreference.fromStorage(null))
        assertEquals(CoverArtPreference.FollowSettings, CoverArtPreference.fromStorage(""))
        assertEquals(CoverArtPreference.FollowSettings, CoverArtPreference.fromStorage(CoverArtPreference.FOLLOW_RAW))
        assertEquals(CoverArtPreference.FollowSettings, CoverArtPreference.fromStorage("future-mode"))
        assertEquals(CoverArtPreference.FollowSettings, CoverArtPreference.fromStorage("EMBEDDED"))
        assertEquals(CoverArtPreference.Embedded, CoverArtPreference.fromStorage("embedded"))
        assertEquals(CoverArtPreference.Generated, CoverArtPreference.fromStorage("generated"))

        // Port of iOS CoverArtPreferenceTests.resolutionIsOverrideThenGlobalThenHasArt.
        for (global in listOf(true, false)) {
            assertFalse(CoverArtResolution.wantsEmbeddedArt(global, "generated"))
            assertTrue(CoverArtResolution.wantsEmbeddedArt(global, "embedded"))
            for (follows in listOf(null, CoverArtPreference.FOLLOW_RAW, "sepia-photo")) {
                assertEquals(global, CoverArtResolution.wantsEmbeddedArt(global, follows))
            }
            for (hasArt in listOf(true, false)) {
                assertFalse(CoverArtResolution.shouldUseEmbeddedArt(global, "generated", hasEmbeddedArt = hasArt))
                assertEquals(hasArt, CoverArtResolution.shouldUseEmbeddedArt(global, "embedded", hasEmbeddedArt = hasArt))
                for (follows in listOf(null, CoverArtPreference.FOLLOW_RAW, "sepia-photo")) {
                    assertEquals(
                        global && hasArt,
                        CoverArtResolution.shouldUseEmbeddedArt(global, follows, hasEmbeddedArt = hasArt)
                    )
                }
            }
        }

        assertEquals("Currently Work's Art", CoverArtResolution.followSettingsSummary(true))
        assertEquals("Currently Generated", CoverArtResolution.followSettingsSummary(false))
    }

    @Test
    fun acceptsAndPreferredMatchIosCoverArtBounds() {
        // Port of iOS GeneratedCoverRecipeTests.embeddedArtPrefersFrontMatterThenLargest.
        assertTrue(EmbeddedWorkCoverImage.accepts(320, 800))   // aspect 0.40
        assertTrue(EmbeddedWorkCoverImage.accepts(740, 400))   // aspect 1.85
        assertFalse(EmbeddedWorkCoverImage.accepts(320, 801))  // < 0.40
        assertFalse(EmbeddedWorkCoverImage.accepts(741, 400))  // > 1.85
        assertFalse(EmbeddedWorkCoverImage.accepts(319, 800))  // min < 320
        assertFalse(EmbeddedWorkCoverImage.accepts(800, 320))  // aspect 2.5
        assertFalse(EmbeddedWorkCoverImage.accepts(0, 500))
        assertFalse(EmbeddedWorkCoverImage.accepts(20_001, 20_000))

        val frontSmall = EmbeddedWorkCoverImage.Candidate(byteArrayOf(1), frontMatter = true, pixelArea = 500_000)
        val frontLarge = EmbeddedWorkCoverImage.Candidate(byteArrayOf(2), frontMatter = true, pixelArea = 1_000_000)
        val chapterHuge = EmbeddedWorkCoverImage.Candidate(byteArrayOf(3), frontMatter = false, pixelArea = 3_000_000)

        assertArrayEquals(
            frontSmall.data,
            EmbeddedWorkCoverImage.preferred(chapterHuge, frontSmall).data
        )
        assertArrayEquals(
            frontSmall.data,
            EmbeddedWorkCoverImage.preferred(frontSmall, chapterHuge).data
        )
        assertArrayEquals(
            frontLarge.data,
            EmbeddedWorkCoverImage.preferred(frontSmall, frontLarge).data
        )
    }

    @Test
    fun extractsFrontMatterCoverFromFixtureEpubDownsamplesAndFlattensAlpha() {
        val frontPng = pngBytes(320, 800, Color.TRANSPARENT)
        val chapterPng = pngBytes(400, 800, Color.BLUE)
        val epub = writeZip(
            File(tempDir, "front-matter.epub"),
            mapOf(
                "META-INF/container.xml" to containerXml("OEBPS/content.opf"),
                "OEBPS/content.opf" to opfXml(
                    manifestItems = listOf(
                        """<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>""",
                        """<item id="front" href="front.xhtml" media-type="application/xhtml+xml"/>""",
                        """<item id="ch1" href="chapter.xhtml" media-type="application/xhtml+xml"/>""",
                        """<item id="img1" href="front%2520.png" media-type="image/png"/>""",
                        """<item id="img2" href="chapter.png" media-type="image/png"/>"""
                    ),
                    spineIds = listOf("front", "ch1")
                ),
                "OEBPS/toc.ncx" to ncxXml(
                    listOf("Preface" to "front.xhtml", "Chapter 1" to "chapter.xhtml")
                ),
                "OEBPS/front.xhtml" to xhtmlWithBody("""<img src="front%2520.png" alt="Cover"/>"""),
                "OEBPS/chapter.xhtml" to xhtmlWithBody("""<img src="chapter.png" alt="Scene"/>"""),
                "OEBPS/front%20.png" to frontPng,
                "OEBPS/chapter.png" to chapterPng
            )
        )

        val extracted = EmbeddedWorkCoverImage.data(epub)
        assertNotNull(extracted)
        assertArrayEquals(frontPng, extracted)

        val thumbnailBytes = checkNotNull(EmbeddedWorkCoverImage.downsampledJPEG(extracted))
        val decoded = checkNotNull(BitmapFactory.decodeByteArray(thumbnailBytes, 0, thumbnailBytes.size))
        assertTrue(
            "expected max dimension <= 600, got ${decoded.width}x${decoded.height}",
            maxOf(decoded.width, decoded.height) <= EmbeddedWorkCoverImage.MAX_THUMBNAIL_PX
        )
        // Transparent pixels flatten onto white before JPEG encoding (iOS EPUBCoverExport parity).
        val corner = decoded.getPixel(0, 0)
        assertTrue(Color.red(corner) >= 245)
        assertTrue(Color.green(corner) >= 245)
        assertTrue(Color.blue(corner) >= 245)
    }

    @Test
    fun fallsBackToFirstChapterAndIgnoresRemoteTraversalSmallAndLaterChapterImages() {
        val tinyPng = pngBytes(120, 120, Color.RED)
        val chapter1Png = pngBytes(400, 600, Color.GREEN)
        val chapter2Png = pngBytes(800, 1000, Color.YELLOW)
        val epub = writeZip(
            File(tempDir, "chapter-fallback.epub"),
            mapOf(
                "META-INF/container.xml" to containerXml("OEBPS/content.opf"),
                "OEBPS/content.opf" to opfXml(
                    manifestItems = listOf(
                        """<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>""",
                        """<item id="front" href="front.xhtml" media-type="application/xhtml+xml"/>""",
                        """<item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>""",
                        """<item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>"""
                    ),
                    spineIds = listOf("front", "ch1", "ch2")
                ),
                "OEBPS/toc.ncx" to ncxXml(
                    listOf(
                        "Preface" to "front.xhtml",
                        "Chapter 1" to "chapter1.xhtml",
                        "Chapter 2" to "chapter2.xhtml"
                    )
                ),
                "OEBPS/front.xhtml" to xhtmlWithBody(
                    """
                    <img src="https://example.com/remote.jpg"/>
                    <img src="//example.com/protocol-relative.jpg"/>
                    <img src="../../outside.png"/>
                    <img src="tiny.png"/>
                    """.trimIndent()
                ),
                "OEBPS/chapter1.xhtml" to xhtmlWithBody("""<img src="ch1.png"/>"""),
                "OEBPS/chapter2.xhtml" to xhtmlWithBody("""<img src="ch2.png"/>"""),
                "OEBPS/tiny.png" to tinyPng,
                "OEBPS/ch1.png" to chapter1Png,
                "OEBPS/ch2.png" to chapter2Png
            )
        )

        val extracted = EmbeddedWorkCoverImage.data(epub)
        assertNotNull(extracted)
        assertArrayEquals(chapter1Png, extracted)
    }

    @Test
    fun loaderCoalescesScansPersistsEmptySentinelAndInvalidatesOnRevisionChange() = runBlocking {
        val cacheDir = File(tempDir, "cache")
        val epub = File(tempDir, "book.epub").apply {
            writeBytes(byteArrayOf(1, 2, 3))
            setLastModified(1_700_000_000_000L)
        }
        val scanCalls = AtomicInteger(0)
        var nextScanResult: ByteArray? = null
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)

        val loader = EmbeddedCoverArtLoader(
            directory = cacheDir,
            scan = {
                if (scanCalls.incrementAndGet() == 1) {
                    started.countDown()
                    release.await(5, TimeUnit.SECONDS)
                }
                nextScanResult
            }
        )

        val first = async(Dispatchers.Default) { loader.load("work-1", epub) }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        val second = async(Dispatchers.Default) { loader.load("work-1", epub) }
        kotlinx.coroutines.delay(25)
        release.countDown()

        assertNull(first.await())
        assertNull(second.await())
        assertEquals(1, scanCalls.get())

        // In-memory negative cache hit avoids rescanning.
        assertNotNull(loader.peekCached(epub))
        assertNull(loader.peekCached(epub)?.bitmap)
        assertNull(loader.load("work-1", epub))
        assertEquals(1, scanCalls.get())

        // Fresh loader reads the .empty disk sentinel without rescanning.
        val reloaded = EmbeddedCoverArtLoader(
            directory = cacheDir,
            scan = {
                scanCalls.incrementAndGet()
                nextScanResult
            }
        )
        assertNull(reloaded.load("work-1", epub))
        assertEquals(1, scanCalls.get())

        // Bumping file revision invalidates cache, rescans, writes .jpg, and prunes old .empty.
        nextScanResult = pngBytes(400, 600, Color.MAGENTA)
        epub.setLastModified(1_700_000_060_000L)
        val bitmap = reloaded.load("work-1", epub)
        assertNotNull(bitmap)
        assertEquals(2, scanCalls.get())
        val files = cacheDir.listFiles().orEmpty()
        assertEquals(1, files.size)
        assertTrue(files.single().name.endsWith(".jpg"))
        assertNotNull(reloaded.peekCached(epub)?.bitmap)
    }

    @Test
    fun cancelledQueuedScanDoesNotRun() = runBlocking {
        val cacheDir = File(tempDir, "cancel-cache")
        val epub1 = File(tempDir, "one.epub").apply {
            writeBytes(byteArrayOf(1))
            setLastModified(1_700_000_000_000L)
        }
        val epub2 = File(tempDir, "two.epub").apply {
            writeBytes(byteArrayOf(2))
            setLastModified(1_700_000_000_000L)
        }
        val firstStarted = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val scanCount = AtomicInteger(0)

        val loader = EmbeddedCoverArtLoader(
            directory = cacheDir,
            scan = {
                if (scanCount.incrementAndGet() == 1) {
                    firstStarted.countDown()
                    releaseFirst.await(5, TimeUnit.SECONDS)
                }
                null
            }
        )

        val job1 = launch(Dispatchers.Default) { loader.load("work-1", epub1) }
        assertTrue(firstStarted.await(5, TimeUnit.SECONDS))
        val job2 = launch(Dispatchers.Default) { loader.load("work-2", epub2) }
        // Let job2 enqueue behind job1, then cancel it before job1 releases.
        kotlinx.coroutines.delay(50)
        job2.cancelAndJoin()
        releaseFirst.countDown()
        job1.join()

        // Allow tail job to observe abandoned waiter and exit.
        kotlinx.coroutines.delay(50)
        assertEquals(1, scanCount.get())
    }

    private fun pngBytes(width: Int, height: Int, color: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawColor(color)
        val out = ByteArrayOutputStream()
        assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, out))
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun writeZip(destination: File, entries: Map<String, Any>): File {
        ZipOutputStream(destination.outputStream()).use { zip ->
            entries.forEach { (name, payload) ->
                zip.putNextEntry(ZipEntry(name))
                when (payload) {
                    is ByteArray -> zip.write(payload)
                    is String -> zip.write(payload.toByteArray(Charsets.UTF_8))
                    else -> error("Unsupported payload for $name")
                }
                zip.closeEntry()
            }
        }
        return destination
    }

    private fun containerXml(opfPath: String): String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles>
                <rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/>
            </rootfiles>
        </container>
    """.trimIndent()

    private fun opfXml(manifestItems: List<String>, spineIds: List<String>): String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Fixture</dc:title>
            </metadata>
            <manifest>
                ${manifestItems.joinToString("\n")}
            </manifest>
            <spine toc="ncx">
                ${spineIds.joinToString("\n") { """<itemref idref="$it"/>""" }}
            </spine>
        </package>
    """.trimIndent()

    private fun ncxXml(points: List<Pair<String, String>>): String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
            <navMap>
                ${points.mapIndexed { idx, (label, src) ->
                    """<navPoint id="np-${idx + 1}" playOrder="${idx + 1}">
                        <navLabel><text>$label</text></navLabel>
                        <content src="$src"/>
                    </navPoint>"""
                }.joinToString("\n")}
            </navMap>
        </ncx>
    """.trimIndent()

    private fun xhtmlWithBody(body: String): String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Page</title></head>
        <body>$body</body>
        </html>
    """.trimIndent()
}
