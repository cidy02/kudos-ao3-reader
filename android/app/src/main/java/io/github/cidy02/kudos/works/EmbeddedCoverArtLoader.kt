package io.github.cidy02.kudos.works

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
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

/**
 * One queued scan per EPUB file revision, caching decoded thumbnails in memory and under
 * `cacheDir/GeneratedCoverArt` (derived data only, never a library field).
 *
 * Port of iOS `GeneratedCoverArtLoader` (`UIComponents/GeneratedCoverArtLoader.swift:5-118`).
 */
class EmbeddedCoverArtLoader(
    private val directory: File,
    private val scan: (File) -> ByteArray? = { EmbeddedWorkCoverImage.data(it) },
    private val scanDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    /** `bitmap == null` represents a scanned "no embedded art" negative cache entry. */
    class CacheEntry(val bitmap: Bitmap?)

    private val memory = MemoryCache(
        maxCount = MAX_MEMORY_ENTRIES,
        maxBytes = memoryBudgetBytes()
    )
    private val scope = CoroutineScope(SupervisorJob() + scanDispatcher)
    private val mutex = Mutex()
    private var tail: Job? = null
    private val scanning = mutableSetOf<String>()
    private val waiters = mutableMapOf<String, MutableMap<String, CompletableDeferred<Bitmap?>>>()

    /** Synchronous in-memory cache lookup so scrolled/recomposed cards draw without flicker. */
    fun peekCached(epubFile: File): CacheEntry? {
        val revision = revisionOf(epubFile) ?: return null
        return memory.get(cacheKey(epubFile, revision))
    }

    suspend fun load(workId: String, epubFile: File): Bitmap? {
        val revision = revisionOf(epubFile) ?: return null
        val key = cacheKey(epubFile, revision)
        memory.get(key)?.let { return it.bitmap }

        val safeWorkId = sanitizeId(workId)
        val basename = "$safeWorkId-$revision"
        val diskHit = withContext(scanDispatcher) {
            val jpeg = File(directory, "$basename.jpg")
            if (jpeg.isFile) {
                val decoded = runCatching {
                    val bytes = jpeg.readBytes()
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }.getOrNull()
                if (decoded != null) {
                    memory.put(key, CacheEntry(decoded))
                    return@withContext CacheEntry(decoded)
                }
            }
            val empty = File(directory, "$basename.empty")
            if (empty.isFile) {
                memory.put(key, CacheEntry(null))
                return@withContext CacheEntry(null)
            }
            null
        }
        if (diskHit != null) return diskHit.bitmap

        val waiterId = UUID.randomUUID().toString()
        val deferred = CompletableDeferred<Bitmap?>()
        mutex.withLock {
            memory.get(key)?.let { return it.bitmap }
            waiters.getOrPut(key) { linkedMapOf() }[waiterId] = deferred
            if (scanning.add(key)) {
                val previous = tail
                tail = scope.launch(scanDispatcher) {
                    previous?.join()
                    if (!hasWaiters(key)) {
                        abandon(key)
                        return@launch
                    }
                    val raw = runCatching { scan(epubFile) }.getOrNull()
                    val jpegBytes = EmbeddedWorkCoverImage.downsampledJPEG(raw)
                    finish(
                        key = key,
                        safeWorkId = safeWorkId,
                        epubFile = epubFile,
                        revision = revision,
                        jpegBytes = jpegBytes
                    )
                }
            }
        }

        return try {
            deferred.await()
        } finally {
            if (!deferred.isCompleted) {
                withContext(NonCancellable) {
                    cancelWaiter(key, waiterId)
                }
            }
        }
    }

    private suspend fun cancelWaiter(key: String, waiterId: String) {
        val removed = mutex.withLock {
            val entries = waiters[key] ?: return@withLock null
            val waiter = entries.remove(waiterId)
            if (entries.isEmpty()) waiters.remove(key)
            waiter
        }
        removed?.complete(null)
    }

    private suspend fun hasWaiters(key: String): Boolean = mutex.withLock {
        waiters[key]?.isNotEmpty() == true
    }

    private suspend fun abandon(key: String) {
        val pending = mutex.withLock {
            scanning.remove(key)
            waiters.remove(key)
        }
        pending?.values?.forEach { it.complete(null) }
    }

    private suspend fun finish(
        key: String,
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
            memory.put(key, CacheEntry(bitmap))
        }
        val pending = mutex.withLock {
            scanning.remove(key)
            waiters.remove(key)
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

        private fun costOf(bitmap: Bitmap?): Long {
            if (bitmap == null) return 1L
            return maxOf(1L, bitmap.allocationByteCount.toLong())
        }
    }

    companion object {
        private const val MAX_MEMORY_ENTRIES = 64
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
        epubDigest = if (shouldShow) work?.epubDigest.orEmpty() else ""
    )
}

/**
 * Checks off the main thread whether [work]'s local EPUB contains qualifying embedded cover art,
 * regardless of the global or per-work cover toggle (drives visibility of Work Detail's Cover choice).
 */
@Composable
fun rememberWorkHasEmbeddedCoverArt(work: SavedWork?): Boolean {
    val activeWork = work?.takeIf { it.hasEpub }
    val bitmap = rememberLoadedEmbeddedCoverArt(
        workId = activeWork?.id,
        epubDigest = activeWork?.epubDigest.orEmpty()
    )
    return bitmap != null
}

@Composable
private fun rememberLoadedEmbeddedCoverArt(
    workId: String?,
    epubDigest: String
): ImageBitmap? {
    val context = LocalContext.current
    val loader = remember(context) { EmbeddedCoverArtLoader.shared(context) }
    val epubFile = remember(workId, context) {
        workId?.let { id ->
            runCatching { WorkFileStore(context.filesDir.toPath()).workEpubPath(id).toFile() }.getOrNull()
        }
    }
    val fileRevision = epubFile?.let(EmbeddedCoverArtLoader::revisionOf)
    val initialBitmap = remember(workId, epubFile, epubDigest, fileRevision) {
        if (workId == null || epubFile == null) null else loader.peekCached(epubFile)?.bitmap
    }
    val bitmap by produceState<Bitmap?>(initialValue = initialBitmap, workId, epubFile, epubDigest, fileRevision) {
        if (workId == null || epubFile == null) {
            value = null
            return@produceState
        }
        val cached = loader.peekCached(epubFile)
        if (cached != null) {
            value = cached.bitmap
            return@produceState
        }
        value = loader.load(workId = workId, epubFile = epubFile)
    }
    return remember(workId, bitmap) { if (workId == null) null else bitmap?.asImageBitmap() }
}
