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
                // Only one original per work: a re-import replaces it.
                deleteOriginalFiles(workId)
                val temp = Files.createTempFile(originalsDirectory, ".$workId-", ".tmp")
                try {
                    Files.write(temp, bytes)
                    try {
                        Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
                    } catch (_: IOException) {
                        Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING)
                    }
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

    private fun findOriginal(workId: String): Path? {
        val uuid = UUID.fromString(workId).toString()
        if (!Files.isDirectory(originalsDirectory)) return null
        Files.newDirectoryStream(originalsDirectory, "$uuid.*").use { stream ->
            return stream.firstOrNull { Files.isRegularFile(it) }
        }
    }

    private fun deleteOriginalFiles(workId: String): Boolean {
        val existing = findOriginal(workId) ?: return false
        return Files.deleteIfExists(existing)
    }

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
