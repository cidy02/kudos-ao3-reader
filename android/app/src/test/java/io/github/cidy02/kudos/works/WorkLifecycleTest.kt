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
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

class WorkMetadataMergerTest {
    @Test
    fun preservesUserLocalStateAndDoesNotEraseWithBlanks() {
        val existing = SavedWork(
            id = workUuid,
            title = "Old title",
            author = "Old author",
            summary = "Existing summary",
            sourceUrl = "https://archiveofourown.org/works/123",
            dateAdded = Instant.parse("2026-06-26T12:00:00Z"),
            isFavorite = true,
            isFinished = true,
            hasEpub = true,
            lastSpineIndex = 3,
            lastScrollFraction = 0.5,
            readiumLocator = "locator"
        )
        val summary = sampleSummary().copy(title = "", summary = "", kudos = 9)
        val metadata = AO3WorkMetadata(
            fandoms = listOf("Fandom"),
            relationships = listOf("A/B"),
            words = 1200,
            chapters = "2/2"
        )

        val merged = WorkMetadataMerger().merge(summary, metadata, existing, markSaved = true)

        assertEquals("Old title", merged.title)
        assertEquals("Existing summary", merged.summary)
        assertTrue(merged.isFavorite)
        assertTrue(merged.isFinished)
        assertEquals(3, merged.lastSpineIndex)
        assertEquals(0.5, merged.lastScrollFraction, 0.0)
        assertEquals("locator", merged.readiumLocator)
        assertEquals(listOf("Fandom"), merged.workFandoms)
        assertEquals(listOf("A/B"), merged.workRelationships)
        assertTrue(merged.workTagsFetched)
        assertEquals(1200, merged.wordCount)
        assertEquals("2/2", merged.chapters)
        assertEquals(9, merged.kudos)
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkLifecycleRepositoryTest {
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var repository: WorkRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fileStore = WorkFileStore(Files.createTempDirectory("kudos-work-tests"))
        repository = WorkRepository(
            database = database,
            fileStore = fileStore,
            clock = { Instant.parse("2026-06-26T12:00:00Z") },
            uuidFactory = { "22222222-2222-2222-2222-222222222222" }
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun workRepositoryInsertUpdateAndToggles() = runTest {
        repository.upsert(sampleSavedWork())

        assertEquals("Example", repository.getWork(workUuid)?.title)
        assertTrue(repository.toggleFavorite(workUuid)!!.isFavorite)
        assertTrue(repository.toggleFinished(workUuid)!!.isFinished)
    }

    @Test
    fun deleteLocalEpubPreservesSavedWork() = runTest {
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        fileStore.writeWorkEpub(workUuid, epubBytes)

        val updated = repository.deleteLocalEpub(workUuid)

        assertEquals(workUuid, updated?.id)
        assertFalse(updated!!.hasEpub)
        assertFalse(fileStore.workEpubExists(workUuid))
    }

    @Test
    fun removeFromLibraryDeletesRecordAndFile() = runTest {
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        fileStore.writeWorkEpub(workUuid, epubBytes)

        repository.removeFromLibrary(workUuid)

        assertNull(repository.getWork(workUuid))
        assertFalse(fileStore.workEpubExists(workUuid))
    }

    @Test
    fun userTagsMergeByTrimmedNameAndAvoidDuplicates() = runTest {
        repository.upsert(sampleSavedWork())

        repository.addUserTag(workUuid, " Comfort ")
        val tags = repository.addUserTag(workUuid, "comfort")

        assertEquals(1, tags.size)
        assertEquals("Comfort", tags.first().name)
    }

    @Test
    fun collectionsMembershipCanBeAddedAndRemoved() = runTest {
        repository.upsert(sampleSavedWork())

        val added = repository.addToCollection(workUuid, "Weekend")
        val removed = repository.removeFromCollection(workUuid, added.first().id)

        assertEquals("Weekend", added.first().name)
        assertTrue(removed.isEmpty())
    }

    @Test
    fun libraryRepositoryListsSavedWorksOnly() = runTest {
        repository.upsert(sampleSavedWork())
        repository.upsert(sampleSavedWork("33333333-3333-3333-3333-333333333333").copy(isSaved = false))
        val library = io.github.cidy02.kudos.library.LibraryRepository(repository)

        val works = library.observeSavedWorks().first()

        assertEquals(listOf(workUuid), works.map { it.id })
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkImporterLifecycleTest {
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var repository: WorkRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fileStore = WorkFileStore(Files.createTempDirectory("kudos-import-tests"))
        repository = WorkRepository(database, fileStore)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun saveOnlyCreatesMetadataRecordWithoutEpub() = runTest {
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(fandoms = listOf("Fandom"), words = 99)),
            download = AO3Result.Failure(AO3Error.NotFound)
        )

        val result = importer.saveMetadataOnly(sampleSummary())

        val work = (result as WorkImportResult.Success).work
        assertTrue(work.isSaved)
        assertFalse(work.hasEpub)
        assertEquals(listOf("Fandom"), work.workFandoms)
        assertTrue(work.workTagsFetched)
    }

    @Test
    fun downloadSuccessSetsHasEpubOnlyAfterFileExists() = runTest {
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Success(epubBytes)
        )

        val result = importer.download(sampleSummary())

        val work = (result as WorkImportResult.Success).work
        assertTrue(work.hasEpub)
        assertTrue(fileStore.workEpubExists(work.id))
    }

    @Test
    fun downloadFailureDoesNotSetHasEpub() = runTest {
        val importer = importer(
            metadata = AO3Result.Failure(AO3Error.NotFound),
            download = AO3Result.Failure(AO3Error.Server(503))
        )

        val result = importer.download(sampleSummary())

        val failure = result as WorkImportResult.Failure
        assertEquals(AO3Error.Server(503), failure.error)
        assertFalse(failure.work!!.hasEpub)
        assertFalse(fileStore.workEpubExists(failure.work.id))
    }

    private fun importer(
        metadata: AO3Result<AO3WorkMetadata>,
        download: AO3Result<ByteArray>
    ): WorkImporter {
        val client = FakeAO3Client(
            text = when (metadata) {
                is AO3Result.Failure -> metadata
                is AO3Result.Success -> AO3Result.Success(
                    AO3HttpResponse(
                        url = "https://archiveofourown.org/works/123?view_adult=true",
                        statusCode = 200,
                        headers = emptyMap(),
                        body = "<html></html>"
                    )
                )
            },
            bytes = when (download) {
                is AO3Result.Failure -> download
                is AO3Result.Success -> AO3Result.Success(
                    AO3BinaryResponse(
                        url = "https://archiveofourown.org/downloads/123/work.epub",
                        statusCode = 200,
                        headers = mapOf("Content-Type" to listOf("application/epub+zip")),
                        body = download.value
                    )
                )
            }
        )
        val metadataRepository = object : AO3WorkMetadataRepository(client) {
            override suspend fun fetch(workId: Long): AO3Result<AO3WorkMetadata> = metadata
        }
        return WorkImporter(
            workRepository = repository,
            metadataRepository = metadataRepository,
            downloader = AO3EpubDownloader(client),
            fileStore = fileStore,
            merger = WorkMetadataMerger(uuidFactory = { workUuid })
        )
    }
}

private class FakeAO3Client(
    private val text: AO3Result<AO3HttpResponse>,
    private val bytes: AO3Result<AO3BinaryResponse>
) : AO3Client {
    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> = text

    override suspend fun getBytes(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3BinaryResponse> = bytes
}

private const val workUuid = "11111111-1111-1111-1111-111111111111"
private val epubBytes = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3)

private fun sampleSummary(): AO3WorkSummary {
    return AO3WorkSummary(
        id = 123,
        title = "Example",
        authors = listOf("Alice"),
        fandoms = listOf("Fandom"),
        rating = "Teen",
        warnings = listOf("No Archive Warnings Apply"),
        categories = listOf("Gen"),
        relationships = listOf("A/B"),
        characters = listOf("A"),
        freeforms = listOf("Fluff"),
        summary = "Summary",
        language = "English",
        wordCount = 1200,
        chapters = "1/1",
        kudos = 7,
        comments = 2,
        hits = 99,
        isComplete = true
    )
}

private fun sampleSavedWork(id: String = workUuid): SavedWork {
    return SavedWork(
        id = id,
        title = "Example",
        author = "Alice",
        summary = "Summary",
        sourceUrl = "https://archiveofourown.org/works/123",
        dateAdded = Instant.parse("2026-06-26T12:00:00Z"),
        isSaved = true,
        hasEpub = false
    )
}
