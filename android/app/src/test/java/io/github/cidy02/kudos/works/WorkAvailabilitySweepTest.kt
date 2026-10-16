package io.github.cidy02.kudos.works

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Clock
import io.github.cidy02.kudos.network.ao3.AO3Delay
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Politeness / batching semantics for the manual availability sweep.
 * Must stay free of real wall-clock delays — [RecordingDelay] records waits only.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkAvailabilitySweepTest {
    private lateinit var database: KudosDatabase
    private lateinit var workRepository: WorkRepository
    private val now: Instant = Instant.parse("2026-08-09T12:00:00Z")
    private val clock = AO3Clock { now.toEpochMilli() }

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        workRepository = WorkRepository(
            database,
            WorkFileStore(Files.createTempDirectory("kudos-availability-sweep-tests"))
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun skipsWorksCheckedWithinRecheckInterval() = runTest {
        val recent = work(
            id = "recent",
            workId = 1,
            lastCheck = now.minus(Duration.ofDays(3))
        )
        val due = work(
            id = "due",
            workId = 2,
            lastCheck = now.minus(Duration.ofDays(8))
        )
        workRepository.upsert(recent)
        workRepository.upsert(due)

        val client = RecordingAO3Client()
        val delay = RecordingDelay()
        val sweep = WorkAvailabilitySweep(
            workRepository = workRepository,
            tagsRepository = WorkTagsRepository(client = client),
            clock = clock,
            delay = delay
        )

        val summary = sweep.sweep()

        assertEquals(1, summary.skippedRecent)
        assertEquals(1, summary.checked)
        assertEquals(setOf(2L), client.contactedWorkIds.toSet())
        assertTrue(client.contactedWorkIds.none { it == 1L })
    }

    @Test
    fun capsAtDefaultLimitAndReportsRemaining() = runTest {
        for (i in 1..200) {
            workRepository.upsert(
                work(
                    id = "w$i",
                    workId = i.toLong(),
                    lastCheck = null
                )
            )
        }

        val client = RecordingAO3Client()
        val delay = RecordingDelay()
        val sweep = WorkAvailabilitySweep(
            workRepository = workRepository,
            tagsRepository = WorkTagsRepository(client = client),
            clock = clock,
            delay = delay
        )

        val summary = sweep.sweep()

        assertEquals(WorkAvailabilitySweep.DEFAULT_LIMIT, client.contactedWorkIds.size)
        assertEquals(150, summary.checked)
        assertEquals(50, summary.remaining)
        assertEquals(0, summary.skippedRecent)
    }

    @Test
    fun contactsOldestCheckedFirstAndNullsFirst() = runTest {
        // Insert in reverse of the expected contact order so sort is load-bearing.
        workRepository.upsert(work(id = "newest", workId = 30, lastCheck = now.minus(Duration.ofDays(8))))
        workRepository.upsert(work(id = "middle", workId = 20, lastCheck = now.minus(Duration.ofDays(10))))
        workRepository.upsert(work(id = "never", workId = 10, lastCheck = null))
        workRepository.upsert(work(id = "oldest", workId = 40, lastCheck = now.minus(Duration.ofDays(30))))

        val client = RecordingAO3Client()
        val sweep = WorkAvailabilitySweep(
            workRepository = workRepository,
            tagsRepository = WorkTagsRepository(client = client),
            clock = clock,
            delay = RecordingDelay()
        )

        sweep.sweep()

        // null first, then oldest lastAvailabilityCheck.
        assertEquals(listOf(10L, 40L, 20L, 30L), client.contactedWorkIds)
    }

    @Test
    fun spacesRequestsWith1500msBetweenConsecutiveItemsOnly() = runTest {
        for (i in 1..4) {
            workRepository.upsert(work(id = "w$i", workId = i.toLong(), lastCheck = null))
        }

        val delay = RecordingDelay()
        val sweep = WorkAvailabilitySweep(
            workRepository = workRepository,
            tagsRepository = WorkTagsRepository(client = RecordingAO3Client()),
            clock = clock,
            delay = delay
        )

        sweep.sweep()

        // n-1 waits of REQUEST_SPACING_MILLIS; no trailing sleep after the last item.
        assertEquals(listOf(1500L, 1500L, 1500L), delay.delays)
        assertEquals(3, delay.delays.size)
        assertTrue(delay.delays.all { it == WorkAvailabilitySweep.REQUEST_SPACING_MILLIS })
    }

    // Ports WorkAvailabilitySweepTests.anInconclusiveCheckCountsAsNeitherOutcome.
    @Test
    fun anInconclusiveCheckCountsAsNeitherOutcome() = runTest {
        for (error in listOf(AO3Error.Network("timeout"), AO3Error.Forbidden, AO3Error.RateLimited(null),
            AO3Error.Server(503), AO3Error.Parse("changed markup"))) {
            val original = workRepository.upsert(work("inconclusive", 1, null).copy(ao3WorkID = 1))
            val client = RecordingAO3Client(failures = mapOf(1L to error))
            val summary = WorkAvailabilitySweep(workRepository, WorkTagsRepository(client), clock, RecordingDelay()).sweep()
            assertEquals(1, summary.checked)
            assertEquals(0, summary.stillAvailable)
            assertEquals(0, summary.nowUnavailable)
            assertEquals(0, summary.remaining)
            assertEquals(original, workRepository.getWork(original.id))
        }
    }

    /** The sweep reads its list once; a page read while it runs must not be written back over. */
    @Test
    fun aPlaceReadWhileTheSweepRunsIsKept() = runTest {
        val original = workRepository.upsert(work("reading", 1, null).copy(ao3WorkID = 1))
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                workRepository.upsert(workRepository.getWork(original.id)!!.copy(readiumLocator = "read-meanwhile"))
                return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), "<dl class=\"work meta group\"></dl>"))
            }
        }
        WorkAvailabilitySweep(workRepository, WorkTagsRepository(client), clock, RecordingDelay()).sweep()
        val after = workRepository.getWork(original.id)!!
        assertEquals("read-meanwhile", after.readiumLocator)
        assertEquals(now, after.lastAvailabilityCheck)
    }

    @Test
    fun deletedWorksAreCountedAndBadgedAndAReappearingWorkLosesTheFlag() = runTest {
        workRepository.upsert(work("gone", 1, null).copy(hasEpub = true))
        workRepository.upsert(work("back", 2, null).copy(ao3Unavailable = true))
        val client = RecordingAO3Client(failures = mapOf(1L to AO3Error.NotFound))
        val summary = WorkAvailabilitySweep(workRepository, WorkTagsRepository(client), clock, RecordingDelay()).sweep()
        assertEquals(2, summary.checked)
        assertEquals(1, summary.nowUnavailable)
        assertEquals(1, summary.stillAvailable)
        val gone = workRepository.getWork("gone")!!
        assertTrue(gone.ao3Unavailable && gone.hasEpub && gone.isProtected)
        assertEquals(now, gone.lastAvailabilityCheck)
        assertEquals(1, gone.ao3WorkID)
        val back = workRepository.getWork("back")!!
        assertFalse(back.ao3Unavailable)
        assertEquals(now, back.lastAvailabilityCheck)
    }

    @Test
    fun worksInRecentlyDeletedAreLeftAloneAndOnlyAO3WorksAreContacted() = runTest {
        workRepository.upsert(work("active", 1, null))
        workRepository.upsert(work("deleted", 2, null))
        workRepository.softDelete("deleted")
        workRepository.upsert(work("ffn", 3, null).copy(sourceUrl = "https://www.fanfiction.net/s/9/1/"))
        workRepository.upsert(work("imported", 4, null).copy(sourceUrl = ""))
        val client = RecordingAO3Client()
        val sweep = WorkAvailabilitySweep(workRepository, WorkTagsRepository(client), clock, RecordingDelay())
        assertEquals(2, sweep.counts().unverifiable)
        val summary = sweep.sweep()
        assertEquals(listOf(1L), client.contactedWorkIds)
        assertEquals(1, summary.checked)
        assertNull(workRepository.getWork("deleted")!!.lastAvailabilityCheck)
    }

    @Test
    fun cancellationStopsAndKeepsWhatItFound() = runTest {
        for (i in 1..5) workRepository.upsert(work("w$i", i.toLong(), null))
        val client = RecordingAO3Client()
        val stop = AO3Delay { throw kotlinx.coroutines.CancellationException("Stopped") }
        val summary = WorkAvailabilitySweep(workRepository, WorkTagsRepository(client), clock, stop).sweep()
        assertTrue(summary.cancelled)
        assertEquals(1, summary.checked)
        assertEquals(4, summary.remaining)
        val checked = workRepository.listSavedWorks().filter { it.lastAvailabilityCheck != null }
        assertEquals(1, checked.size)
        assertEquals(now, checked.single().lastAvailabilityCheck)
    }

    private fun work(
        id: String,
        workId: Long,
        lastCheck: Instant?
    ): SavedWork {
        return SavedWork(
            id = id,
            title = "Title $id",
            author = "Author",
            sourceUrl = "https://archiveofourown.org/works/$workId",
            lastAvailabilityCheck = lastCheck,
            isSaved = true,
            // Room keeps milliseconds; a default Instant.now() came back unequal by its microseconds.
            dateAdded = Instant.parse("2026-10-01T12:00:00Z")
        )
    }
}

/** Records delay calls without sleeping — same role as test-tree `NoDelay` / `RecordingDelay`. */
private class RecordingDelay : AO3Delay {
    val delays = mutableListOf<Long>()

    override suspend fun delay(millis: Long) {
        delays += millis
    }
}

/**
 * Fake AO3 client that records contacted work ids and returns parseable success HTML
 * so [WorkTagsRepository.refreshTags] stamps availability without a network.
 */
private class RecordingAO3Client(private val failures: Map<Long, AO3Error> = emptyMap()) : AO3Client {
    val contactedWorkIds = mutableListOf<Long>()

    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        val workId = WorkTags.ao3WorkIdFromUrl(url)
        if (workId != null) contactedWorkIds += workId
        failures[workId]?.let { return AO3Result.Failure(it) }
        return AO3Result.Success(
            AO3HttpResponse(
                url = url,
                statusCode = 200,
                headers = emptyMap(),
                body = MINIMAL_WORK_HTML
            )
        )
    }
}

private val MINIMAL_WORK_HTML = """
    <html><body>
    <dl class="work meta group">
      <dd class="fandom tags"><ul><li><a class="tag">Test</a></li></ul></dd>
      <dd class="language">English</dd>
      <dl class="stats">
        <dd class="words">100</dd>
        <dd class="chapters">1/1</dd>
      </dl>
    </dl>
    </body></html>
""".trimIndent()
