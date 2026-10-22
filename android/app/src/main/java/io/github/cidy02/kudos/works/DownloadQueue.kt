package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlin.math.exp

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
    private val processDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val nowMillis: () -> Long = { System.nanoTime() / 1_000_000 }
) {
    private val _items = MutableStateFlow<List<DownloadQueueItem>>(emptyList())
    val items: StateFlow<List<DownloadQueueItem>> = _items.asStateFlow()

    private val _instantDownloads = MutableStateFlow<Map<String, Double>>(emptyMap())
    val instantDownloads: StateFlow<Map<String, Double>> = _instantDownloads.asStateFlow()

    /** A keep with no fetch still fills for 0.7 s, independently of the serial queue. */
    fun showInstantDownload(workId: String) {
        if (_instantDownloads.value.containsKey(workId)) return
        _instantDownloads.update { it + (workId to 0.0) }
        val start = nowMillis()
        scope.launch {
            try {
                while (true) {
                    val elapsed = (nowMillis() - start).coerceAtLeast(0)
                    _instantDownloads.update { it + (workId to (elapsed / 700.0).coerceAtMost(1.0)) }
                    if (elapsed >= 700) break
                    delay(minOf(50L, 700 - elapsed))
                }
            } finally {
                _instantDownloads.update { it - workId }
            }
        }
    }

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
                current += item.copy(status = DownloadQueueStatus.Queued, fraction = 0.0)
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

        val start = nowMillis()
        val result = coroutineScope {
            val creep = launch {
                while (true) {
                    setFraction(item.ao3WorkId, downloadPacingFraction(nowMillis() - start))
                    delay(50)
                }
            }
            try {
                withContext(processDispatcher) {
                    downloadItem(item) { fraction -> setFraction(item.ao3WorkId, fraction) }
                }
            } finally {
                creep.cancel()
            }
        }

        when (result) {
            is WorkImportResult.Success -> {
                setFraction(item.ao3WorkId, 1.0)
                delay(300)
                updateStatus(item.ao3WorkId, DownloadQueueStatus.Done)
            }
            is WorkImportResult.Failure -> updateStatus(item.ao3WorkId, DownloadQueueStatus.Failed)
        }
    }

    private suspend fun downloadItem(item: DownloadQueueItem, onProgress: (Double) -> Unit): WorkImportResult {
        item.summary?.let { return workImporter.download(it, onProgress) }

        val source = item.sourceUrl?.takeIf { it.isNotBlank() }
            ?: AO3URLResolver.canonicalWorkUrl(item.ao3WorkId)
        val existing = WorkIdentityIndex.findExisting(
            candidateSourceUrl = source,
            loadWorks = workRepository::listWorksForIdentity
        )
        if (existing != null) {
            return workImporter.downloadExisting(existing, onProgress)
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
        return workImporter.download(summary, onProgress)
    }

    private suspend fun isAlreadyDownloaded(item: DownloadQueueItem): Boolean {
        val source = item.sourceUrl?.takeIf { it.isNotBlank() }
            ?: AO3URLResolver.canonicalWorkUrl(item.ao3WorkId)
        val existing = WorkIdentityIndex.findExisting(
            candidateSourceUrl = source,
            loadWorks = workRepository::listWorksForIdentity
        )
        if (existing == null) return false
        if (existing.isDeleted) {
            // softDelete() keeps the EPUB on disk, so a soft-deleted match with
            // hasEpub=true would otherwise report "already downloaded" and this whole
            // item gets skipped (see the `!item.force` guard above the caller) — the
            // work never actually comes back to the Library, and stays on course to be
            // purged for good when its Recently Deleted window runs out, despite the
            // user having just tried to download it again (directly, or as part of a
            // series). Revive it here rather than only recognising the file is present:
            // restoreFromRecentlyDeleted also retracts the soft-delete's sync
            // tombstone, which the WorkImporter-side revival fixes for the redownload
            // paths don't (they have no repository access to do so).
            workRepository.restoreFromRecentlyDeleted(existing.id)
        }
        return existing.hasEpub
    }

    private fun setFraction(ao3WorkId: Long, fraction: Double) {
        if (!fraction.isFinite()) return
        _items.update { list ->
            list.map { item ->
                if (item.ao3WorkId == ao3WorkId) item.copy(fraction = maxOf(item.fraction, fraction.coerceIn(0.0, 1.0)))
                else item
            }
        }
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
    val summary: AO3WorkSummary? = null,
    val fraction: Double = 0.0
)

/** AO3 may pace without reporting a file size. Never claim completion from elapsed time. */
internal fun downloadPacingFraction(elapsedMillis: Long): Double =
    (0.9 * (1 - exp(-elapsedMillis.coerceAtLeast(0) / 4000.0))).coerceAtMost(0.899999)
