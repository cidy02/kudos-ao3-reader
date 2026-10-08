package io.github.cidy02.kudos.library

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.works.*
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.File
import java.nio.file.Paths
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReadingQueueRepositorySeriesTest {
    private lateinit var database: KudosDatabase
    private lateinit var files: WorkFileStore
    private lateinit var works: WorkRepository
    private lateinit var repository: ReadingQueueRepository
    private val backgroundEnqueues = mutableListOf<DownloadQueueItem>()

    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        files = WorkFileStore(Paths.get(context.cacheDir.absolutePath, "series-${System.nanoTime()}"))
        works = WorkRepository(database, files)
        repository = ReadingQueueRepository(database, epubOnDisk = files::workEpubExists,
            enqueueDownloads = { backgroundEnqueues += it })
    }
    @After fun tearDown() { database.close() }

    private fun summary(id: Long) = AO3WorkSummary(id, "Work $id", listOf("Author"), emptyList(), "",
        emptyList(), emptyList())

    private fun fixture(name: String): String = listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures",
        "android/app/src/debug/assets/fixtures").map { File(it, "$name.html") }.first { it.isFile }.readText()

    private fun importer(client: AO3Client): WorkImporter {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return WorkImporter(works, AO3WorkMetadataRepository(client), AO3EpubDownloader(client), files, context.cacheDir)
    }

    /** Uses the real coordinator with a virtual clock, not a fake zero-pause client. */
    private class Client(now: () -> Long) : AO3Client {
        val reads = mutableListOf<Pair<String, Long>>()
        val failures = mutableMapOf<Long, AO3Error>()
        val pages = mutableMapOf<String, String>()
        private val clock = now
        private val coordinator = AO3RequestCoordinator(AO3NetworkConfig(), AO3Clock(now), AO3Delay { delay(it) })
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
            coordinator.coordinate {
                reads += url to clock()
                val html = pages[url] ?: return@coordinate AO3Result.Failure(AO3Error.Forbidden)
                AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
            }
        override suspend fun getBytes(url: String, headers: Map<String, String>): AO3Result<AO3BinaryResponse> =
            coordinator.coordinate {
                reads += url to clock()
                val id = url.substringAfter("/downloads/").substringBefore('/').toLong()
                failures[id]?.let { return@coordinate AO3Result.Failure(it) }
                AO3Result.Success(AO3BinaryResponse(url, 200, mapOf("Content-Type" to listOf("application/epub+zip")),
                    EpubBuilder.buildEpub("Work $id", "<p>A complete local chapter.</p>")))
            }
    }

    @Test fun sequentialDownloadsAreAwaitedPacedAndKeepEveryMembership() = runTest {
        val client = Client { testScheduler.currentTime }
        val result = repository.preserveSeries(listOf(summary(1), summary(2), summary(3)), null, importer(client))
        assertEquals(3, result.preserved)
        assertEquals(listOf(0L, 2000L, 4000L), client.reads.map { it.second })
        assertTrue(client.reads.all { it.first.contains("/downloads/") }) // no work-page read ahead
        assertTrue(backgroundEnqueues.isEmpty())
        val queue = repository.ensureSavedForLaterQueue()
        val saved = repository.listWorks(queue.id)
        assertEquals(3, saved.size)
        for (item in saved) {
            val work = item.work!!
            assertFalse(work.isSaved) // queue-only, not a new Library keep flag
            assertTrue(files.workEpubExists(work.id))
            assertEquals("preserved", work.epubPreservationStatusRaw)
            assertNotNull(work.lastPreservationAttemptAt)
        }
    }

    @Test fun heldAndUnavailableCopiesSkipReadsAndMissingMembershipsAreAdded() = runTest {
        val held = works.upsert(SavedWork(title = "Held", author = "Author", sourceUrl = summary(1).workUrl,
            hasEpub = true, epubPreservationStatusRaw = "preserved", isSaved = true, isFavorite = true, isFinished = true, readiumLocator = "kept locator"))
        files.writeWorkEpub(held.id, EpubBuilder.buildEpub("Held", "<p>Original.</p>"))
        // Re-read: the stored row keeps milliseconds, the object handed back keeps more.
        val unavailable = works.getWork(works.upsert(SavedWork(title = "Unavailable", author = "Author",
            sourceUrl = summary(2).workUrl, ao3Unavailable = true, isSaved = true)).id)!!
        val client = Client { testScheduler.currentTime }
        val result = repository.preserveSeries(listOf(summary(1), summary(2), summary(3).copy(isRestricted = true)), null, importer(client))
        assertEquals(1, result.alreadyPreserved)
        assertEquals(1, result.unavailable)
        assertEquals(1, result.skipped)
        assertTrue(client.reads.isEmpty())
        assertTrue(repository.isInSavedForLater(held.id))
        val fresh = works.getWork(held.id)!!
        assertTrue(fresh.isSaved && fresh.isFavorite && fresh.isFinished)
        assertEquals("kept locator", fresh.readiumLocator)
        assertTrue(files.workEpubExists(held.id))
        assertEquals(unavailable, works.getWork(unavailable.id))
        assertTrue(backgroundEnqueues.isEmpty())
    }

    @Test fun explicitSeriesTargetsOnlyTheSelectedQueues() = runTest {
        val first = repository.createQueue("First")
        val second = repository.createQueue("Second")
        val unselected = repository.createQueue("Unselected")
        val client = Client { testScheduler.currentTime }
        val result = repository.preserveSeries(listOf(summary(1)), listOf(first, second), importer(client))
        assertEquals(1, result.preserved)
        assertEquals(1, repository.listWorks(first.id).size)
        assertEquals(1, repository.listWorks(second.id).size)
        assertTrue(repository.listWorks(unselected.id).isEmpty())
        assertTrue(repository.listWorks(repository.ensureSavedForLaterQueue().id).isEmpty())
        assertTrue(backgroundEnqueues.isEmpty())
    }

    @Test fun failureInTheMiddleKeepsItsRecordAndContinuesAfterThePause() = runTest {
        val client = Client { testScheduler.currentTime }
        client.failures[2] = AO3Error.Forbidden
        val result = repository.preserveSeries((1L..3L).map(::summary), null, importer(client))
        assertEquals(2, result.preserved)
        assertEquals(1, result.failed)
        assertEquals(listOf(0L, 2000L, 4000L), client.reads.map { it.second })
        val members = repository.listWorks(repository.ensureSavedForLaterQueue().id)
        assertEquals(3, members.size)
        val failed = members.single { it.work!!.sourceUrl == summary(2).workUrl }.work!!
        assertEquals("failed", failed.epubPreservationStatusRaw)
        assertNotNull(failed.lastPreservationAttemptAt)
        assertFalse(failed.isDeleted)
        assertTrue(backgroundEnqueues.isEmpty())
    }

    @Test fun cancelAfterSecondWorkKeepsTwoDownloadsAndDoesNotReadTheRest() = runTest {
        val client = Client { testScheduler.currentTime }
        var result: SeriesPreservationResult? = null
        var task: Job? = null
        task = launch {
            result = repository.preserveSeries((1L..4L).map(::summary), null, importer(client), progress = {
                if (it.preserved == 2) task!!.cancel()
            })
        }
        task!!.join()
        assertEquals(2, result!!.preserved)
        assertEquals(2, result!!.cancelled)
        assertEquals(2, client.reads.size)
        assertEquals(listOf(0L, 2000L), client.reads.map { it.second })
        val members = repository.listWorks(repository.ensureSavedForLaterQueue().id)
        assertEquals(2, members.size)
        for (item in members) assertTrue(files.workEpubExists(item.work!!.id))
        assertTrue(backgroundEnqueues.isEmpty())
    }

    @Test fun cancellationDuringAnEpubKeepsTheNewMembershipAndAttemptStamp() = runTest {
        val entered = kotlinx.coroutines.CompletableDeferred<Unit>()
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                throw AssertionError("Read a work page ahead of its EPUB")
            override suspend fun getBytes(url: String, headers: Map<String, String>): AO3Result<AO3BinaryResponse> {
                entered.complete(Unit)
                kotlinx.coroutines.awaitCancellation()
            }
        }
        var result: SeriesPreservationResult? = null
        val task = launch { result = repository.preserveSeries(listOf(summary(1)), null, importer(client)) }
        entered.await()
        task.cancel(); task.join()
        assertEquals(1, result!!.cancelled)
        val work = repository.listWorks(repository.ensureSavedForLaterQueue().id).single().work!!
        assertFalse(work.isDeleted)
        assertEquals("queued", work.epubPreservationStatusRaw)
        assertNotNull(work.lastPreservationAttemptAt)
        assertTrue(backgroundEnqueues.isEmpty())
    }

    @Test fun aRestrictedWorkWithItsLocalCopyCanJoinQueuesWithoutARead() = runTest {
        val held = works.upsert(SavedWork(title = "Held restricted", author = "Author", sourceUrl = summary(1).workUrl,
            hasEpub = true, isSaved = true))
        files.writeWorkEpub(held.id, EpubBuilder.buildEpub("Held restricted", "<p>Original.</p>"))
        val client = Client { testScheduler.currentTime }
        val result = repository.preserveSeries(listOf(summary(1).copy(isRestricted = true)), null, importer(client))
        assertEquals(1, result.preserved)
        assertTrue(client.reads.isEmpty())
        assertTrue(repository.isInSavedForLater(held.id))
        assertTrue(files.workEpubExists(held.id))
    }

    @Test fun completePreviewIsReusedWithoutASecondSeriesRead() = runTest {
        val url = "https://archiveofourown.org/series/999"
        val client = Client { testScheduler.currentTime }
        client.pages[url] = fixture("ao3_demo_series")
        val series = AO3SeriesRepository(client)
        val preview = (series.seriesPage(url) as AO3Result.Success).value
        val prompt = SeriesPreservationPrompt(preview, 4)
        assertTrue(prompt.shouldAutoPreserve(true))
        val result = repository.preserveSeries(prompt.preview!!.works, null, importer(client))
        assertEquals(3, result.preserved) // restricted entry is never requested
        assertEquals(1, result.skipped)
        assertEquals(1, client.reads.count { it.first == url })
        assertEquals(600L, client.reads[1].second) // preview→first EPUB obeys coordinator
        assertEquals(listOf(600L, 2600L, 4600L), client.reads.drop(1).map { it.second })
    }

    @Test fun multiPagePreviewDoesNotReadAheadAndExplicitChoiceCrawlsInOrder() = runTest {
        val url = "https://archiveofourown.org/series/1000"
        val client = Client { testScheduler.currentTime }
        for (page in 1..2) client.pages[if (page == 1) url else "$url?page=2"] =
            fixture("ao3_demo_series_two_pages_$page")
        val series = AO3SeriesRepository(client)
        val preview = (series.seriesPage(url) as AO3Result.Success).value
        assertFalse(SeriesPreservationPrompt(preview, 25).shouldAutoPreserve(true))
        assertEquals(1, client.reads.size)
        val result = repository.preserveSeries(url, null, series, importer(client))
        assertEquals(6, result.preserved)
        assertEquals(listOf(url, url, "$url?page=2"), client.reads.take(3).map { it.first })
        assertEquals(listOf(0L, 600L, 1200L), client.reads.take(3).map { it.second })
        assertEquals(1800L, client.reads[3].second)
        assertEquals(9, client.reads.size)
    }

    @Test fun failedSizeReadIsOneAttemptAndNoAutomaticCrawlOrDownload() = runTest {
        val client = Client { testScheduler.currentTime }
        val preview = AO3SeriesRepository(client).seriesPage("https://archiveofourown.org/series/1001")
        assertTrue(preview is AO3Result.Failure)
        val prompt = SeriesPreservationPrompt(null, 25, previewFailed = true)
        assertFalse(prompt.shouldAutoPreserve(true))
        assertEquals(1, client.reads.size)
        assertTrue(prompt.message.startsWith("Kudos couldn't check"))
        assertTrue(repository.listWorks(repository.ensureSavedForLaterQueue().id).isEmpty())
    }

    @Test fun emptyTargetsSkipAndNotFoundKeepsTheLastCopy() = runTest {
        val client = Client { testScheduler.currentTime }
        assertEquals(1, repository.preserveSeries(listOf(summary(1)), emptyList(), importer(client)).skipped)
        assertTrue(client.reads.isEmpty())
        client.failures[2] = AO3Error.NotFound
        val result = repository.preserveSeries(listOf(summary(2)), null, importer(client))
        assertEquals(1, result.unavailable)
        val work = repository.listWorks(repository.ensureSavedForLaterQueue().id).single().work!!
        assertTrue(work.ao3Unavailable)
        assertFalse(work.isDeleted)
        assertNotNull(work.lastPreservationAttemptAt)
    }
}
