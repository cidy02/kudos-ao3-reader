package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext

/**
 * Serially downloads AO3 works via [WorkImporter], keeping network polite
 * (one at a time). Mirrors Apple `DownloadQueue`: enqueue, cancel remaining,
 * skip already-downloaded works, and expose progress for a root banner.
 */
class DownloadQueue(
    private val workImporter: WorkImporter,
    private val workRepository: WorkRepository,
    private val seriesRepository: AO3SeriesRepository = AO3SeriesRepository(),
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    private val processDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    private val _items = MutableStateFlow<List<DownloadQueueItem>>(emptyList())
    val items: StateFlow<List<DownloadQueueItem>> = _items.asStateFlow()

    private val pumpMutex = Mutex()

    @Volatile
    private var isRunning = false

    val pendingCount: Int
        get() = _items.value.count {
            it.status == DownloadQueueStatus.Queued || it.status == DownloadQueueStatus.Downloading
        }

    val finishedCount: Int
        get() = _items.value.size - pendingCount

    val total: Int
        get() = _items.value.size

    val failedCount: Int
        get() = _items.value.count { it.status == DownloadQueueStatus.Failed }

    val currentTitle: String?
        get() = _items.value.firstOrNull { it.status == DownloadQueueStatus.Downloading }?.title

    val isActive: Boolean
        get() = pendingCount > 0

    /**
     * Enqueues works that aren't already queued/in-flight and starts serial
     * processing. A fresh run (nothing in flight) first clears previous finished rows.
     */
    fun enqueue(newItems: List<DownloadQueueItem>) {
        if (newItems.isEmpty()) return
        // Synchronous state update so rapid second enqueue appends to the same run.
        val current = _items.value.toMutableList()
        if (!isRunning) {
            current.clear()
        }
        val seen = current.map { it.ao3WorkId }.toMutableSet()
        for (item in newItems) {
            if (seen.add(item.ao3WorkId)) {
                current += item.copy(status = DownloadQueueStatus.Queued)
            }
        }
        _items.value = current
        if (current.any { it.status == DownloadQueueStatus.Queued }) {
            isRunning = true
            scope.launch { pump() }
        }
    }

    /** Convenience: enqueue one remote summary (Work Detail Download path). */
    fun enqueue(summary: AO3WorkSummary, force: Boolean = false) {
        enqueue(
            listOf(
                DownloadQueueItem(
                    ao3WorkId = summary.id,
                    title = summary.title.ifBlank { "Work ${summary.id}" },
                    sourceUrl = summary.workUrl,
                    force = force,
                    isComplete = summary.isComplete == true,
                    seriesUrl = summary.seriesUrl.orEmpty(),
                    summary = summary
                )
            )
        )
    }

    /**
     * Convenience: enqueue a local library work (redownload). [force] defaults
     * true so an already-downloaded EPUB is not skipped.
     */
    fun enqueueLocal(
        ao3WorkId: Long,
        title: String,
        sourceUrl: String,
        force: Boolean = true
    ) {
        enqueue(
            listOf(
                DownloadQueueItem(
                    ao3WorkId = ao3WorkId,
                    title = title,
                    sourceUrl = sourceUrl,
                    force = force
                )
            )
        )
    }

    /**
     * Fetches every work on the AO3 series page(s) and enqueues them for serial
     * download. Already-downloaded works are skipped during [process]. Mirrors
     * Apple Work Detail "Download Whole Series" → `AO3Client.seriesWorks` + queue.
     *
     * @return [AO3Result.Success] with the number of works discovered (pre-dedupe /
     * skip), or a failure from the series fetch/parse path.
     */
    suspend fun enqueueSeries(seriesUrl: String): AO3Result<Int> {
        return when (val result = seriesRepository.seriesWorks(seriesUrl)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> {
                val works = result.value
                enqueue(
                    works.map { summary ->
                        DownloadQueueItem(
                            ao3WorkId = summary.id,
                            title = summary.title.ifBlank { "Work ${summary.id}" },
                            sourceUrl = summary.workUrl,
                            isComplete = summary.isComplete == true,
                            seriesUrl = seriesUrl,
                            summary = summary
                        )
                    }
                )
                AO3Result.Success(works.size)
            }
        }
    }

    /** Cancels everything still queued. An in-flight download finishes. */
    fun cancel() {
        _items.update { list -> list.filterNot { it.status == DownloadQueueStatus.Queued } }
    }

    /**
     * Serial pump: only one coroutine processes the queue at a time.
     * Extra [pump] launches no-op via [pumpMutex] until the active run finishes,
     * then the trailing check restarts if anything is still queued.
     */
    private suspend fun pump() {
        if (!pumpMutex.tryLock()) return
        try {
            isRunning = true
            while (true) {
                val index = _items.value.indexOfFirst { it.status == DownloadQueueStatus.Queued }
                if (index < 0) break
                process(index)
            }
        } finally {
            isRunning = false
            pumpMutex.unlock()
            if (_items.value.any { it.status == DownloadQueueStatus.Queued }) {
                isRunning = true
                scope.launch { pump() }
            }
        }
    }

    private suspend fun process(index: Int) {
        val item = _items.value.getOrNull(index) ?: return
        if (item.status != DownloadQueueStatus.Queued) return

        if (!item.force && isAlreadyDownloaded(item)) {
            updateStatus(item.ao3WorkId, DownloadQueueStatus.Skipped)
            return
        }

        updateStatus(item.ao3WorkId, DownloadQueueStatus.Downloading)

        val result = withContext(processDispatcher) {
            downloadItem(item)
        }

        when (result) {
            is WorkImportResult.Success -> updateStatus(item.ao3WorkId, DownloadQueueStatus.Done)
            is WorkImportResult.Failure -> updateStatus(item.ao3WorkId, DownloadQueueStatus.Failed)
        }
    }

    private suspend fun downloadItem(item: DownloadQueueItem): WorkImportResult {
        item.summary?.let { return workImporter.download(it) }

        val source = item.sourceUrl?.takeIf { it.isNotBlank() }
            ?: AO3URLResolver.canonicalWorkUrl(item.ao3WorkId)
        val existing = WorkIdentityIndex.findExisting(
            candidateSourceUrl = source,
            byId = { workRepository.getWork(it) },
            bySourceUrl = { workRepository.findBySourceUrl(it) }
        )
        if (existing != null) {
            return workImporter.downloadExisting(existing)
        }

        // Minimal summary so WorkImporter can still fetch canonical metadata + EPUB.
        val summary = AO3WorkSummary(
            id = item.ao3WorkId,
            title = item.title,
            authors = emptyList(),
            fandoms = emptyList(),
            rating = "",
            warnings = emptyList(),
            categories = emptyList(),
            isComplete = item.isComplete.takeIf { it },
            seriesUrl = item.seriesUrl.takeIf { it.isNotBlank() }
        )
        return workImporter.download(summary)
    }

    private suspend fun isAlreadyDownloaded(item: DownloadQueueItem): Boolean {
        val source = item.sourceUrl?.takeIf { it.isNotBlank() }
            ?: AO3URLResolver.canonicalWorkUrl(item.ao3WorkId)
        val existing = WorkIdentityIndex.findExisting(
            candidateSourceUrl = source,
            byId = { workRepository.getWork(it) },
            bySourceUrl = { workRepository.findBySourceUrl(it) }
        )
        return existing?.hasEpub == true
    }

    private fun updateStatus(ao3WorkId: Long, status: DownloadQueueStatus) {
        _items.update { list ->
            list.map { item ->
                if (item.ao3WorkId == ao3WorkId) item.copy(status = status) else item
            }
        }
    }
}

enum class DownloadQueueStatus {
    Queued,
    Downloading,
    Done,
    Skipped,
    Failed
}

data class DownloadQueueItem(
    val ao3WorkId: Long,
    val title: String,
    val sourceUrl: String? = null,
    val status: DownloadQueueStatus = DownloadQueueStatus.Queued,
    /** When true, download even if a local EPUB already exists (redownload). */
    val force: Boolean = false,
    val isComplete: Boolean = false,
    val seriesUrl: String = "",
    /** Preferred path: full blurb from Search/Browse/Work Detail. */
    val summary: AO3WorkSummary? = null
)
