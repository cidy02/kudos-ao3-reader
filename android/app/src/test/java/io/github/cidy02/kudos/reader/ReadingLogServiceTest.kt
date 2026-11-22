package io.github.cidy02.kudos.reader

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.lifecycle.viewModelScope
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.toBackupSettingsPayload
import io.github.cidy02.kudos.core.model.BackupSettings
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.ReadingSessionMode
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.encodeToString
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

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReadingLogServiceTest {
    private lateinit var database: KudosDatabase
    private lateinit var service: ReadingLogService
    private var now = Instant.parse("2026-06-26T12:00:00Z")

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        service = newService()
    }

    @After
    fun tearDown() {
        database.close()
    }

    /** ReadingLogTests.markVisitedUpdatesExistingWatermark. */
    @Test
    fun markVisitedUpdatesExistingWatermark() = runTest {
        val newest = SavedWork(title = "Newest in Fandom", author = "A", ao3WorkID = 99)
        val dao = database.readingLogDao()
        io.github.cidy02.kudos.browse.FandomVisits.markVisited(dao, "The Untamed (TV)", now, newest)
        val first = dao.getAllWatermarks().single()
        advance(60)
        io.github.cidy02.kudos.browse.FandomVisits.markVisited(dao, "The Untamed (TV)", now, newest)
        val row = dao.getAllWatermarks().single()
        assertEquals(first.id, row.id)
        assertEquals("The Untamed (TV)", row.fandomName)
        assertEquals(99, row.newestWorkIDSeen)
        assertEquals("Newest in Fandom", row.newestWorkTitleSeen)
        assertEquals(now, row.lastVisitedAt)
        // A visit with no newest snapshot (the Browse entry path on both platforms) keeps it.
        advance(60)
        io.github.cidy02.kudos.browse.FandomVisits.markVisited(dao, "The Untamed (TV)", now)
        assertEquals(99, dao.getAllWatermarks().single().newestWorkIDSeen)
    }

    @Test
    fun activeGapsAndPauseResume() = runTest {
        val t0 = Instant.parse("2026-06-26T12:00:00Z")
        assertEquals(120.0, ReadingLogService.activeGap(t0, t0.plusSeconds(120)), 0.0)
        assertEquals(300.0, ReadingLogService.activeGap(t0, t0.plusSeconds(300)), 0.0)
        assertEquals(300.0, ReadingLogService.activeGap(t0, t0.plusSeconds(301)), 0.0)
        assertEquals(300.0, ReadingLogService.activeGap(t0, t0.plusSeconds(480)), 0.0)
        assertEquals(0.0, ReadingLogService.activeGap(t0, t0.minusSeconds(1)), 0.0)
        assertEquals(0.0, ReadingLogService.activeGap(t0, t0), 0.0)

        val work = work()
        now = t0
        service.startSession(work)
        advance(120)
        service.noteActivity(work.id)
        advance(300)
        service.noteActivity(work.id)
        advance(480)
        service.noteActivity(work.id)
        // Out-of-order timestamp must be ignored without rewinding lastActivityAt.
        now = t0.plusSeconds(890)
        service.noteActivity(work.id)
        now = t0.plusSeconds(930)
        service.pauseSession(work)
        // Paused activity marks count nothing.
        now = t0.plusSeconds(1_100)
        service.noteActivity(work.id)
        now = t0.plusSeconds(2_000)
        service.resumeSession(work.id)
        advance(120)
        service.noteActivity(work.id)
        advance(80)
        service.endSession(work)

        val row = database.readingLogDao().getAllSessions().single()
        assertEquals(950.0, requireNotNull(row.activeSeconds), 0.0)
        assertEquals(1_130.0, row.durationSeconds, 0.0)
    }

    @Test
    fun startProgressUsesOnlyStoredOverallProgress() = runTest {
        val unreadId = "33333333-3333-4333-8333-333333333333"
        val legacyId = "44444444-4444-4444-8444-444444444444"
        val macId = "55555555-5555-4555-8555-555555555555"
        val unread = work().copy(id = unreadId, chapters = "5/10", lastReadDate = now)
        val legacy = work().copy(id = legacyId, chapters = "5/10", lastSpineIndex = 3)
        val macPercent = work().copy(id = macId, legacyReaderProgress = 0.6)

        service.startSession(unread)
        advance(20)
        service.endSession(unread)

        service.startSession(legacy)
        advance(20)
        service.endSession(legacy)

        service.startSession(macPercent)
        advance(20)
        service.endSession(macPercent)

        val sessions = database.readingLogDao().getAllSessions().associateBy { it.workID }
        assertEquals(0.0, requireNotNull(sessions.getValue(unreadId).startProgress), 0.0)
        assertNull(sessions.getValue(legacyId).startProgress)
        assertEquals(0.6, requireNotNull(sessions.getValue(macId).startProgress), 0.0)
    }

    @Test
    fun startFactsKeepTheirOriginalValuesAndInstallID() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefsName = "reading-log-test-${UUID.randomUUID()}"
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val firstID = ReadingLogService.deviceId(prefs)
        val relaunchedPrefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        assertEquals(firstID, ReadingLogService.deviceId(relaunchedPrefs))

        val zone = ZoneOffset.ofHoursMinutes(5, 30)
        service = ReadingLogService(
            dao = database.readingLogDao(),
            clock = { now },
            zoneIdProvider = { zone },
            deviceIdProvider = { ReadingLogService.deviceId(prefs) }
        )
        val started = work().copy(readiumLocator = locator(0.25, "Chapter 1"), lastSpineIndex = 3)
        service.startSession(started)
        advance(60)
        service.setMode(ReadingSessionMode.LISTEN, started.id, playbackRate = 1.25)
        service.endSession(
            started.copy(readiumLocator = locator(0.75, "Chapter 8"), lastSpineIndex = 8)
        )

        val row = database.readingLogDao().getAllSessions().single()
        assertEquals(19_800, row.tzOffsetSeconds)
        assertEquals(0.25, requireNotNull(row.startProgress), 0.0)
        assertEquals(3, row.startSpineIndex)
        assertEquals(ReadingSessionMode.LISTEN, row.mode)
        assertEquals(1.25, requireNotNull(row.playbackRate), 0.0)
        assertEquals(60.0, requireNotNull(row.activeSeconds), 0.0)
        assertEquals(firstID, row.deviceID)
        assertEquals(1, row.rulesVersion)

        val settingsJson = BackupJson.encodeToString(
            BackupSettings.fromSettings(KudosSettings.Defaults).toBackupSettingsPayload()
        )
        assertFalse(settingsJson.contains(firstID))
        assertFalse(settingsJson.contains("readingLogDeviceID"))
    }

    @Test
    fun oneModePerSittingAndClampedPlaybackRate() = runTest {
        val w = work()
        service.startSession(w)
        service.setMode(ReadingSessionMode.LISTEN, w.id, playbackRate = 2.5)
        advance(20)
        service.pauseSession(w)
        assertEquals(1.5, requireNotNull(database.readingLogDao().getAllSessions().single().playbackRate), 0.0)

        service.resumeSession(w.id)
        // Updating rate while playing clamps to 0.5..1.5; stopping Read Aloud cannot revert to read.
        service.setMode(ReadingSessionMode.LISTEN, w.id, playbackRate = 1.35)
        service.setMode(ReadingSessionMode.READ, w.id)
        advance(10)
        service.endSession(w)

        val listenRow = database.readingLogDao().getAllSessions().single()
        assertEquals("listen", listenRow.modeRaw)
        assertEquals(1.35, requireNotNull(listenRow.playbackRate), 0.0)

        val silentWork = work().copy(id = "66666666-6666-4666-8666-666666666666")
        service.startSession(silentWork)
        advance(20)
        service.endSession(silentWork)
        val readRow = database.readingLogDao().getAllSessions().first { it.workID == silentWork.id }
        assertEquals("read", readRow.modeRaw)
        assertNull(readRow.playbackRate)
    }

    @Test
    fun laterCheckpointUpdatesListeningFactsOnTheSameRow() = runTest {
        val work = work()
        service.startSession(work)
        advance(20)
        service.pauseSession(work)
        advance(10)
        service.resumeSession(work.id)
        service.setMode(ReadingSessionMode.LISTEN, work.id, playbackRate = 1.25)
        advance(20)
        service.endSession(work)

        val row = database.readingLogDao().getAllSessions().single()
        assertEquals(ReadingSessionMode.LISTEN, row.mode)
        assertEquals(1.25, requireNotNull(row.playbackRate), 0.0)
        assertEquals(40.0, requireNotNull(row.activeSeconds), 0.0)
        assertEquals(40.0, row.durationSeconds, 0.0)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun readerViewModelRecordsLocatorActivityAndClampedListeningMode() = runBlocking {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val directory = Files.createTempDirectory("kudos-reading-log-vm-test").toFile()
        var model: ReaderViewModel? = null
        try {
            val files = WorkFileStore(directory.toPath())
            val works = WorkRepository(database, files)
            val seeded = works.upsert(work().copy(hasEpub = true))
            files.writeWorkEpub(seeded.id, byteArrayOf(0x50, 0x4B, 0x03, 0x04))
            val store = object : DataStore<Preferences> {
                override val data = MutableStateFlow(emptyPreferences())
                override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
                    transform(data.value).also { data.value = it }
            }
            val vm = ReaderViewModel(
                ReaderRepository(works, files, settingsProvider = { KudosSettings.Defaults }, clock = { now }),
                service,
                SettingsRepository(store),
                AnnotationRepository(database.annotationDao(), database.syncTombstoneDao()),
                seeded.id
            )
            model = vm
            withTimeout(5_000) { vm.state.filterIsInstance<ReaderUiState.Reading>().first() }
            vm.startReadingSession()
            vm.onProgress(ReaderProgress(0, 0.0, locator(0.0, "Ch 1"), 0.0))
            advance(100)
            vm.onProgress(ReaderProgress(0, 0.0002, locator(0.0002, "Ch 1"), 0.0002))
            advance(400)
            vm.setListeningMode(2.0)
            vm.close()

            val row = withTimeout(5_000) {
                while (database.readingLogDao().getAllSessions().isEmpty()) kotlinx.coroutines.delay(10)
                database.readingLogDao().getAllSessions().single()
            }
            assertEquals("listen", row.modeRaw)
            assertEquals(1.5, requireNotNull(row.playbackRate), 0.0)
            assertEquals(400.0, requireNotNull(row.activeSeconds), 0.0)
        } finally {
            model?.viewModelScope?.coroutineContext?.get(Job)?.cancelAndJoin()
            directory.deleteRecursively()
            Dispatchers.resetMain()
        }
    }

    @Test
    fun startThenEndPersistsAllIosFields() = runTest {
        val started = work()
        service.startSession(started)
        advance(20)
        service.endSession(
            started.copy(
                title = "Updated title",
                sourceUrl = "https://archiveofourown.org/works/42",
                lastSpineIndex = 2,
                readiumLocator = locator(0.4, "Chapter 2"),
                wordCount = 12_000,
                chapters = "3/10"
            )
        )

        val row = database.readingLogDao().getAllSessions().single()
        assertEquals(WORK_ID, row.workID)
        assertEquals(42, row.ao3WorkID)
        assertEquals("https://archiveofourown.org/works/42", row.sourceURL)
        assertEquals("Updated title", row.workTitle)
        assertEquals(Instant.parse("2026-06-26T12:00:00Z"), row.startedAt)
        assertEquals(now, row.endedAt)
        assertEquals(20.0, row.durationSeconds, 0.0)
        assertEquals(2, row.lastSpineIndex)
        assertEquals("Chapter 2", row.chapterTitle)
        assertEquals(0.4, row.endingProgress, 0.0)
        assertEquals(12_000, row.wordCount)
        assertEquals(3, row.chapterCountAtVisit)
        assertFalse(row.didFinish)
        assertEquals(now, row.lastModifiedAt)
    }

    @Test
    fun sessionsUnderFifteenSecondsAreDroppedAndFifteenIsKept() = runTest {
        val work = work()
        service.startSession(work)
        advance(14)
        service.endSession(work)
        assertTrue(database.readingLogDao().getAllSessions().isEmpty())

        service.startSession(work)
        advance(15)
        service.endSession(work)
        assertEquals(15.0, database.readingLogDao().getAllSessions().single().durationSeconds, 0.0)
    }

    @Test
    fun backgroundCheckpointSurvivesProcessLossAndNextStartIsANewVisit() = runTest {
        val work = work()
        service.startSession(work)
        advance(600)
        service.pauseSession(work)

        val checkpoint = database.readingLogDao().getAllSessions().single()
        assertEquals(600.0, checkpoint.durationSeconds, 0.0)
        assertEquals(now, checkpoint.endedAt)

        service = newService() // The old in-memory open session was reclaimed with the process.
        advance(100)
        service.startSession(work)
        advance(20)
        service.endSession(work)

        val rows = database.readingLogDao().getAllSessions()
        assertEquals(2, rows.size)
        assertEquals(setOf(600.0, 20.0), rows.map { it.durationSeconds }.toSet())
    }

    @Test
    fun resumedVisitStaysOneRowAndDoesNotCountBackgroundTime() = runTest {
        val work = work()
        service.startSession(work)
        advance(60)
        service.pauseSession(work)
        advance(240)
        service.resumeSession(work.id)
        advance(60)
        service.endSession(work)

        val row = database.readingLogDao().getAllSessions().single()
        assertEquals(120.0, row.durationSeconds, 0.0)
    }

    @Test
    fun finishTransitionSurvivesBackgroundAndIsNotCountedAgainOnReopen() = runTest {
        val unfinished = work()
        service.startSession(unfinished)
        advance(30)
        service.pauseSession(unfinished.copy(isFinished = true))

        service = newService()
        advance(10)
        val alreadyFinished = unfinished.copy(isFinished = true)
        service.startSession(alreadyFinished)
        advance(30)
        service.endSession(alreadyFinished)

        val rows = database.readingLogDao().getAllSessions()
        assertEquals(2, rows.size)
        assertEquals(1, rows.count { it.didFinish })
    }

    @Test
    fun secondStartForTheSameWorkDoesNotDoubleCount() = runTest {
        val work = work()
        val firstStart = now
        service.startSession(work)
        advance(5)
        service.startSession(work)
        advance(20)
        service.endSession(work)

        val row = database.readingLogDao().getAllSessions().single()
        assertEquals(firstStart, row.startedAt)
        assertEquals(25.0, row.durationSeconds, 0.0)
    }

    private fun newService() = ReadingLogService(
        dao = database.readingLogDao(),
        clock = { now }
    )

    private fun advance(seconds: Long) {
        now = now.plusSeconds(seconds)
    }

    private fun work() = SavedWork(
        id = WORK_ID,
        title = "Session Work",
        author = "Author",
        sourceUrl = "https://archiveofourown.org/works/42",
        ao3WorkID = 42
    )

    private fun locator(progress: Double, title: String): String =
        requireNotNull(
            ReaderLocatorCodec.encodeEnvelope(
                """{"href":"c1.xhtml","title":"$title","locations":{"totalProgression":$progress}}"""
            )
        )

    private companion object {
        const val WORK_ID = "22222222-2222-4222-8222-222222222222"
    }
}
