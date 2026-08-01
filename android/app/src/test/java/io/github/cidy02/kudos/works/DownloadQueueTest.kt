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
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
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
class DownloadQueueTest {
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var repository: WorkRepository
    private lateinit var queueScope: CoroutineScope

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fileStore = WorkFileStore(Files.createTempDirectory("kudos-dlqueue-tests"))
        repository = WorkRepository(database, fileStore)
        // Real dispatchers: TestScope + StandardTestDispatcher never auto-runs
        // scope.launch, and Room uses its own executor anyway.
        queueScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    }

    @After
    fun tearDown() {
        queueScope.cancel()
        database.close()
    }

    @Test
    fun enqueueDedupesByAo3WorkId() = runBlocking {
        val downloads = AtomicInteger(0)
        val queue = queue(
            downloadBytes = {
                downloads.incrementAndGet()
                AO3Result.Success(epubBytes)
            }
        )

        queue.enqueue(
            listOf(
                item(1, "One"),
                item(1, "One again"),
                item(2, "Two")
            )
        )
        awaitIdle(queue)

        assertEquals(2, queue.items.value.size)
        assertEquals(setOf(1L, 2L), queue.items.value.map { it.ao3WorkId }.toSet())
        assertEquals(2, downloads.get())
        assertTrue(queue.items.value.all { it.status == DownloadQueueStatus.Done })
        assertFalse(queue.isActive)
    }

    @Test
    fun skipAlreadyDownloadedWhenDetectable() = runBlocking {
        repository.upsert(
            SavedWork(
                id = existingWorkId,
                title = "Saved",
                author = "Alice",
                sourceUrl = "https://archiveofourown.org/works/99",
                dateAdded = Instant.parse("2026-06-26T12:00:00Z"),
                isSaved = true,
                hasEpub = true
            )
        )
        val downloads = AtomicInteger(0)
        val queue = queue(
            downloadBytes = {
                downloads.incrementAndGet()
                AO3Result.Success(epubBytes)
            }
        )

        queue.enqueue(listOf(item(99, "Saved")))
        awaitIdle(queue)

        assertEquals(0, downloads.get())
        assertEquals(DownloadQueueStatus.Skipped, queue.items.value.single().status)
        assertFalse(queue.isActive)
    }

    @Test
    fun forceBypassesAlreadyDownloadedSkip() = runBlocking {
        repository.upsert(
            SavedWork(
                id = existingWorkId,
                title = "Saved",
                author = "Alice",
                sourceUrl = "https://archiveofourown.org/works/99",
                dateAdded = Instant.parse("2026-06-26T12:00:00Z"),
                isSaved = true,
                hasEpub = true
            )
        )
        val downloads = AtomicInteger(0)
        val queue = queue(
            downloadBytes = {
                downloads.incrementAndGet()
                AO3Result.Success(epubBytes)
            }
        )

        queue.enqueue(listOf(item(99, "Saved", force = true)))
        awaitIdle(queue)

        assertEquals(1, downloads.get())
        assertEquals(DownloadQueueStatus.Done, queue.items.value.single().status)
    }

    @Test
    fun cancelRemovesQueuedButLeavesInFlight() = runBlocking {
        val started = AtomicInteger(0)
        val release = CompletableDeferred<Unit>()
        val queue = queue(
            downloadBytes = {
                started.incrementAndGet()
                release.await()
                AO3Result.Success(epubBytes)
            }
        )

        queue.enqueue(
            listOf(
                item(1, "One"),
                item(2, "Two"),
                item(3, "Three")
            )
        )
        withTimeout(5_000) {
            while (started.get() < 1) delay(10)
            queue.items.first { list ->
                list.any { it.status == DownloadQueueStatus.Downloading }
            }
        }
        assertEquals(1, started.get())

        queue.cancel()

        assertEquals(
            listOf(DownloadQueueStatus.Downloading),
            queue.items.value.map { it.status }
        )
        assertEquals(1L, queue.items.value.single().ao3WorkId)

        release.complete(Unit)
        awaitIdle(queue)

        assertEquals(DownloadQueueStatus.Done, queue.items.value.single().status)
        assertEquals(1, started.get())
        assertFalse(queue.isActive)
    }

    @Test
    fun processesSeriallyAndRecordsFailure() = runBlocking {
        val order = mutableListOf<Long>()
        val queue = queue(
            downloadBytes = { workId ->
                order += workId
                if (workId == 2L) {
                    AO3Result.Failure(AO3Error.Server(503))
                } else {
                    AO3Result.Success(epubBytes)
                }
            }
        )

        queue.enqueue(listOf(item(1, "One"), item(2, "Two"), item(3, "Three")))
        awaitIdle(queue)

        assertEquals(listOf(1L, 2L, 3L), order)
        assertEquals(
            listOf(
                DownloadQueueStatus.Done,
                DownloadQueueStatus.Failed,
                DownloadQueueStatus.Done
            ),
            queue.items.value.map { it.status }
        )
        assertEquals(1, queue.failedCount)
        assertFalse(queue.isActive)
    }

    @Test
    fun secondEnqueueWhileRunningAppendsWithoutClearing() = runBlocking {
        val release = CompletableDeferred<Unit>()
        val downloads = AtomicInteger(0)
        val queue = queue(
            downloadBytes = {
                downloads.incrementAndGet()
                if (downloads.get() == 1) release.await()
                AO3Result.Success(epubBytes)
            }
        )

        queue.enqueue(listOf(item(1, "One")))
        withTimeout(5_000) {
            queue.items.first { list ->
                list.any { it.status == DownloadQueueStatus.Downloading }
            }
        }
        assertTrue(queue.isActive)
        queue.enqueue(listOf(item(2, "Two")))

        assertEquals(listOf(1L, 2L), queue.items.value.map { it.ao3WorkId })
        release.complete(Unit)
        awaitIdle(queue)

        assertEquals(2, downloads.get())
        assertTrue(queue.items.value.all { it.status == DownloadQueueStatus.Done })
    }

    private suspend fun awaitIdle(queue: DownloadQueue) {
        withTimeout(10_000) {
            queue.items.first { list ->
                list.isNotEmpty() &&
                    list.none {
                        it.status == DownloadQueueStatus.Queued ||
                            it.status == DownloadQueueStatus.Downloading
                    }
            }
        }
    }

    private fun queue(
        downloadBytes: suspend (Long) -> AO3Result<ByteArray>
    ): DownloadQueue {
        val client = object : AO3Client {
            override suspend fun get(
                url: String,
                headers: Map<String, String>
            ): AO3Result<AO3HttpResponse> {
                return AO3Result.Success(
                    AO3HttpResponse(
                        url = url,
                        statusCode = 200,
                        headers = emptyMap(),
                        body = "<html></html>"
                    )
                )
            }

            override suspend fun getBytes(
                url: String,
                headers: Map<String, String>
            ): AO3Result<AO3BinaryResponse> {
                val workId = url.substringAfter("/downloads/").substringBefore('/').toLongOrNull()
                    ?: return AO3Result.Failure(AO3Error.Validation("bad download url"))
                return when (val result = downloadBytes(workId)) {
                    is AO3Result.Failure -> result
                    is AO3Result.Success -> AO3Result.Success(
                        AO3BinaryResponse(
                            url = url,
                            statusCode = 200,
                            headers = mapOf("Content-Type" to listOf("application/epub+zip")),
                            body = result.value
                        )
                    )
                }
            }
        }
        val metadataRepository = object : AO3WorkMetadataRepository(client) {
            override suspend fun fetch(workId: Long): AO3Result<AO3WorkMetadata> {
                return AO3Result.Success(AO3WorkMetadata(chapters = "1/1"))
            }
        }
        val importer = WorkImporter(
            workRepository = repository,
            metadataRepository = metadataRepository,
            downloader = AO3EpubDownloader(client),
            fileStore = fileStore
        )
        return DownloadQueue(
            workImporter = importer,
            workRepository = repository,
            scope = queueScope,
            processDispatcher = Dispatchers.IO
        )
    }

    private fun item(
        id: Long,
        title: String,
        force: Boolean = false
    ): DownloadQueueItem {
        val summary = AO3WorkSummary(
            id = id,
            title = title,
            authors = listOf("Author"),
            fandoms = listOf("Fandom"),
            rating = "Teen",
            warnings = emptyList(),
            categories = emptyList()
        )
        return DownloadQueueItem(
            ao3WorkId = id,
            title = title,
            sourceUrl = summary.workUrl,
            force = force,
            summary = summary
        )
    }
}

private val existingWorkId = "11111111-1111-1111-1111-111111111111"
private val epubBytes = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3)
