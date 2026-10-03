package io.github.cidy02.kudos.reader

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.AppSettings
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReaderSettings
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.readingProgress
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.time.Instant
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

private const val WORK_UUID = "22222222-2222-2222-2222-222222222222"
private val EPUB_BYTES = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3)

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReaderRepositoryTest {
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var workRepository: WorkRepository
    private lateinit var readerRepository: ReaderRepository
    private var settingsSnapshot: KudosSettings = KudosSettings.Defaults
    private var now: Instant = Instant.parse("2026-06-26T12:00:00Z")

    @Before
    fun setUp() {
        now = Instant.parse("2026-06-26T12:00:00Z")
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fileStore = WorkFileStore(Files.createTempDirectory("kudos-reader-tests"))
        workRepository = WorkRepository(database, fileStore)
        settingsSnapshot = KudosSettings.Defaults
        readerRepository = ReaderRepository(
            workRepository = workRepository,
            fileStore = fileStore,
            settingsProvider = { settingsSnapshot },
            clock = { now }
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
        // Defaults: 18pt → 100%, matchAppTheme + Light app → Light
        assertEquals(100, result.preferences.fontSizePercent)
        assertEquals(ReaderColorTheme.Light, result.preferences.theme)
    }

    @Test
    fun openKeepsWorkWhenKeepWorksYouReadIsOn() = runTest {
        settingsSnapshot = KudosSettings(app = AppSettings(keepsWorksYouRead = true))
        workRepository.upsert(
            savedWork(hasEpub = true).copy(
                isSaved = false,
                isFinished = true,
                freedAt = Instant.parse("2026-06-20T12:00:00Z")
            )
        )
        fileStore.writeWorkEpub(WORK_UUID, EPUB_BYTES)

        val result = readerRepository.open(WORK_UUID) as ReaderOpenResult.Success

        assertTrue(result.work.isSaved)
        assertTrue(result.work.isDownloaded)
        assertEquals(null, result.work.freedAt)
    }

    @Test
    fun closingReholdsAFinishedUnkeptReadingCopy() = runTest {
        workRepository.upsert(
            savedWork(hasEpub = true).copy(
                sourceUrl = "https://archiveofourown.org/works/123",
                isSaved = false,
                isFinished = true,
                freedAt = Instant.parse("2026-06-20T12:00:00Z")
            )
        )
        fileStore.writeWorkEpub(WORK_UUID, EPUB_BYTES)

        val opened = readerRepository.open(WORK_UUID) as ReaderOpenResult.Success
        assertEquals(null, opened.work.freedAt)

        val closed = readerRepository.close(WORK_UUID)!!
        assertEquals(Instant.parse("2026-06-26T12:00:00Z"), closed.freedAt)
    }

    @Test
    fun openMapsSavedFontPtAndExplicitReaderThemeFromSettingsSnapshot() = runTest {
        // Simulates SettingsRepository.snapshot() after backup restore / deferred 3a write.
        settingsSnapshot = KudosSettings(
            reader = ReaderSettings(
                readerFontPt = 27.0, // 150% of 18pt base
                readerTheme = ReaderThemeSetting.Sepia,
                matchAppReaderTheme = false,
                readerCustomize = true
            ),
            app = AppSettings(appTheme = AppThemeSetting.Dark)
        )
        workRepository.upsert(savedWork(hasEpub = true))
        fileStore.writeWorkEpub(WORK_UUID, EPUB_BYTES)

        val result = readerRepository.open(WORK_UUID) as ReaderOpenResult.Success
        assertEquals(150, result.preferences.fontSizePercent)
        assertEquals(ReaderColorTheme.Sepia, result.preferences.theme)
        assertFalse(result.preferences.publisherStyles)
    }

    @Test
    fun openResolvesThemeFromAppThemeWhenMatchAppReaderTheme() = runTest {
        settingsSnapshot = KudosSettings(
            reader = ReaderSettings(
                readerFontPt = 22.5, // 125%
                readerTheme = ReaderThemeSetting.Light, // ignored when matching app
                matchAppReaderTheme = true
            ),
            app = AppSettings(appTheme = AppThemeSetting.Dark)
        )
        workRepository.upsert(savedWork(hasEpub = true))
        fileStore.writeWorkEpub(WORK_UUID, EPUB_BYTES)

        val result = readerRepository.open(WORK_UUID) as ReaderOpenResult.Success
        assertEquals(125, result.preferences.fontSizePercent)
        assertEquals(ReaderColorTheme.Dark, result.preferences.theme)
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

    @Test
    fun openMapsCustomFontDeclarationsWhenCustomFontSelected() = runTest {
        val customFont = io.github.cidy02.kudos.core.model.CustomFont(
            name = "OpenDyslexic",
            fileName = "opendyslexic.ttf"
        )
        settingsSnapshot = KudosSettings(
            reader = ReaderSettings(
                readerFontId = customFont.selectionId
            )
        )
        workRepository.upsert(savedWork(hasEpub = true))
        fileStore.writeWorkEpub(WORK_UUID, EPUB_BYTES)

        val fontPathResolver: (String) -> String? = { fileName ->
            if (fileName == "opendyslexic.ttf") "/tmp/fonts/opendyslexic.ttf" else null
        }
        val customRepository = ReaderRepository(
            workRepository = workRepository,
            fileStore = fileStore,
            settingsProvider = { settingsSnapshot },
            customFontsProvider = { listOf(customFont) },
            fontPathResolver = fontPathResolver
        )

        val result = customRepository.open(WORK_UUID) as ReaderOpenResult.Success
        assertEquals("custom:opendyslexic.ttf", result.preferences.fontFamily)
        assertEquals(1, result.preferences.fontDeclarations.size)
        assertEquals("/tmp/fonts/opendyslexic.ttf", result.preferences.fontDeclarations.first().fontPath)
    }

    @Test
    fun openPositionMatchesIosForEachStoredCombination() = runTest {
        val locator = envelope(0.8)
        val withLocator = storedWork(
            id = "33333333-3333-3333-3333-333333333333",
            readiumLocator = locator,
            lastSpineIndex = 4,
            chapters = "5/10",
            legacyReaderProgress = null
        )
        val legacyOnly = storedWork(
            id = "44444444-4444-4444-4444-444444444444",
            legacyReaderProgress = 0.42,
            lastSpineIndex = 0,
            lastScrollFraction = 0.0,
            chapters = "5/10"
        )
        val spineOnly = storedWork(
            id = "55555555-5555-5555-5555-555555555555",
            lastSpineIndex = 4,
            lastScrollFraction = 0.3,
            chapters = "5/10"
        )
        val nothing = storedWork(
            id = "66666666-6666-6666-6666-666666666666",
            chapters = ""
        )

        val located = readerRepository.open(withLocator.id) as ReaderOpenResult.Success
        assertTrue(located.restoreTarget is ReaderRestoreTarget.Locator)
        assertEquals(0.8, located.work.readingProgress!!, 0.0)
        assertEquals(now, located.work.lastReadDate)

        val legacy = readerRepository.open(legacyOnly.id) as ReaderOpenResult.Success
        assertEquals(ReaderRestoreTarget.Beginning, legacy.restoreTarget)
        assertEquals(0.42, legacy.work.readingProgress!!, 0.0)
        assertEquals(0.42, legacy.work.legacyReaderProgress!!, 0.0)

        val spine = readerRepository.open(spineOnly.id) as ReaderOpenResult.Success
        val fallback = spine.restoreTarget as ReaderRestoreTarget.Fallback
        assertEquals(4, fallback.spineIndex)
        assertEquals(0.0, fallback.scrollFraction, 0.0)
        assertEquals(0.5, spine.work.readingProgress!!, 0.0)

        val fresh = readerRepository.open(nothing.id) as ReaderOpenResult.Success
        assertEquals(ReaderRestoreTarget.Beginning, fresh.restoreTarget)
        assertNull(fresh.work.readingProgress)
    }

    @Test
    fun openThenCloseWithoutMovingKeepsFortyTwoPercent() = runTest {
        val id = "77777777-7777-7777-7777-777777777777"
        storedWork(
            id = id,
            legacyReaderProgress = 0.42,
            lastSpineIndex = 1,
            lastScrollFraction = 0.42,
            chapters = "1/1"
        )
        val opened = readerRepository.open(id) as ReaderOpenResult.Success
        val fallback = opened.restoreTarget as ReaderRestoreTarget.Fallback
        assertEquals(1, fallback.spineIndex)
        assertEquals(0.0, fallback.scrollFraction, 0.0)

        val landing = ReaderProgress(
            spineIndex = 0,
            scrollFraction = 0.0,
            locatorJson = envelope(0.0),
            totalProgression = 0.0
        )
        assertFalse(readerRepository.observeLocation(id, landing))

        now = now.plusSeconds(30)
        val closed = readerRepository.finishReading(id)!!
        assertEquals(0.42, closed.legacyReaderProgress!!, 0.0)
        assertEquals(0.42, closed.lastScrollFraction, 0.0)
        assertEquals(1, closed.lastSpineIndex)
        assertNull(closed.readiumLocator)
        assertEquals(0.42, closed.readingProgress!!, 0.0)
        assertEquals(now, closed.lastReadDate)
        assertEquals(now, closed.progressModifiedAt)
    }

    @Test
    fun aLaterMovePersistsAtTheInjectedClockAndRetiresTheMacPercent() = runTest {
        val id = "88888888-8888-8888-8888-888888888888"
        storedWork(
            id = id,
            legacyReaderProgress = 0.42,
            lastSpineIndex = 1,
            lastScrollFraction = 0.42,
            chapters = "1/1"
        )
        readerRepository.open(id)
        val openedAt = now
        assertFalse(
            readerRepository.observeLocation(
                id,
                ReaderProgress(0, 0.0, envelope(0.0), totalProgression = 0.0)
            )
        )
        val moved = ReaderProgress(
            spineIndex = 2,
            scrollFraction = 0.2,
            locatorJson = envelope(0.55),
            totalProgression = 0.55
        )
        assertTrue(readerRepository.observeLocation(id, moved))
        now = now.plusSeconds(8)
        val saved = readerRepository.persistLocation(id, moved)!!
        assertNull(saved.legacyReaderProgress)
        assertEquals(0.55, saved.readingProgress!!, 0.0)
        assertEquals(2, saved.lastSpineIndex)
        assertEquals(openedAt, saved.lastReadDate)
        assertEquals(now, saved.progressModifiedAt)

        now = now.plusSeconds(4)
        val closed = readerRepository.finishReading(id)!!
        assertEquals(now, closed.lastReadDate)
        assertEquals(0.55, closed.readingProgress!!, 0.0)
    }

    private fun envelope(total: Double): String {
        return ReaderLocatorCodec.encodeEnvelope(
            """{"href":"chapter.xhtml","type":"application/xhtml+xml","locations":{"progression":$total,"totalProgression":$total}}"""
        )!!
    }

    private suspend fun storedWork(
        id: String,
        readiumLocator: String? = null,
        lastSpineIndex: Int = 0,
        lastScrollFraction: Double = 0.0,
        legacyReaderProgress: Double? = null,
        chapters: String = ""
    ): SavedWork {
        val work = savedWork(hasEpub = true).copy(
            id = id,
            readiumLocator = readiumLocator,
            lastSpineIndex = lastSpineIndex,
            lastScrollFraction = lastScrollFraction,
            legacyReaderProgress = legacyReaderProgress,
            chapters = chapters
        )
        fileStore.writeWorkEpub(id, EPUB_BYTES)
        return workRepository.upsert(work)
    }
}
