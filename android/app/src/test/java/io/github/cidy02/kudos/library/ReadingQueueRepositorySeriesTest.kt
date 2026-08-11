package io.github.cidy02.kudos.library

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Client
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.nio.file.Paths

class FakeClient : AO3Client {
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        return AO3Result.Failure(AO3Error.NotFound)
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReadingQueueRepositorySeriesTest {
    private lateinit var database: KudosDatabase
    private lateinit var repository: ReadingQueueRepository
    private lateinit var workImporter: WorkImporter

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = ReadingQueueRepository(database)
        
        val fileStore = WorkFileStore(Paths.get(context.filesDir.absolutePath))
        val workRepo = WorkRepository(database, fileStore)
        val fakeClient = FakeClient()
        workImporter = WorkImporter(
            workRepo,
            AO3WorkMetadataRepository(fakeClient),
            AO3EpubDownloader(fakeClient),
            fileStore
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun preserveSeriesSavesAndQueuesWorks() = runTest {
        val queue = repository.ensureSavedForLaterQueue()
        val summaries = listOf(
            AO3WorkSummary(id = 1L, title = "W1", authors = listOf("A1"), fandoms = emptyList(), rating = "", warnings = emptyList(), categories = emptyList()),
            AO3WorkSummary(id = 2L, title = "W2", authors = listOf("A2"), fandoms = emptyList(), rating = "", warnings = emptyList(), categories = emptyList())
        )
        
        val result = repository.preserveSeries(
            summaries = summaries,
            targetQueues = listOf(queue),
            workImporter = workImporter,
            pauseMillis = 0L
        )
        
        assertEquals(2, result.preserved)
        assertEquals(0, result.failed)
        
        val queuedWorks = repository.listWorks(queue.id)
        assertEquals(2, queuedWorks.size)
    }
}
