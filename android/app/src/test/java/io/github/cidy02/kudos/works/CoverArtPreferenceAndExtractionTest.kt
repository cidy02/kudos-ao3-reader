package io.github.cidy02.kudos.works

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import io.github.cidy02.kudos.account.coverFace
import io.github.cidy02.kudos.backup.BackupMergeService
import io.github.cidy02.kudos.core.model.AppSettings
import io.github.cidy02.kudos.core.model.CoverArtPreference
import io.github.cidy02.kudos.core.model.CoverArtResolution
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
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
import org.junit.Assert.assertNotSame
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
    fun theMergeTableDecidesEveryRow() {
        // Port of iOS CoverArtPreferenceTests.theMergeTableDecidesEveryRow.
        val now = Instant.ofEpochSecond(100_000)
        val t1 = Instant.ofEpochSecond(1_000)
        val t2 = Instant.ofEpochSecond(2_000)
        fun wins(lr: String?, ls: Instant?, ir: String, istamp: Instant?): Boolean =
            CoverArtResolution.incomingWins(
                localRaw = lr,
                localStamp = ls,
                incomingRaw = ir,
                incomingStamp = istamp,
                now = now
            )

        assertTrue(wins("generated", t1, "embedded", t2))            // stamped vs stamped: newer wins
        assertFalse(wins("generated", t2, "embedded", t1))
        assertTrue(wins("embedded", t1, "generated", t1))            // equal stamps: greater value wins, on both devices
        assertFalse(wins("generated", t1, "embedded", t1))
        assertFalse(wins("generated", t1, "embedded", null))         // stamped local beats unstamped incoming
        assertTrue(wins("generated", null, "embedded", t1))          // unstamped local loses to stamped incoming
        assertTrue(wins("embedded", null, "generated", null))        // unstamped vs unstamped: greater value
        assertFalse(wins("generated", null, "embedded", null))
        assertTrue(wins("embedded", null, "follow", null))           // an older unstamped archive can only
        assertFalse(wins("follow", null, "embedded", null))          // win by value, so both devices agree
        assertTrue(wins(null, null, "follow", null))                 // nil local takes any present value
        assertTrue(wins(null, null, "embedded", t1))
        // a far-future stamp is clamped to now + skew on both sides
        val far = now.plus(BackupMergeService.FUTURE_CLOCK_SKEW.multipliedBy(3))
        assertFalse(wins("generated", far, "embedded", far.plusSeconds(500))) // equal once clamped: "embedded" < "generated"
        assertTrue(wins("embedded", far, "generated", far.plusSeconds(500)))
    }

    @Test
    fun applyEditStepsByTwoMillisCapsAtMaxSkewAndHealsBeyondCap() {
        val now = Instant.parse("2026-11-24T12:00:00.000Z")
        val ceiling = now.plus(BackupMergeService.FUTURE_CLOCK_SKEW)

        val first = checkNotNull(
            CoverArtResolution.applyEdit(null, null, CoverArtPreference.Generated, now = now)
        )
        assertEquals("generated", first.raw)
        assertEquals(now, first.changedAt)

        // Rapid second edit at the same instant steps by 2 ms (clears ISO-8601 ms rounding).
        val second = checkNotNull(
            CoverArtResolution.applyEdit(first.raw, first.changedAt, CoverArtPreference.Embedded, now = now)
        )
        assertEquals("embedded", second.raw)
        assertEquals(now.plusMillis(2), second.changedAt)

        // A previous stamp just under the cap is capped at now + FUTURE_CLOCK_SKEW.
        val capped = checkNotNull(
            CoverArtResolution.applyEdit("embedded", ceiling.minusMillis(1), CoverArtPreference.Generated, now = now)
        )
        assertEquals(ceiling, capped.changedAt)

        // A stored stamp already beyond the cap counts as now on the next edit (heals a fast clock).
        val farFuture = now.plus(BackupMergeService.FUTURE_CLOCK_SKEW.multipliedBy(3))
        val healed = checkNotNull(
            CoverArtResolution.applyEdit("generated", farFuture, CoverArtPreference.Embedded, now = now)
        )
        assertEquals("embedded", healed.raw)
        assertEquals(now.plusMillis(2), healed.changedAt)
        assertFalse(healed.changedAt.isAfter(ceiling))
        assertTrue(healed.changedAt.isBefore(now.plusSeconds(60)))

        // Selecting what is already active writes nothing; unknown future value is preserved.
        assertNull(CoverArtResolution.applyEdit("embedded", now, CoverArtPreference.Embedded, now = now))
        assertNull(CoverArtResolution.applyEdit(null, null, CoverArtPreference.FollowSettings, now = now))
        assertNull(CoverArtResolution.applyEdit(CoverArtPreference.FOLLOW_RAW, now, CoverArtPreference.FollowSettings, now = now))
        assertNull(CoverArtResolution.applyEdit("sepia-photo", now, CoverArtPreference.FollowSettings, now = now))
    }

    @Test
    fun exportFollowsTheResolvedChoice() {
        // Port of iOS CoverArtPreferenceTests.exportFollowsTheResolvedChoice.
        val defaultGlobal = AppSettings().useEmbeddedCoverArt
        assertTrue(defaultGlobal)
        var work = SavedWork(title = "Export", author = "Writer")
        assertTrue(CoverArtResolution.wantsEmbeddedArt(work, defaultGlobal))
        assertFalse(CoverArtResolution.wantsEmbeddedArt(work, globalUseEmbeddedCoverArt = false))
        work = work.copy(coverArtPreferenceRaw = "embedded")
        assertTrue(CoverArtResolution.wantsEmbeddedArt(work, globalUseEmbeddedCoverArt = false))
        work = work.copy(coverArtPreferenceRaw = "generated")
        assertFalse(CoverArtResolution.wantsEmbeddedArt(work, globalUseEmbeddedCoverArt = true))
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
            scan = { _, _ ->
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
        assertEquals(false, loader.peekHasArt(epub))
        assertNull(loader.load("work-1", epub))
        assertFalse(loader.hasEmbeddedArt("work-1", epub))
        assertEquals(1, scanCalls.get())

        // Fresh loader reads the .empty disk sentinel without rescanning.
        val reloaded = EmbeddedCoverArtLoader(
            directory = cacheDir,
            scan = { _, _ ->
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
        assertEquals(true, reloaded.peekHasArt(epub))
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
            scan = { _, _ ->
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

    @Test
    fun loaderNeverStatsOnCallerThreadAndCachesHasEmbeddedArt() = runBlocking {
        val callerThread = Thread.currentThread()
        val cacheDir = File(tempDir, "no-main-stat-cache")
        val realEpub = File(tempDir, "guarded.epub").apply {
            writeBytes(byteArrayOf(7, 8, 9))
            setLastModified(1_700_000_000_000L)
        }
        val guardedFile = object : File(realEpub.absolutePath) {
            override fun isFile(): Boolean {
                assertNotSame("isFile() must not run on caller thread", callerThread, Thread.currentThread())
                return super.isFile()
            }

            override fun lastModified(): Long {
                assertNotSame("lastModified() must not run on caller thread", callerThread, Thread.currentThread())
                return super.lastModified()
            }

            override fun length(): Long {
                assertNotSame("length() must not run on caller thread", callerThread, Thread.currentThread())
                return super.length()
            }
        }

        val scanCalls = AtomicInteger(0)
        val png = pngBytes(400, 600, Color.CYAN)
        val loader = EmbeddedCoverArtLoader(
            directory = cacheDir,
            scan = { _, _ ->
                scanCalls.incrementAndGet()
                png
            },
            scanDispatcher = Dispatchers.IO
        )

        // Synchronous peeks do zero stat() calls on the caller thread.
        assertNull(loader.peekCached(guardedFile))
        assertNull(loader.peekHasArt(guardedFile))

        // Off-main-thread hasEmbeddedArt scans once and populates both caches.
        assertTrue(loader.hasEmbeddedArt("work-guarded", guardedFile))
        assertEquals(1, scanCalls.get())
        assertEquals(true, loader.peekHasArt(guardedFile))
        assertNotNull(loader.peekCached(guardedFile)?.bitmap)

        // Subsequent calls hit cache without rescanning or stat'ing on callerThread.
        assertTrue(loader.hasEmbeddedArt("work-guarded", guardedFile))
        assertNotNull(loader.load("work-guarded", guardedFile))
        assertEquals(1, scanCalls.get())
    }

    @Test
    fun cancellingActiveScanSignalsIsCancelledDoesNotWriteEmptyAndUnblocksQueue() = runBlocking {
        val cacheDir = File(tempDir, "active-cancel-cache")
        val epub1 = File(tempDir, "active-one.epub").apply {
            writeBytes(byteArrayOf(1))
            setLastModified(1_700_000_000_000L)
        }
        val epub2 = File(tempDir, "active-two.epub").apply {
            writeBytes(byteArrayOf(2))
            setLastModified(1_700_000_000_000L)
        }
        val firstScanStarted = CountDownLatch(1)
        val firstSawCancel = AtomicBoolean(false)
        val firstScanAttempts = AtomicInteger(0)
        val coverPng = pngBytes(400, 600, Color.BLUE)

        val loader = EmbeddedCoverArtLoader(
            directory = cacheDir,
            scan = { file, isCancelled ->
                if (file.name == epub1.name && firstScanAttempts.incrementAndGet() == 1) {
                    firstScanStarted.countDown()
                    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
                    while (!isCancelled() && System.nanoTime() < deadline) {
                        Thread.sleep(5)
                    }
                    if (isCancelled()) {
                        firstSawCancel.set(true)
                        null
                    } else {
                        coverPng
                    }
                } else {
                    coverPng
                }
            },
            scanDispatcher = Dispatchers.IO
        )

        val job1 = launch(Dispatchers.Default) { loader.load("work-1", epub1) }
        assertTrue(firstScanStarted.await(5, TimeUnit.SECONDS))
        val deferred2 = async(Dispatchers.Default) { loader.load("work-2", epub2) }

        // Cancel active scan for work-1; scan receives isCancelled() == true and unblocks work-2.
        job1.cancelAndJoin()
        assertNotNull(deferred2.await())
        assertTrue("Active scan should have observed cancellation", firstSawCancel.get())
        assertNull("Cancelled scan must not negative-cache work-1", loader.peekCached(epub1))
        assertNull("Cancelled scan must not cache hasArt=false for work-1", loader.peekHasArt(epub1))
        assertTrue(
            "Cancelled scan must not persist a .empty sentinel for work-1",
            cacheDir.listFiles().orEmpty().none { it.name.startsWith("work-1-") && it.name.endsWith(".empty") }
        )

        // Retrying work-1 now succeeds and extracts its real cover.
        assertNotNull(loader.load("work-1", epub1))
        assertEquals(2, firstScanAttempts.get())
    }

    @Test
    fun epub3NavSelectsTocTokenOverEarlierLandmarksAndRejectsSubstringMatches() {
        val frontPng = pngBytes(360, 540, Color.RED)
        val chapterPng = pngBytes(600, 900, Color.GREEN)
        val navXhtml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <body>
                <nav epub:type="landmarks">
                    <ol><li><a href="front.xhtml">Chapter 1</a></li></ol>
                </nav>
                <nav epub:type="notoc">
                    <ol><li><a href="front.xhtml">Chapter 1</a></li></ol>
                </nav>
                <nav epub:type="landmarks toc">
                    <ol>
                        <li><a href="front.xhtml">Preface</a></li>
                        <li><a href="chapter1.xhtml">Chapter 1</a></li>
                    </ol>
                </nav>
            </body>
            </html>
        """.trimIndent()
        val epub = writeZip(
            File(tempDir, "epub3-nav.epub"),
            mapOf(
                "META-INF/container.xml" to containerXml("OEBPS/content.opf"),
                "OEBPS/content.opf" to opfXml(
                    manifestItems = listOf(
                        """<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>""",
                        """<item id="front" href="front.xhtml" media-type="application/xhtml+xml"/>""",
                        """<item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>"""
                    ),
                    spineIds = listOf("front", "ch1")
                ),
                "OEBPS/nav.xhtml" to navXhtml,
                "OEBPS/front.xhtml" to xhtmlWithBody("""<img src="front.png"/>"""),
                "OEBPS/chapter1.xhtml" to xhtmlWithBody("""<img src="chapter1.png"/>"""),
                "OEBPS/front.png" to frontPng,
                "OEBPS/chapter1.png" to chapterPng
            )
        )

        // Because the multi-token `epub:type="landmarks toc"` nav is picked (not earlier landmarks/notoc),
        // front.xhtml is front matter and beats the larger chapter1.png.
        val extracted = EmbeddedWorkCoverImage.data(epub)
        assertNotNull(extracted)
        assertArrayEquals(frontPng, extracted)
    }

    @Test
    fun deduplicatesRepeatedHrefsCapsCandidateCountAndRespectsCancellation() {
        val smallPng = pngBytes(360, 500, Color.GRAY)
        val mediumPng = pngBytes(480, 720, Color.MAGENTA)
        val hugePng = pngBytes(800, 1000, Color.YELLOW)
        val repeatedTags = (1..200).joinToString("\n") { """<img src="dup.png"/>""" }
        val distinctTags = (1..70).joinToString("\n") { idx -> """<img src="img-$idx.png"/>""" }
        val entries = linkedMapOf<String, Any>(
            "META-INF/container.xml" to containerXml("OEBPS/content.opf"),
            "OEBPS/content.opf" to opfXml(
                manifestItems = listOf(
                    """<item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>"""
                ),
                spineIds = listOf("ch1")
            ),
            "OEBPS/ch1.xhtml" to xhtmlWithBody("$repeatedTags\n$distinctTags"),
            "OEBPS/dup.png" to smallPng
        )
        // dup.png repeats 200 times (deduplicated to 1 candidate), img-1 is medium (wins over dup.png
        // only when repeated hrefs are deduplicated), and img-70 is beyond MAX_IMAGE_CANDIDATES = 64.
        entries["OEBPS/img-1.png"] = mediumPng
        for (i in 2..69) {
            entries["OEBPS/img-$i.png"] = smallPng
        }
        entries["OEBPS/img-70.png"] = hugePng

        val epub = writeZip(File(tempDir, "capped.epub"), entries)

        // Cancelled immediately returns null.
        assertNull(EmbeddedWorkCoverImage.data(epub, isCancelled = { true }))

        // Deduplication lets img-1 beat dup.png; candidate cap (64) stops before img-70.
        val extracted = EmbeddedWorkCoverImage.data(epub)
        assertNotNull(extracted)
        assertArrayEquals(mediumPng, extracted)
    }

    @Test
    fun remoteSummaryCoverFaceSetsHasEpubFalse() {
        val summary = AO3WorkSummary(
            id = 12345L,
            title = "Remote Work",
            authors = listOf("Author"),
            fandoms = listOf("Fandom"),
            rating = "General Audiences",
            warnings = listOf("No Archive Warnings Apply"),
            categories = listOf("Gen")
        )
        assertFalse(summary.coverFace().hasEpub)
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
