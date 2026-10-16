package io.github.cidy02.kudos.works

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Ports WorkAvailabilityTests through the saved-work refresh, with no AO3 traffic. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkAvailabilityTest {
    private lateinit var database: KudosDatabase
    private lateinit var repository: WorkRepository
    private lateinit var directory: File
    private lateinit var files: WorkFileStore
    private val now = Instant.parse("2026-08-09T12:00:00Z")
    private val requested = mutableListOf<Long>()
    private var response: AO3Result<AO3WorkMetadata> = AO3Result.Success(AO3WorkMetadata(title = "Complete Metadata"))
    private val metadata = object : AO3WorkMetadataRepository() {
        override suspend fun fetch(workId: Long): AO3Result<AO3WorkMetadata> {
            requested += workId
            return response
        }
    }

    @Before
    fun setUp() {
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        directory = Files.createTempDirectory("kudos-availability").toFile()
        files = WorkFileStore(directory.toPath())
        repository = WorkRepository(database, files, clock = { now })
    }

    @After
    fun tearDown() {
        database.close()
        directory.deleteRecursively()
    }

    private fun work() = SavedWork(
        title = "Complete Metadata", author = "Someone",
        sourceUrl = "https://archiveofourown.org/works/555", ao3WorkID = 555,
        hasEpub = true, isSaved = true, workTags = listOf("Fluff"), workFandoms = listOf("Fandom"),
        workWarnings = listOf("No Archive Warnings Apply"), workCategories = listOf("Gen"),
        language = "English", wordCount = 1000, chapters = "1/1", workTagsFetched = true,
        lastSpineIndex = 3, lastScrollFraction = 0.5, downloadedAt = now.minusSeconds(100),
        lastModifiedAt = now.minusSeconds(50),
        // Room keeps milliseconds; a default Instant.now() came back unequal by its microseconds.
        dateAdded = Instant.parse("2026-10-01T12:00:00Z")
    )

    @Test
    fun visibleRefreshDeduplicatesAO3IdentityAndStopsAfterARefusal() = runTest {
        val first = repository.upsert(work())
        val same = repository.upsert(work().copy(id = "second-record"))
        val other = repository.upsert(work().copy(sourceUrl = "https://archiveofourown.org/works/556", ao3WorkID = 556))
        val refresh = WorkMetadataRefresh(repository, metadata)
        refresh.refresh(listOf(first, same, other))
        assertEquals(listOf(555L, 556L), requested)
        requested.clear()
        response = AO3Result.Failure(AO3Error.Forbidden)
        refresh.refresh(listOf(first, other))
        assertEquals(listOf(555L), requested)
        assertFalse(repository.getWork(other.id)!!.isDeleted)
    }

    @Test
    fun refreshMergesOntoTheFlagsAndProgressWrittenWhileTheRequestWaits() = runTest {
        val original = repository.upsert(work())
        val repo = object : AO3WorkMetadataRepository() {
            override suspend fun fetch(workId: Long): AO3Result<AO3WorkMetadata> {
                repository.upsert(repository.getWork(original.id)!!.copy(isFavorite = true,
                    readiumLocator = "new-location", lastSpineIndex = 9))
                return AO3Result.Success(AO3WorkMetadata(words = 2000, title = "New title"))
            }
        }
        val updated = WorkMetadataRefresh(repository, repo).refresh(original)
        assertTrue(updated.isFavorite)
        assertEquals("new-location", updated.readiumLocator)
        assertEquals(9, updated.lastSpineIndex)
        assertEquals(2000, updated.wordCount)
        assertEquals("New title", updated.title)
    }

    @Test
    fun refreshDoesNotReviveAWorkDeletedWhileTheRequestWaits() = runTest {
        val original = repository.upsert(work())
        val repo = object : AO3WorkMetadataRepository() {
            override suspend fun fetch(workId: Long): AO3Result<AO3WorkMetadata> {
                repository.softDelete(original.id)
                return AO3Result.Success(AO3WorkMetadata(words = 2000))
            }
        }
        val updated = WorkMetadataRefresh(repository, repo).refresh(original)
        assertTrue(updated.isDeleted)
        assertEquals(original.wordCount, updated.wordCount)
    }

    @Test
    fun a404MarksTheLocalCopyAsTheLastOne() = runTest {
        val original = repository.upsert(work())
        val bytes = "local EPUB must survive".toByteArray()
        files.writeWorkEpub(original.id, bytes)
        response = AO3Result.Failure(AO3Error.NotFound)

        val refreshed = WorkMetadataRefresh(repository, metadata).refresh(original)

        assertTrue(refreshed.ao3Unavailable)
        assertTrue(refreshed.hasEpub && refreshed.isProtected)
        assertEquals(now, refreshed.lastAvailabilityCheck)
        assertEquals(now, refreshed.lastModifiedAt)
        assertEquals(original, refreshed.copy(ao3Unavailable = false, lastAvailabilityCheck = null,
            lastModifiedAt = original.lastModifiedAt))
        assertEquals(refreshed, repository.getWork(original.id))
        assertArrayEquals(bytes, Files.readAllBytes(files.workEpubPath(original.id)))
    }

    @Test
    fun aWorkStillOnAO3IsRecordedAsChecked() = runTest {
        val original = repository.upsert(work())
        val result = WorkMetadataRefresh(repository, metadata).refresh(original)
        assertFalse(result.ao3Unavailable)
        assertEquals(now, result.lastAvailabilityCheck)
    }

    @Test
    fun aWorkThatReappearsLosesTheFlag() = runTest {
        val original = repository.upsert(work().copy(ao3Unavailable = true))
        val result = WorkMetadataRefresh(repository, metadata).refresh(original)
        assertFalse(result.ao3Unavailable)
        assertEquals(now, result.lastAvailabilityCheck)
    }

    @Test
    fun anInconclusiveFailureRecordsNothingAtAllAndDoesNotClearAnExistingFlag() = runTest {
        for (error in listOf(AO3Error.Network("timeout"), AO3Error.Forbidden, AO3Error.RateLimited(null),
            AO3Error.Server(503), AO3Error.Parse("markup changed"))) {
            for (unavailable in listOf(false, true)) {
                val original = repository.upsert(work().copy(ao3Unavailable = unavailable))
                response = AO3Result.Failure(error)
                assertEquals(original, WorkMetadataRefresh(repository, metadata).refresh(original))
                assertEquals(original, repository.getWork(original.id))
            }
        }
    }

    @Test
    fun aWorkWithNoAO3IdentityIsLeftUnknown() = runTest {
        val original = repository.upsert(work().copy(ao3WorkID = null,
            sourceUrl = "https://www.fanfiction.net/s/999/1/"))
        assertEquals(original, WorkMetadataRefresh(repository, metadata).refresh(original))
        assertTrue(requested.isEmpty())
        assertNull(repository.getWork(original.id)!!.lastAvailabilityCheck)
    }

    @Test
    fun theWorkIDIsRecoveredFromTheSourceURL() = runTest {
        for (result in listOf(AO3Result.Success(AO3WorkMetadata()), AO3Result.Failure(AO3Error.NotFound),
            AO3Result.Failure(AO3Error.Network("offline")))) {
            val original = repository.upsert(work().copy(ao3WorkID = null,
                sourceUrl = "https://archiveofourown.org/works/424242"))
            response = result
            val refreshed = WorkMetadataRefresh(repository, metadata).refresh(original)
            assertEquals(424242L, requested.last())
            assertEquals(424242, refreshed.ao3WorkID)
            assertEquals(424242, repository.getWork(original.id)!!.ao3WorkID)
        }
    }

    @Test
    fun aStoredWorkIDCanBeCheckedWithoutASourceURL() = runTest {
        val original = repository.upsert(work().copy(sourceUrl = ""))
        WorkMetadataRefresh(repository, metadata).refresh(original)
        assertEquals(listOf(555L), requested)
    }

    @Test
    fun aFullRefreshPersistsDatesAndStatusAndBlanksDoNotEraseThem() = runTest {
        val original = repository.upsert(work().copy(isComplete = false))
        response = AO3Result.Success(AO3WorkMetadata(datePublished = "01 Jan 2026",
            dateUpdated = "02 Jan 2026", isComplete = true))
        val refresh = WorkMetadataRefresh(repository, metadata)
        val updated = refresh.refresh(original)
        assertEquals("01 Jan 2026", updated.datePublished)
        assertEquals("02 Jan 2026", updated.dateUpdated)
        assertTrue(updated.isComplete)
        response = AO3Result.Success(AO3WorkMetadata())
        val blank = refresh.refresh(updated)
        assertEquals(updated.datePublished, blank.datePublished)
        assertEquals(updated.dateUpdated, blank.dateUpdated)
        assertTrue(blank.isComplete)
        assertEquals(blank, repository.getWork(original.id))
    }

    @Test
    fun tagOnlyRefreshAlsoRecordsDeletionAndRecoveryWithoutLosingTheFile() = runTest {
        var answer: AO3Result<AO3HttpResponse> = AO3Result.Failure(AO3Error.NotFound)
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> = answer
        }
        val tags = WorkRepository(database, files, tagsRepository = WorkTagsRepository(client), clock = { now })
        val original = tags.upsert(work().copy(ao3WorkID = null))
        val bytes = "local EPUB".toByteArray()
        files.writeWorkEpub(original.id, bytes)
        assertTrue(tags.refreshMetadata(original.id) is AO3Result.Success)
        val gone = tags.getWork(original.id)!!
        assertTrue(gone.ao3Unavailable)
        assertEquals(555, gone.ao3WorkID)
        assertEquals(now, gone.lastAvailabilityCheck)
        answer = AO3Result.Success(AO3HttpResponse(original.sourceUrl, 200, emptyMap(),
            """<dl class="work meta group"><dd class="language">English</dd></dl>"""))
        tags.refreshMetadata(original.id)
        assertFalse(tags.getWork(original.id)!!.ao3Unavailable)
        assertArrayEquals(bytes, Files.readAllBytes(files.workEpubPath(original.id)))
    }
}
