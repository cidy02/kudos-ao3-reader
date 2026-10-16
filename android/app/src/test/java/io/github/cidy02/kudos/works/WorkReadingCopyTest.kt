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
                return if (fail) AO3Result.Failure(AO3Error.NotFound) else AO3Result.Success(
                    AO3BinaryResponse(url, 200, mapOf("Content-Type" to listOf("application/epub+zip")), bytes))
            }
        }
        importer = WorkImporter(works, AO3WorkMetadataRepository(fake), AO3EpubDownloader(fake), store, context.cacheDir)
    }

    @After fun tearDown() { database.close() }

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
        works.upsert(stale.copy(lastSpineIndex = 7, isFavorite = true))
        val rebuilt = (importer.rebuildFromOriginal(stale) as WorkImportResult.Success).work
        assertEquals(7, rebuilt.lastSpineIndex)
        assertTrue(rebuilt.isFavorite)
        assertTrue(store.workEpubExists(stale.id))
        assertEquals(0, downloads)
    }
}
