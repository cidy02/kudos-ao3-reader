package io.github.cidy02.kudos.works

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import io.github.cidy02.kudos.core.model.CoverArtResolution
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.ui.components.LocalUseEmbeddedCoverArt
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

internal const val EMBEDDED_COVER_ART_IMAGE_TAG = "embeddedCoverArtImage"

/**
 * One queued scan per EPUB file revision, caching decoded thumbnails in memory and under
 * `cacheDir/GeneratedCoverArt` (derived data only, never a library field).
 *
 * Port of iOS `GeneratedCoverArtLoader` (`UIComponents/GeneratedCoverArtLoader.swift:5-118`).
 */
open class EmbeddedCoverArtLoader(
    private val directory: File,
    private val scan: (File, () -> Boolean) -> ByteArray? = { file, isCancelled ->
        EmbeddedWorkCoverImage.data(file, isCancelled)
    },
    private val scanDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    /** `bitmap == null` represents a scanned "no embedded art" negative cache entry. */
    class CacheEntry(val bitmap: Bitmap?, internal val revision: String = "")

    private data class HasArtEntry(val hasArt: Boolean, val revision: String)

    private sealed interface PreparedLoad {
        data class Resolved(val bitmap: Bitmap?) : PreparedLoad
        data class NeedsScan(
            val revision: String,
            val safeWorkId: String,
            val scanKey: String
        ) : PreparedLoad
    }

    private val memory = MemoryCache(
        maxCount = MAX_MEMORY_ENTRIES,
        maxBytes = memoryBudgetBytes()
    )
    private val hasArtMemory = HasArtCache(maxCount = MAX_HAS_ART_ENTRIES)
    private val scope = CoroutineScope(SupervisorJob() + scanDispatcher)
    private val mutex = Mutex()
    private var tail: Job? = null
    private val scanning = mutableSetOf<String>()
    private val waiters = mutableMapOf<String, MutableMap<String, CompletableDeferred<Bitmap?>>>()
    private val waiterCounts = ConcurrentHashMap<String, AtomicInteger>()

    /**
     * Synchronous in-memory cache lookup with zero filesystem I/O so scrolled/recomposed cards
     * draw without flicker or main-thread `stat()` calls. Staleness is verified off-main-thread
     * in [load] / [hasEmbeddedArt].
     */
    open fun peekCached(epubFile: File): CacheEntry? = memory.get(epubFile.absolutePath)

    /** Synchronous in-memory "has embedded art" lookup with zero filesystem I/O. */
    fun peekHasArt(epubFile: File): Boolean? {
        val path = epubFile.absolutePath
        hasArtMemory.get(path)?.let { return it.hasArt }
        return memory.get(path)?.let { it.bitmap != null }
    }

    /**
     * Checks off the main thread whether [epubFile] contains qualifying embedded cover art,
     * caching the boolean result in a small LRU cache without decoding the JPEG bitmap when
     * the disk cache already knows the answer.
     */
    suspend fun hasEmbeddedArt(workId: String, epubFile: File): Boolean {
        val path = epubFile.absolutePath
        val known = withContext(scanDispatcher) {
            val revision = revisionOf(epubFile)
            if (revision == null) {
                memory.remove(path)
                hasArtMemory.remove(path)
                return@withContext false
            }
            hasArtMemory.get(path)?.takeIf { it.revision == revision }?.let { return@withContext it.hasArt }
            memory.get(path)?.takeIf { it.revision == revision }?.let { cached ->
                val hasArt = cached.bitmap != null
                hasArtMemory.put(path, HasArtEntry(hasArt, revision))
                return@withContext hasArt
            }
            val safeWorkId = sanitizeId(workId)
            val basename = "$safeWorkId-$revision"
            if (File(directory, "$basename.jpg").isFile) {
                hasArtMemory.put(path, HasArtEntry(true, revision))
                return@withContext true
            }
            if (File(directory, "$basename.empty").isFile) {
                hasArtMemory.put(path, HasArtEntry(false, revision))
                return@withContext false
            }
            null
        }
        if (known != null) return known
        return load(workId = workId, epubFile = epubFile) != null
    }

    open suspend fun load(workId: String, epubFile: File): Bitmap? {
        val path = epubFile.absolutePath
        val prepared = withContext(scanDispatcher) {
            val revision = revisionOf(epubFile)
            if (revision == null) {
                memory.remove(path)
                hasArtMemory.remove(path)
                return@withContext PreparedLoad.Resolved(null)
            }
            memory.get(path)?.takeIf { it.revision == revision }?.let { cached ->
                hasArtMemory.put(path, HasArtEntry(cached.bitmap != null, revision))
                return@withContext PreparedLoad.Resolved(cached.bitmap)
            }

            val safeWorkId = sanitizeId(workId)
            val basename = "$safeWorkId-$revision"
            val jpeg = File(directory, "$basename.jpg")
            if (jpeg.isFile) {
                val decoded = runCatching {
                    val bytes = jpeg.readBytes()
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }.getOrNull()
                if (decoded != null) {
                    memory.put(path, CacheEntry(decoded, revision))
                    hasArtMemory.put(path, HasArtEntry(true, revision))
                    return@withContext PreparedLoad.Resolved(decoded)
                }
            }
            val empty = File(directory, "$basename.empty")
            if (empty.isFile) {
                memory.put(path, CacheEntry(null, revision))
                hasArtMemory.put(path, HasArtEntry(false, revision))
                return@withContext PreparedLoad.Resolved(null)
            }
            PreparedLoad.NeedsScan(
                revision = revision,
                safeWorkId = safeWorkId,
                scanKey = cacheKey(epubFile, revision)
            )
        }
        val request = when (prepared) {
            is PreparedLoad.Resolved -> return prepared.bitmap
            is PreparedLoad.NeedsScan -> prepared
        }

        val scanKey = request.scanKey
        val waiterId = UUID.randomUUID().toString()
        val deferred = CompletableDeferred<Bitmap?>()
        mutex.withLock {
            memory.get(path)?.takeIf { it.revision == request.revision }?.let { return it.bitmap }
            waiters.getOrPut(scanKey) { linkedMapOf() }[waiterId] = deferred
            waiterCounts.computeIfAbsent(scanKey) { AtomicInteger(0) }.incrementAndGet()
            if (scanning.add(scanKey)) {
                val previous = tail
                tail = scope.launch(scanDispatcher) {
                    previous?.join()
                    while (true) {
                        if (!hasWaiters(scanKey)) {
                            if (abandonIfEmpty(scanKey)) return@launch
                            continue
                        }
                        val aborted = AtomicBoolean(false)
                        val isCancelled = {
                            val noWaiters = (waiterCounts[scanKey]?.get() ?: 0) <= 0
                            if (noWaiters) aborted.set(true)
                            noWaiters
                        }
                        val raw = runCatching { scan(epubFile, isCancelled) }.getOrNull()
                        if (aborted.get()) {
                            // Never write `.empty` or negative-cache a scan aborted by cancellation.
                            if (abandonIfEmpty(scanKey)) return@launch
                            continue
                        }
                        if (raw != null && (waiterCounts[scanKey]?.get() ?: 0) <= 0) {
                            if (abandonIfEmpty(scanKey)) return@launch
                            continue
                        }
                        val jpegBytes = EmbeddedWorkCoverImage.downsampledJPEG(raw)
                        finish(
                            scanKey = scanKey,
                            path = path,
                            safeWorkId = request.safeWorkId,
                            epubFile = epubFile,
                            revision = request.revision,
                            jpegBytes = jpegBytes
                        )
                        return@launch
                    }
                }
            }
        }

        return try {
            deferred.await()
        } finally {
            if (!deferred.isCompleted) {
                withContext(NonCancellable) {
                    cancelWaiter(scanKey, waiterId)
                }
            }
        }
    }

    private suspend fun cancelWaiter(scanKey: String, waiterId: String) {
        val removed = mutex.withLock {
            val entries = waiters[scanKey] ?: return@withLock null
            val waiter = entries.remove(waiterId)
            if (waiter != null) {
                waiterCounts[scanKey]?.decrementAndGet()
            }
            if (entries.isEmpty()) waiters.remove(scanKey)
            waiter
        }
        removed?.complete(null)
    }

    private suspend fun hasWaiters(scanKey: String): Boolean = mutex.withLock {
        waiters[scanKey]?.isNotEmpty() == true
    }

    private suspend fun abandonIfEmpty(scanKey: String): Boolean = mutex.withLock {
        if (waiters[scanKey]?.isNotEmpty() == true) {
            false
        } else {
            scanning.remove(scanKey)
            waiters.remove(scanKey)
            waiterCounts.remove(scanKey)
            true
        }
    }

    private suspend fun finish(
        scanKey: String,
        path: String,
        safeWorkId: String,
        epubFile: File,
        revision: String,
        jpegBytes: ByteArray?
    ) {
        // A file replacement during extraction must not publish an image from the old EPUB.
        val current = revisionOf(epubFile)
        val resultBytes = if (current == revision) jpegBytes else null
        val bitmap = resultBytes?.let { bytes ->
            runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
        }
        if (current == revision) {
            runCatching {
                directory.mkdirs()
                val basename = "$safeWorkId-$revision"
                val destination = File(directory, basename + if (resultBytes == null) ".empty" else ".jpg")
                writeAtomically(destination, resultBytes ?: ByteArray(0))
                val prefix = "$safeWorkId-"
                directory.listFiles()?.forEach { existing ->
                    if (existing.name.startsWith(prefix) && existing.name != destination.name) {
                        existing.delete()
                    }
                }
            }
            memory.put(path, CacheEntry(bitmap, revision))
            hasArtMemory.put(path, HasArtEntry(bitmap != null, revision))
        }
        val pending = mutex.withLock {
            scanning.remove(scanKey)
            waiterCounts.remove(scanKey)
            waiters.remove(scanKey)
        }
        pending?.values?.forEach { it.complete(bitmap) }
    }

    private fun writeAtomically(destination: File, bytes: ByteArray) {
        val temp = File(destination.parentFile, ".${destination.name}.${UUID.randomUUID()}.tmp")
        try {
            temp.writeBytes(bytes)
            if (!temp.renameTo(destination)) {
                destination.writeBytes(bytes)
                temp.delete()
            }
        } catch (error: Throwable) {
            temp.delete()
            throw error
        }
    }

    private class HasArtCache(private val maxCount: Int) {
        private val entries = LinkedHashMap<String, HasArtEntry>(maxCount, 0.75f, true)

        @Synchronized
        fun get(key: String): HasArtEntry? = entries[key]

        @Synchronized
        fun put(key: String, entry: HasArtEntry) {
            entries[key] = entry
            val iterator = entries.entries.iterator()
            while (entries.size > maxCount && iterator.hasNext()) {
                iterator.next()
                iterator.remove()
            }
        }

        @Synchronized
        fun remove(key: String) {
            entries.remove(key)
        }
    }

    private class MemoryCache(
        private val maxCount: Int,
        private val maxBytes: Long
    ) {
        private val entries = LinkedHashMap<String, Pair<CacheEntry, Long>>(maxCount, 0.75f, true)
        private var currentBytes: Long = 0L

        @Synchronized
        fun get(key: String): CacheEntry? = entries[key]?.first

        @Synchronized
        fun put(key: String, entry: CacheEntry) {
            val cost = costOf(entry.bitmap)
            entries.remove(key)?.let { (_, previousCost) -> currentBytes -= previousCost }
            entries[key] = entry to cost
            currentBytes += cost
            val iterator = entries.entries.iterator()
            while ((entries.size > maxCount || currentBytes > maxBytes) && iterator.hasNext()) {
                val eldest = iterator.next()
                currentBytes -= eldest.value.second
                iterator.remove()
            }
        }

        @Synchronized
        fun remove(key: String) {
            entries.remove(key)?.let { (_, previousCost) -> currentBytes -= previousCost }
        }

        private fun costOf(bitmap: Bitmap?): Long {
            if (bitmap == null) return 1L
            return maxOf(1L, bitmap.allocationByteCount.toLong())
        }
    }

    companion object {
        private const val MAX_MEMORY_ENTRIES = 64
        private const val MAX_HAS_ART_ENTRIES = 256
        private const val MAX_MEMORY_BYTES = 80L * 1024L * 1024L
        private const val MIN_MEMORY_BYTES = 8L * 1024L * 1024L
        private const val CACHE_DIR_NAME = "GeneratedCoverArt"

        private val sharedInstances = ConcurrentHashMap<String, EmbeddedCoverArtLoader>()

        fun shared(context: Context): EmbeddedCoverArtLoader {
            val dir = File(context.applicationContext.cacheDir, CACHE_DIR_NAME)
            return sharedInstances.computeIfAbsent(dir.absolutePath) {
                EmbeddedCoverArtLoader(directory = dir)
            }
        }

        internal fun revisionOf(file: File): String? {
            if (!file.isFile) return null
            val modified = file.lastModified()
            if (modified <= 0L) return null
            return "$modified-${file.length()}"
        }

        private fun cacheKey(file: File, revision: String): String =
            "${file.absolutePath}|$revision"

        private fun sanitizeId(workId: String): String =
            workId.replace(Regex("[^A-Za-z0-9_-]"), "_").ifEmpty { "work" }

        private fun memoryBudgetBytes(): Long {
            val heapShare = Runtime.getRuntime().maxMemory() / 6L
            return heapShare.coerceIn(MIN_MEMORY_BYTES, MAX_MEMORY_BYTES)
        }
    }
}

/**
 * Loads the embedded cover art for [work] off the main thread when both [enabled] and
 * [CoverArtResolution.shouldUseEmbeddedArt] allow it. Returns `null` while loading,
 * when disabled/obscured, or when the EPUB has no qualifying embedded image.
 */
@Composable
fun rememberWorkEmbeddedCoverArt(
    work: SavedWork?,
    enabled: Boolean = true,
    globalUseEmbeddedCoverArt: Boolean = LocalUseEmbeddedCoverArt.current
): ImageBitmap? {
    val shouldShow = enabled &&
        work != null &&
        work.hasEpub &&
        CoverArtResolution.shouldUseEmbeddedArt(
            globalUseEmbeddedCoverArt = globalUseEmbeddedCoverArt,
            workPreferenceRaw = work.coverArtPreferenceRaw,
            hasEmbeddedArt = true
        )
    return rememberLoadedEmbeddedCoverArt(
        workId = if (shouldShow) work?.id else null,
        epubDigest = if (shouldShow) work?.epubDigest.orEmpty() else "",
        downloadedAtMillis = if (shouldShow) work?.downloadedAt?.toEpochMilli() ?: 0L else 0L
    )
}

/**
 * Checks off the main thread whether [work]'s local EPUB contains qualifying embedded cover art,
 * regardless of the global or per-work cover toggle (drives visibility of Work Detail's Cover choice).
 */
@Composable
fun rememberWorkHasEmbeddedCoverArt(work: SavedWork?): Boolean {
    val context = LocalContext.current
    val loader = remember(context) { EmbeddedCoverArtLoader.shared(context) }
    val activeWork = work?.takeIf { it.hasEpub }
    val workId = activeWork?.id
    val epubDigest = activeWork?.epubDigest.orEmpty()
    val downloadedAtMillis = activeWork?.downloadedAt?.toEpochMilli() ?: 0L
    val epubFile = remember(workId, context) {
        workId?.let { id ->
            runCatching { WorkFileStore(context.filesDir.toPath()).workEpubPath(id).toFile() }.getOrNull()
        }
    }
    val initialHasArt = remember(workId, epubFile, epubDigest, downloadedAtMillis) {
        if (workId == null || epubFile == null) false else loader.peekHasArt(epubFile) ?: false
    }
    // State keyed like the load, so a reused composable never shows the previous work's answer while the new one loads
    // (produceState would keep the old value until its producer sets a new one).
    val hasArt = remember(workId, epubFile, epubDigest, downloadedAtMillis) { mutableStateOf(initialHasArt) }
    LaunchedEffect(workId, epubFile, epubDigest, downloadedAtMillis) {
        hasArt.value = if (workId == null || epubFile == null) false
        else loader.hasEmbeddedArt(workId = workId, epubFile = epubFile)
    }
    return workId != null && hasArt.value
}

@Composable
private fun rememberLoadedEmbeddedCoverArt(
    workId: String?,
    epubDigest: String,
    downloadedAtMillis: Long
): ImageBitmap? {
    val context = LocalContext.current
    val loader = remember(context) { EmbeddedCoverArtLoader.shared(context) }
    val epubFile = remember(workId, context) {
        workId?.let { id ->
            runCatching { WorkFileStore(context.filesDir.toPath()).workEpubPath(id).toFile() }.getOrNull()
        }
    }
    val initialBitmap = remember(workId, epubFile, epubDigest, downloadedAtMillis) {
        if (workId == null || epubFile == null) null else loader.peekCached(epubFile)?.bitmap
    }
    // Keyed state, not produceState: see rememberWorkHasEmbeddedCoverArt.
    val bitmapState = remember(workId, epubFile, epubDigest, downloadedAtMillis) { mutableStateOf(initialBitmap) }
    LaunchedEffect(workId, epubFile, epubDigest, downloadedAtMillis) {
        bitmapState.value = if (workId == null || epubFile == null) null
        else loader.load(workId = workId, epubFile = epubFile)
    }
    val bitmap = bitmapState.value
    return remember(workId, bitmap) { if (workId == null) null else bitmap?.asImageBitmap() }
}
