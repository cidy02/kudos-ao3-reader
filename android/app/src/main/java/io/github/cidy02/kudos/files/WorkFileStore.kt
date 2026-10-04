package io.github.cidy02.kudos.files

import io.github.cidy02.kudos.backup.BackupPaths
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class WorkFileStore(
    private val filesRoot: Path
) {
    private val worksDirectory: Path
        get() = filesRoot.resolve("works").normalize()

    suspend fun writeWorkEpub(workId: String, bytes: ByteArray): FileWriteResult {
        if (bytes.isEmpty()) return FileWriteResult.Failure("EPUB download was empty.")
        return withContext(Dispatchers.IO) {
            try {
                val destination = workEpubPath(workId)
                Files.createDirectories(worksDirectory)
                val temp = Files.createTempFile(worksDirectory, ".$workId-", ".tmp")
                try {
                    Files.write(temp, bytes)
                    try {
                        Files.move(
                            temp,
                            destination,
                            StandardCopyOption.REPLACE_EXISTING,
                            StandardCopyOption.ATOMIC_MOVE
                        )
                    } catch (_: IOException) {
                        Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING)
                    }
                    FileWriteResult.Success(destination)
                } finally {
                    Files.deleteIfExists(temp)
                }
            } catch (error: Exception) {
                FileWriteResult.Failure(error.message ?: "Could not write EPUB file.", error)
            }
        }
    }

    suspend fun deleteWorkEpub(workId: String): Boolean {
        return withContext(Dispatchers.IO) {
            runCatching { Files.deleteIfExists(workEpubPath(workId)) }.getOrDefault(false)
        }
    }

    suspend fun workEpubExists(workId: String): Boolean {
        return withContext(Dispatchers.IO) {
            runCatching { Files.isRegularFile(workEpubPath(workId)) }.getOrDefault(false)
        }
    }

    fun workEpubPath(workId: String): Path {
        val uuid = UUID.fromString(workId).toString()
        val path = worksDirectory.resolve("$uuid.epub").normalize()
        require(path.startsWith(worksDirectory)) { "Unsafe work EPUB path." }
        return path
    }

    /**
     * Archives the bytes a converted work was built *from* (iOS
     * `UserDocumentImport` + `WorkConversionRecord`), so "Rebuild from Original"
     * can re-run a newer converter over the same source without asking the user
     * to find the file again. Kept beside the EPUB and removed with it.
     */
    suspend fun writeOriginal(workId: String, extension: String, bytes: ByteArray): FileWriteResult {
        if (bytes.isEmpty()) return FileWriteResult.Failure("Original file was empty.")
        return withContext(Dispatchers.IO) {
            try {
                Files.createDirectories(originalsDirectory)
                val destination = originalPath(workId, extension)
                // iOS `Storage.originalDocumentURL` / backup restore preserve local
                // originals. A failed re-import must preserve them too: install first.
                val previous = findOriginal(workId)
                val temp = Files.createTempFile(originalsDirectory, ".$workId-", ".tmp")
                try {
                    Files.write(temp, bytes)
                    try {
                        Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
                    } catch (_: IOException) {
                        Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING)
                    }
                    if (previous != null && previous != destination) Files.deleteIfExists(previous)
                    Files.deleteIfExists(conversionRecordPath(workId))
                    FileWriteResult.Success(destination)
                } finally {
                    Files.deleteIfExists(temp)
                }
            } catch (error: Exception) {
                FileWriteResult.Failure(error.message ?: "Could not archive the original file.", error)
            }
        }
    }

    /** The archived original, if this work was converted from one. */
    suspend fun readOriginal(workId: String): Pair<String, ByteArray>? {
        return withContext(Dispatchers.IO) {
            runCatching {
                findOriginal(workId)?.let { path ->
                    path.fileName.toString().substringAfterLast('.') to Files.readAllBytes(path)
                }
            }.getOrNull()
        }
    }

    suspend fun originalExists(workId: String): Boolean =
        withContext(Dispatchers.IO) { runCatching { findOriginal(workId) != null }.getOrDefault(false) }

    suspend fun deleteOriginal(workId: String): Boolean =
        withContext(Dispatchers.IO) { runCatching { deleteOriginalFiles(workId) }.getOrDefault(false) }

    /** The archived original's file, if there is one: for its size and name without reading it. */
    fun originalFile(workId: String): Path? = runCatching { findOriginal(workId) }.getOrNull()

    /**
     * iOS `WorkConversionRecord`, `<work>.conversion.json` beside the original: which converter
     * made the EPUB, and from which file. Android writes none of its own. It keeps the one a
     * backup or the sync folder brings, byte for byte, and writes it back out, so a library
     * that passes through Android still has it.
     */
    suspend fun conversionRecordExists(workId: String): Boolean = withContext(Dispatchers.IO) {
        runCatching { Files.isRegularFile(conversionRecordPath(workId)) }.getOrDefault(false)
    }

    suspend fun readConversionRecord(workId: String): ByteArray? = withContext(Dispatchers.IO) {
        runCatching {
            conversionRecordPath(workId).takeIf { Files.isRegularFile(it) }?.let { Files.readAllBytes(it) }
        }.getOrNull()
    }

    suspend fun writeConversionRecord(workId: String, bytes: ByteArray): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            Files.createDirectories(originalsDirectory)
            Files.write(conversionRecordPath(workId), bytes)
        }.isSuccess
    }

    private fun findOriginal(workId: String): Path? {
        val uuid = UUID.fromString(workId).toString()
        if (!Files.isDirectory(originalsDirectory)) return null
        val record = conversionRecordPath(workId)
        Files.newDirectoryStream(originalsDirectory, "$uuid.*").use { stream ->
            // The conversion record shares the prefix and is not the original (iOS
            // `existingOriginalDocumentURL`): rebuilding would try to convert its own bookkeeping.
            return stream.firstOrNull { Files.isRegularFile(it) && it != record }
        }
    }

    private fun deleteOriginalFiles(workId: String): Boolean {
        // The record describes the original it sits beside, and goes with it.
        Files.deleteIfExists(conversionRecordPath(workId))
        val existing = findOriginal(workId) ?: return false
        return Files.deleteIfExists(existing)
    }

    private fun conversionRecordPath(workId: String): Path =
        originalsDirectory.resolve("${UUID.fromString(workId)}${BackupPaths.CONVERSION_RECORD_SUFFIX}").normalize()

    private val originalsDirectory: Path
        get() = filesRoot.resolve("originals").normalize()

    private fun originalPath(workId: String, extension: String): Path {
        val uuid = UUID.fromString(workId).toString()
        val safeExtension = extension.lowercase().filter { it.isLetterOrDigit() }.ifEmpty { "bin" }
        val path = originalsDirectory.resolve("$uuid.$safeExtension").normalize()
        require(path.startsWith(originalsDirectory)) { "Unsafe original file path." }
        return path
    }

    fun fontPath(fileName: String): Path {
        BackupPaths.requireSafeFontFileName(fileName)
        val fontsDirectory = filesRoot.resolve("fonts").normalize()
        val path = fontsDirectory.resolve(fileName).normalize()
        require(path.startsWith(fontsDirectory)) { "Unsafe font path." }
        return path
    }

    suspend fun fontExists(fileName: String): Boolean {
        return withContext(Dispatchers.IO) {
            val path = runCatching { fontPath(fileName) }.getOrNull() ?: return@withContext false
            runCatching { Files.isRegularFile(path) }.getOrDefault(false)
        }
    }
}
