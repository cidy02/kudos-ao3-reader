package io.github.cidy02.kudos.works

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Client
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

/** Always answers 404 — the cheapest way to exercise the "AO3 says gone" path
 * without needing a real work-page HTML fixture to parse. */
private class NotFoundAO3Client : AO3Client {
    var requestCount = 0
        private set

    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        requestCount++
        return AO3Result.Success(AO3HttpResponse(url = url, statusCode = 404, headers = emptyMap(), body = ""))
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkAvailabilitySweepTest {
    private lateinit var database: KudosDatabase
    private lateinit var workRepository: WorkRepository
    private lateinit var client: NotFoundAO3Client
    private lateinit var sweep: WorkAvailabilitySweep
    private val now: Instant = Instant.parse("2026-07-31T12:00:00Z")

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        workRepository = WorkRepository(database, WorkFileStore(Files.createTempDirectory("kudos-sweep-tests")))
        client = NotFoundAO3Client()
        sweep = WorkAvailabilitySweep(workRepository, WorkTagsRepository(client), clock = { now })
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun pendingSkipsWorksCheckedWithinTheRecheckIntervalAndOrdersOldestFirst() = runTest {
        workRepository.upsert(work("recent", lastCheck = now.minus(Duration.ofHours(1))))
        workRepository.upsert(work("neverChecked", lastCheck = null))
        workRepository.upsert(work("justOutsideWindow", lastCheck = now.minus(WorkAvailabilitySweep.RECHECK_INTERVAL)))
        workRepository.upsert(work("longAgo", lastCheck = now.minus(Duration.ofDays(30))))

        val pending = sweep.pending(now).map { it.id }

        // Never-checked sorts first — those are the works the sweep knows least
        // about (mirrors iOS's own `pending(in:)` ordering).
        assertEquals(listOf("neverChecked", "longAgo", "justOutsideWindow"), pending)
    }

    @Test
    fun runMarksA404WorkUnavailableAndStampsTheCheckTime() = runTest {
        workRepository.upsert(work("gone", lastCheck = null))

        val summary = sweep.run()

        assertEquals(1, summary.checked)
        assertEquals(1, summary.nowUnavailable)
        val updated = workRepository.getWork("gone")!!
        assertTrue(updated.ao3Unavailable)
        assertEquals(now, updated.lastAvailabilityCheck)
    }

    @Test
    fun runRespectsThePerRunLimitAndReportsWhatIsLeftOver() = runTest {
        repeat(5) { workRepository.upsert(work("work-$it", lastCheck = null)) }

        val summary = sweep.run(limit = 3)

        assertEquals(3, summary.checked)
        assertEquals(2, summary.remaining)
        assertEquals(3, client.requestCount)
    }

    @Test
    fun runCountsUnverifiableWorksWithoutContactingAO3() = runTest {
        workRepository.upsert(work("no-source", lastCheck = null).copy(sourceUrl = ""))
        workRepository.upsert(work("has-source", lastCheck = null))

        val summary = sweep.run()

        assertEquals(1, summary.unverifiable)
        assertEquals(1, summary.checked)
        assertEquals(1, client.requestCount)
    }

    private fun work(id: String, lastCheck: Instant?): SavedWork {
        return SavedWork(
            id = id,
            title = "Title $id",
            author = "Author",
            sourceUrl = "https://archiveofourown.org/works/${id.hashCode().let { if (it < 0) -it else it }}",
            isSaved = true,
            lastAvailabilityCheck = lastCheck
        )
    }
}
