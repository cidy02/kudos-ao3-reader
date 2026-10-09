package io.github.cidy02.kudos.settings

import android.system.Os
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.text.NumberFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

/** The same file categories as iOS LocalStorageFootprint; no writing or network access. */
data class LocalStorageFootprint(
    val downloadedWorkBytes: Long,
    val readingCopyBytes: Long,
    val preservedOriginalBytes: Long,
    val importedFontBytes: Long,
    val draftRecoveryBytes: Long,
    val cacheBytes: Long,
    val readingPositions: Int,
    val localCollections: Int,
    val savedSearches: Int
) {
    fun sizeRows(): List<Pair<String, Long>> = buildList {
        add("Downloaded works" to downloadedWorkBytes)
        if (readingCopyBytes > 0) add("Works you're reading" to readingCopyBytes)
        if (preservedOriginalBytes > 0) add("Original files kept" to preservedOriginalBytes)
        if (importedFontBytes > 0) add("Imported fonts" to importedFontBytes)
        add("Draft recovery" to draftRecoveryBytes)
        add("Caches" to cacheBytes)
    }

    companion object {
        /** ByteCountFormatter(.file): decimal units, numeric zero, adaptive precision. */
        fun formatted(bytes: Long): String {
            val positive = bytes.coerceAtLeast(0)
            if (positive < 1_000) return "$positive ${if (positive == 1L) "byte" else "bytes"}"
            val units = listOf("KB", "MB", "GB", "TB", "PB", "EB")
            var amount = positive.toDouble() / 1_000
            var index = 0
            while (amount >= 1_000 && index < units.lastIndex) {
                amount /= 1_000
                index++
            }
            val number = NumberFormat.getNumberInstance().apply {
                maximumFractionDigits = minOf(index, 2)
                minimumFractionDigits = 0
            }
            return "${number.format(amount)} ${units[index]}"
        }
    }
}

class LocalDataFootprintScanner(
    private val database: KudosDatabase,
    private val works: WorkRepository,
    private val filesRoot: Path,
    private val cacheRoot: Path
) {
    suspend fun measure(): LocalStorageFootprint = withContext(Dispatchers.IO) {
        val fileStore = WorkFileStore(filesRoot)
        val readingBytes = works.observeLibraryWorks().first()
            .filter { it.hasEpub && !it.isDownloaded }
            .sumOf { work -> runCatching { Files.size(fileStore.workEpubPath(work.id)) }.getOrDefault(0L) }
        LocalStorageFootprint(
            downloadedWorkBytes = (directorySize(filesRoot.resolve("works")) - readingBytes).coerceAtLeast(0),
            readingCopyBytes = readingBytes,
            preservedOriginalBytes = directorySize(filesRoot.resolve("originals")),
            importedFontBytes = directorySize(filesRoot.resolve("fonts")),
            draftRecoveryBytes = directorySize(WritingTextRecovery.inFilesDir(filesRoot).directory),
            // Android's persisted Browse metadata cache. Readium streams ZIP entries;
            // there is no app-owned Reader unzip directory. Voice packs/import staging
            // and WebView caches are not either of iOS's measured cache categories.
            cacheBytes = fileSize(cacheRoot.resolve("fandom-catalog.json")),
            readingPositions = works.observePositionedWorks().first().size,
            localCollections = database.collectionDao().getAll().size,
            savedSearches = database.savedSearchDao().getAll().size
        )
    }

    private fun directorySize(directory: Path): Long {
        if (!Files.isDirectory(directory, NOFOLLOW_LINKS)) return 0
        // Skip hidden files/directories and symlinks, as iOS's enumerator does.
        return runCatching {
            Files.newDirectoryStream(directory).use { entries ->
                entries.sumOf { path ->
                    if (path.fileName.toString().startsWith(".")) 0L
                    else if (Files.isDirectory(path, NOFOLLOW_LINKS)) directorySize(path)
                    else fileSize(path)
                }
            }
        }.getOrDefault(0)
    }

    private fun fileSize(path: Path): Long {
        if (!Files.isRegularFile(path, NOFOLLOW_LINKS)) return 0
        return runCatching {
            val logical = Files.size(path)
            // POSIX st_blocks counts 512-byte allocated blocks. On providers without
            // allocation metadata (including JVM tests), fall back to logical size.
            runCatching {
                val stat = Os.stat(path.toString())
                // A valid sparse file may occupy zero blocks. A missing block size
                // means this provider did not supply allocation metadata at all.
                if (stat.st_blksize > 0 && stat.st_blocks >= 0) stat.st_blocks * 512L else logical
            }.getOrDefault(logical)
        }.getOrDefault(0)
    }
}
