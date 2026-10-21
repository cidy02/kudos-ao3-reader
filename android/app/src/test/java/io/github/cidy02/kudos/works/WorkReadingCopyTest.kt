package io.github.cidy02.kudos.works

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3BinaryResponse
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CancellationException
import io.github.cidy02.kudos.ui.components.RemoteWorkBulkActions
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkReadingCopyTest {
    private lateinit var database: KudosDatabase
    private lateinit var store: WorkFileStore
    private lateinit var works: WorkRepository
    private lateinit var importer: WorkImporter
    private var downloads = 0
    private var fail = false
    private var failOnDownload: Int? = null
    private var cancelOnDownload: Int? = null
    private var downloadError: AO3Error = AO3Error.NotFound
    private val bytes = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1)
    private val summary = AO3WorkSummary(id = 123, title = "Read me", authors = listOf("A"),
        fandoms = emptyList(), rating = "", warnings = emptyList(), categories = emptyList())

    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        store = WorkFileStore(Files.createTempDirectory("reading-copy"))
        works = WorkRepository(database, store)
        val fake = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                error("Read must not enrich a listing before obtaining its EPUB")
            override suspend fun getBytes(url: String, headers: Map<String, String>): AO3Result<AO3BinaryResponse> {
                downloads++
                if (downloads == cancelOnDownload) throw CancellationException("Leaving the list")
                return if (fail || downloads == failOnDownload) AO3Result.Failure(downloadError) else AO3Result.Success(
                    AO3BinaryResponse(url, 200, mapOf("Content-Type" to listOf("application/epub+zip")), bytes))
            }
        }
        importer = WorkImporter(works, AO3WorkMetadataRepository(fake), AO3EpubDownloader(fake), store, context.cacheDir)
    }

    @After fun tearDown() { database.close() }

    @Test fun bulkDownloadKeepsARealCopyAndReusesItOnRepeat() = runBlocking {
        assertTrue(RemoteWorkBulkActions.saveToLibrary(listOf(summary), importer).allSucceeded)
        val work = works.listSavedWorks().single()
        assertTrue(work.isDownloaded)
        assertTrue(store.workEpubExists(work.id))
        works.upsert(work.copy(readiumLocator = "position", isFavorite = true))
        assertTrue(RemoteWorkBulkActions.saveToLibrary(listOf(summary), importer).allSucceeded)
        assertEquals(1, downloads)
        assertEquals("position", works.getWork(work.id)!!.readiumLocator)
        assertTrue(works.getWork(work.id)!!.isFavorite)
    }

    @Test fun bulkDownloadReportsPartialFailureAndContinuesPastAMissingWork() = runBlocking {
        failOnDownload = 2
        val result = RemoteWorkBulkActions.saveToLibrary(
            listOf(summary, summary.copy(id = 124), summary.copy(id = 125)), importer)
        assertEquals(2, result.added)
        assertEquals(1, result.failed)
        assertFalse(result.allSucceeded)
        assertEquals(3, downloads)
        assertEquals(2, works.listSavedWorks().count { it.isDownloaded })
    }

    @Test fun bulkDownloadStopsAtASystemicFailureAndDoesNotKeepTheFailedCopy() = runBlocking {
        failOnDownload = 2
        downloadError = AO3Error.Validation("Blocked")
        val result = RemoteWorkBulkActions.saveToLibrary(
            listOf(summary, summary.copy(id = 124), summary.copy(id = 125)), importer)
        assertEquals(1, result.added)
        assertEquals(2, result.failed)
        assertEquals(2, downloads)
        assertEquals(1, works.listSavedWorks().count { it.isDownloaded })
    }

    @Test fun bulkDownloadPropagatesCancellationAndNeverRequestsTheNextWork() = runBlocking {
        cancelOnDownload = 2
        try {
            RemoteWorkBulkActions.saveToLibrary(
                listOf(summary, summary.copy(id = 124), summary.copy(id = 125)), importer)
            org.junit.Assert.fail("Cancellation must propagate")
        } catch (_: CancellationException) {
            assertEquals(2, downloads)
            assertEquals(1, works.listSavedWorks().count { it.isDownloaded })
        }
    }

    @Test fun membershipResolutionCreatesUnkeptRecordsWithoutAnyRequests() = runBlocking {
        var resolved = emptyList<SavedWork>()
        val result = RemoteWorkBulkActions.resolve(listOf(summary), importer) { resolved = it }
        assertTrue(result.allSucceeded)
        assertFalse(resolved.single().isSaved)
        assertFalse(resolved.single().hasEpub)
        assertEquals(0, downloads)
    }

    @Test fun remoteReadObtainsAnUnkeptCopyAndASecondReadUsesIt() = runBlocking {
        val first = importer.prepareForReading(summary) as WorkImportResult.Success
        assertTrue(first.work.hasEpub)
        assertFalse(first.work.isSaved)
        assertFalse(first.work.isQueuedForLater)
        assertTrue(store.workEpubExists(first.work.id))
        val second = importer.prepareForReading(summary) as WorkImportResult.Success
        assertEquals(first.work.id, second.work.id)
        assertEquals(1, downloads)
    }

    @Test fun missingFileIsRestoredIntoTheSameRecordWithItsKeepAndReadiumLocator() = runBlocking {
        val work = works.upsert(SavedWork(title = "Kept", author = "A", sourceUrl = summary.workUrl,
            isSaved = true, hasEpub = true, lastSpineIndex = 4, lastScrollFraction = 0.6,
            isFinished = true, readiumLocator = "saved-reader-locator", legacyReaderProgress = 0.7))
        val restored = (importer.prepareForReading(work) as WorkImportResult.Success).work
        assertEquals(work.id, restored.id)
        assertTrue(restored.isSaved)
        assertEquals("saved-reader-locator", restored.readiumLocator)
        assertEquals(0, restored.lastSpineIndex)
        assertEquals(0.0, restored.lastScrollFraction, 0.0)
        assertNull(restored.legacyReaderProgress)
        assertFalse(restored.isFinished)
        assertEquals(1, downloads)
    }

    @Test fun readingADeletedCopyRevivesItWithoutDownloadingAgain() = runBlocking {
        val work = works.upsert(SavedWork(title = "Recover me", author = "A", sourceUrl = summary.workUrl))
        store.writeWorkEpub(work.id, bytes)
        works.softDelete(work.id)
        val restored = (importer.prepareForReading(work) as WorkImportResult.Success).work
        assertFalse(restored.isDeleted)
        assertTrue(restored.hasEpub)
        assertEquals(0, downloads)
    }

    @Test fun refusedReadKeepsTheRecordAndReturnsTheError() = runBlocking {
        val work = works.upsert(SavedWork(title = "No longer on AO3", author = "A", sourceUrl = summary.workUrl,
            hasEpub = false, lastSpineIndex = 2))
        fail = true
        val result = importer.prepareForReading(work) as WorkImportResult.Failure
        assertEquals(AO3Error.NotFound, result.error)
        val retained = works.getWork(work.id)!!
        assertFalse(retained.isDeleted)
        assertFalse(retained.isSaved)
        assertEquals(2, retained.lastSpineIndex)
    }

    @Test fun rebuildingUsesTheCurrentLocalStateAndReportsAMissingOriginal() = runBlocking {
        val stale = works.upsert(SavedWork(title = "Import", author = "A", lastSpineIndex = 1))
        assertTrue(importer.rebuildFromOriginal(stale) is WorkImportResult.Failure)
        store.writeOriginal(stale.id, "txt", "The original text.".toByteArray())
        assertFalse(importer.conversionIsStale(stale))
        store.writeConversionRecord(stale.id, WorkConversionRecord(
            converterVersion = 0, format = "plainText", originalFileName = "story.txt", converterPlatform = "android"
        ).encode())
        assertTrue(importer.conversionIsStale(stale))
        works.upsert(stale.copy(lastSpineIndex = 7, isFavorite = true))
        val rebuilt = (importer.rebuildFromOriginal(stale) as WorkImportResult.Success).work
        assertEquals(7, rebuilt.lastSpineIndex)
        assertTrue(rebuilt.isFavorite)
        assertTrue(store.workEpubExists(stale.id))
        assertFalse(importer.conversionIsStale(rebuilt))
        assertEquals(WorkConversionRecord.CURRENT_VERSION,
            WorkConversionRecord.decode(store.readConversionRecord(stale.id))!!.converterVersion)
        assertEquals("android", WorkConversionRecord.decode(store.readConversionRecord(stale.id))!!.converterPlatform)
        assertEquals(0, downloads)
    }
    @Test fun everyConvertedImportWritesItsStampAndRebuildRefreshesIt() = runBlocking {
        val work = (importer.importLocalEpub("story.txt", "Original story.".toByteArray()) as WorkImportResult.Success).work
        val record = WorkConversionRecord.decode(store.readConversionRecord(work.id))!!
        assertEquals("story.txt", record.originalFileName)
        assertEquals("plainText", record.format)
        assertEquals("android", record.converterPlatform)
        assertFalse(importer.conversionIsStale(work))
        store.writeConversionRecord(work.id, record.copy(converterVersion = 0).encode())
        assertTrue(importer.conversionIsStale(work))
        val rebuilt = (importer.rebuildFromOriginal(work) as WorkImportResult.Success).work
        assertFalse(importer.conversionIsStale(rebuilt))
        assertEquals("story.txt", WorkConversionRecord.decode(store.readConversionRecord(work.id))!!.originalFileName)
        assertEquals(0, downloads)
    }

    @Test fun foreignConverterRecordsNeverOfferAnAutomaticRebuild() = runBlocking {
        val work = works.upsert(SavedWork(title = "Shared import", author = "A"))
        store.writeOriginal(work.id, "txt", "The original text.".toByteArray())
        for (platform in listOf(null, "ios", "other")) {
            for (version in listOf(0, 9, 999)) {
                val record = WorkConversionRecord(version, "plainText", "story.txt", converterPlatform = platform)
                store.writeConversionRecord(work.id, record.encode())
                assertFalse(importer.conversionIsStale(work))
                assertEquals(record, WorkConversionRecord.decode(store.readConversionRecord(work.id)))
            }
        }
        assertEquals(0, downloads)
    }

}
