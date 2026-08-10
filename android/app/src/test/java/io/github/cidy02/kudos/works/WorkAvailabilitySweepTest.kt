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
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.After
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
            isSaved = true
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
private class RecordingAO3Client : AO3Client {
    val contactedWorkIds = mutableListOf<Long>()

    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        val workId = WorkTags.ao3WorkIdFromUrl(url)
        if (workId != null) contactedWorkIds += workId
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
