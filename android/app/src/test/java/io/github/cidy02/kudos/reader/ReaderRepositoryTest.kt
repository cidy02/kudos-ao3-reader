package io.github.cidy02.kudos.reader

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

private const val WORK_UUID = "22222222-2222-2222-2222-222222222222"
private val EPUB_BYTES = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3)

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReaderRepositoryTest {
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var workRepository: WorkRepository
    private lateinit var readerRepository: ReaderRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fileStore = WorkFileStore(Files.createTempDirectory("kudos-reader-tests"))
        workRepository = WorkRepository(database, fileStore)
        readerRepository = ReaderRepository(
            workRepository = workRepository,
            fileStore = fileStore,
            settingsProvider = { KudosSettings.Defaults },
            clock = { Instant.parse("2026-06-26T12:00:00Z") }
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    private fun savedWork(hasEpub: Boolean) = SavedWork(
        id = WORK_UUID,
        title = "Example",
        author = "Author",
        isSaved = true,
        hasEpub = hasEpub
    )

    @Test
    fun openReturnsWorkNotFoundForUnknownId() = runTest {
        val result = readerRepository.open("does-not-exist")
        assertTrue(result is ReaderOpenResult.Failure)
        assertEquals(ReaderError.WorkNotFound, (result as ReaderOpenResult.Failure).error)
    }

    @Test
    fun openReturnsNotDownloadedWhenNoEpub() = runTest {
        workRepository.upsert(savedWork(hasEpub = false))
        val result = readerRepository.open(WORK_UUID)
        assertEquals(ReaderError.NotDownloaded, (result as ReaderOpenResult.Failure).error)
    }

    @Test
    fun openReturnsFileMissingWhenFlagSetButNoFile() = runTest {
        workRepository.upsert(savedWork(hasEpub = true))
        val result = readerRepository.open(WORK_UUID)
        assertEquals(ReaderError.FileMissing, (result as ReaderOpenResult.Failure).error)
    }

    @Test
    fun openSucceedsAtBeginningWithDefaultPreferences() = runTest {
        workRepository.upsert(savedWork(hasEpub = true))
        fileStore.writeWorkEpub(WORK_UUID, EPUB_BYTES)

        val result = readerRepository.open(WORK_UUID)
        assertTrue(result is ReaderOpenResult.Success)
        result as ReaderOpenResult.Success
        assertEquals(ReaderRestoreTarget.Beginning, result.restoreTarget)
        assertTrue(result.epubPath.toString().endsWith("$WORK_UUID.epub"))
        assertTrue(result.preferences.scroll)
    }

    @Test
    fun saveProgressPersistsAndPreservesUserState() = runTest {
        workRepository.upsert(savedWork(hasEpub = true).copy(isFavorite = true, isFinished = true))
        val envelope = ReaderLocatorCodec.encodeEnvelope(
            """{"href":"c1.xhtml","locations":{"totalProgression":0.6}}"""
        )

        readerRepository.saveProgress(WORK_UUID, ReaderProgress(4, 0.6, envelope))

        val stored = workRepository.getWork(WORK_UUID)!!
        assertEquals(4, stored.lastSpineIndex)
        assertEquals(0.6, stored.lastScrollFraction, 0.0)
        assertEquals(envelope, stored.readiumLocator)
        assertEquals(Instant.parse("2026-06-26T12:00:00Z"), stored.lastReadDate)
        assertTrue(stored.isFavorite)
        assertTrue(stored.isFinished)
    }

    @Test
    fun reopenAfterProgressRestoresFromLocator() = runTest {
        workRepository.upsert(savedWork(hasEpub = true))
        fileStore.writeWorkEpub(WORK_UUID, EPUB_BYTES)
        val envelope = ReaderLocatorCodec.encodeEnvelope(
            """{"href":"c1.xhtml","locations":{"totalProgression":0.6}}"""
        )
        readerRepository.saveProgress(WORK_UUID, ReaderProgress(4, 0.6, envelope))

        val result = readerRepository.open(WORK_UUID) as ReaderOpenResult.Success
        assertTrue(result.restoreTarget is ReaderRestoreTarget.Locator)
    }

    @Test
    fun setFinishedTogglesWithoutTouchingProgress() = runTest {
        workRepository.upsert(savedWork(hasEpub = true).copy(lastSpineIndex = 3))
        val updated = readerRepository.setFinished(WORK_UUID, true)!!
        assertTrue(updated.isFinished)
        assertEquals(3, updated.lastSpineIndex)
    }

    @Test
    fun markEpubMissingClearsFlagButKeepsRecord() = runTest {
        workRepository.upsert(savedWork(hasEpub = true))
        val updated = readerRepository.markEpubMissing(WORK_UUID)!!
        assertFalse(updated.hasEpub)
        assertTrue(workRepository.getWork(WORK_UUID) != null)
    }
}
