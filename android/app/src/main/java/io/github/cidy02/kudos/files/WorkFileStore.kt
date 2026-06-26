package io.github.cidy02.kudos.files

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
}
