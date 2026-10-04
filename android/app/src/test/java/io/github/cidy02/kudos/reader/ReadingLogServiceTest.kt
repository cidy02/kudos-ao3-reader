package io.github.cidy02.kudos.reader

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
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
