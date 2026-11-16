package io.github.cidy02.kudos.ui.components

import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
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
 * One queued scan per file revision. The cache is derived data under the app's cacheDir,
 * never a library field. Port of iOS `GeneratedCoverArtLoader.swift`.
 */
class GeneratedCoverArtLoader<T : Any>(
    private val directory: File,
    private val scan: (File) -> ByteArray? = { EmbeddedWorkCoverImage.data(it) },
    private val downsample: (ByteArray?) -> ByteArray? = { EmbeddedWorkCoverImage.downsampledJPEG(it) },
    private val decode: (ByteArray) -> T?,
    private val costBytes: (T) -> Int = { 1 },
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    private class Entry<T : Any>(val image: T?, val cost: Int)

    private val memory = object {
        private val maxCount = 64
        private val maxTotalBytes = 80 * 1024 * 1024
        private val map = LinkedHashMap<String, Entry<T>>(64, 0.75f, true)
        private var totalBytes = 0

        @Synchronized
        operator fun get(key: String): Entry<T>? = map[key]

        @Synchronized
        fun put(key: String, image: T?) {
            val cost = image?.let(costBytes)?.coerceAtLeast(1) ?: 1
            map.remove(key)?.let { totalBytes -= it.cost }
            map[key] = Entry(image, cost)
            totalBytes += cost
            val iter = map.entries.iterator()
            while (iter.hasNext() && (map.size > maxCount || totalBytes > maxTotalBytes)) {
                val eldest = iter.next()
                totalBytes -= eldest.value.cost
                iter.remove()
            }
        }
    }

    private val mutex = Mutex()
    private val scanning = HashSet<String>()
    private val waiters = HashMap<String, MutableMap<String, CompletableDeferred<T?>>>()
    private var tail: Job? = null

    suspend fun image(workId: String, file: File): T? {
        // isFile and lastModified are disk stats. Callers (LaunchedEffect) run on Main.
        val located = withContext(Dispatchers.IO) {
            if (!file.isFile) {
                null
            } else {
                val revision = file.lastModified().toString()
                revision to "${file.absolutePath}|$revision"
            }
        } ?: return null
        val (revision, key) = located
        memory[key]?.let { return it.image }

        val basename = "$workId-$revision"
        val jpeg = File(directory, "$basename.jpg")
        val empty = File(directory, "$basename.empty")
        val diskHit = withContext(Dispatchers.IO) {
            if (jpeg.isFile) {
                val bytes = runCatching { jpeg.readBytes() }.getOrNull()
                val decoded = bytes?.let(decode)
                if (decoded != null) return@withContext Entry(decoded, 1)
            }
            if (empty.isFile) {
                return@withContext Entry<T>(null, 1)
            }
            null
        }
        if (diskHit != null) {
            memory.put(key, diskHit.image)
            return diskHit.image
        }

        val waiterId = UUID.randomUUID().toString()
        val deferred = CompletableDeferred<T?>()
        mutex.withLock {
            memory[key]?.let { return it.image }
            waiters.getOrPut(key) { HashMap() }[waiterId] = deferred
            if (scanning.add(key)) {
                val previous = tail
                tail = scope.launch {
                    previous?.join()
                    val shouldScan = mutex.withLock { !waiters[key].isNullOrEmpty() }
                    if (!shouldScan) {
                        abandon(key)
                        return@launch
                    }
                    val data = runCatching { downsample(scan(file)) }.getOrNull()
                    finish(key = key, workId = workId, file = file, revision = revision, data = data)
                }
            }
        }

        return try {
            deferred.await()
        } finally {
            withContext(NonCancellable) {
                mutex.withLock {
                    waiters[key]?.remove(waiterId)
                }
            }
        }
    }

    private suspend fun abandon(key: String) {
        val orphaned = mutex.withLock {
            scanning.remove(key)
            waiters.remove(key)?.values?.toList().orEmpty()
        }
        for (continuation in orphaned) {
            continuation.complete(null)
        }
    }

    private suspend fun finish(
        key: String,
        workId: String,
        file: File,
        revision: String,
        data: ByteArray?
    ) {
        // A replacement during extraction must not publish an image from the old EPUB.
        val current = if (file.isFile) file.lastModified().toString() else null
        val result = if (current == revision) data else null
        val image = result?.let(decode)
        if (current == revision) {
            runCatching {
                if (!directory.exists()) directory.mkdirs()
                val basename = "$workId-$revision"
                val destination = File(directory, basename + if (result == null) ".empty" else ".jpg")
                val temp = File(directory, ".$basename.${UUID.randomUUID()}.tmp")
                try {
                    temp.writeBytes(result ?: ByteArray(0))
                    try {
                        Files.move(
                            temp.toPath(),
                            destination.toPath(),
                            StandardCopyOption.REPLACE_EXISTING,
                            StandardCopyOption.ATOMIC_MOVE
                        )
                    } catch (_: Exception) {
                        Files.move(
                            temp.toPath(),
                            destination.toPath(),
                            StandardCopyOption.REPLACE_EXISTING
                        )
                    }
                } finally {
                    temp.delete()
                }
                val prefix = "$workId-"
                directory.listFiles()?.forEach { old ->
                    if (old.name.startsWith(prefix) && old != destination) {
                        old.delete()
                    }
                }
            }
            memory.put(key, image)
        }
        val waiting = mutex.withLock {
            scanning.remove(key)
            waiters.remove(key)?.values?.toList().orEmpty()
        }
        for (continuation in waiting) {
            continuation.complete(image)
        }
    }

    companion object {
        private val instances = ConcurrentHashMap<String, GeneratedCoverArtLoader<ImageBitmap>>()

        fun forCacheDir(cacheDir: File): GeneratedCoverArtLoader<ImageBitmap> {
            val dir = File(cacheDir, "GeneratedCoverArt")
            return instances.computeIfAbsent(dir.absolutePath) {
                GeneratedCoverArtLoader(
                    directory = dir,
                    decode = { bytes ->
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
                    },
                    costBytes = { bitmap -> bitmap.width * bitmap.height * 4 }
                )
            }
        }
    }
}
