package io.github.cidy02.kudos.network.ao3.browse

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Local-first, on-disk cache of each media category's full fandom list, so the
 * heavy `/media/<category>/fandoms` pages (thousands of fandoms each) aren't
 * re-scraped every time Browse opens. Mirrors iOS `FandomCatalogCache`: a
 * single JSON file in the evictable cache directory, keyed by category name,
 * each entry carrying its fetch time so staleness can be checked without a
 * network call.
 */
class FandomCatalogCache(private val cacheDir: Path) {
    @Serializable
    data class Entry(val fandoms: List<AO3Fandom>, val fetchedAtEpochMillis: Long)

    private val json = Json { ignoreUnknownKeys = true }
    private val filePath: Path get() = cacheDir.resolve(FILE_NAME)

    /** Reads cached entries keyed by category name. Empty if absent/unreadable. */
    suspend fun load(): Map<String, Entry> = withContext(Dispatchers.IO) {
        if (!Files.isRegularFile(filePath)) return@withContext emptyMap()
        runCatching {
            json.decodeFromString<Map<String, Entry>>(Files.readString(filePath))
        }.getOrDefault(emptyMap())
    }

    /**
     * Atomically writes the entries (temp file + move, mirrors
     * [io.github.cidy02.kudos.files.FontFileStore]). Best-effort: a failed
     * write just means the next launch re-scrapes.
     */
    suspend fun save(entries: Map<String, Entry>) = withContext(Dispatchers.IO) {
        runCatching {
            Files.createDirectories(cacheDir)
            val temp = Files.createTempFile(cacheDir, ".fandom-catalog-", ".json.tmp")
            try {
                Files.writeString(temp, json.encodeToString(entries))
                try {
                    Files.move(
                        temp,
                        filePath,
                        StandardCopyOption.REPLACE_EXISTING,
                        StandardCopyOption.ATOMIC_MOVE
                    )
                } catch (_: Exception) {
                    Files.move(temp, filePath, StandardCopyOption.REPLACE_EXISTING)
                }
            } finally {
                Files.deleteIfExists(temp)
            }
        }
        Unit
    }

    /** Removes the cache file (Privacy & Local Data "Clear Browse Cache"). Rebuilds next open. */
    suspend fun clear() = withContext(Dispatchers.IO) {
        runCatching { Files.deleteIfExists(filePath) }
        Unit
    }

    companion object {
        private const val FILE_NAME = "fandom-catalog.json"

        /** Fandom counts drift slowly; refresh a category at most about once a week. */
        val MaxAge: Duration = Duration.ofDays(7)

        fun isStale(entry: Entry?, now: Instant = Instant.now()): Boolean {
            if (entry == null) return true
            return Duration.between(Instant.ofEpochMilli(entry.fetchedAtEpochMillis), now) > MaxAge
        }
    }
}
