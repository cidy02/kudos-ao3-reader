package io.github.cidy02.kudos.files

import io.github.cidy02.kudos.backup.BackupPaths
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Local font files under `files/fonts/`. Paths are constrained with the same
 * backup-safe filename rules as ZIP font entries.
 */
class FontFileStore(
    private val filesRoot: Path
) {
    private val fontsDirectory: Path
        get() = filesRoot.resolve("fonts").normalize()

    fun fontPath(fileName: String): Path {
        BackupPaths.requireSafeFontFileName(fileName)
        val path = fontsDirectory.resolve(fileName).normalize()
        require(path.startsWith(fontsDirectory)) { "Unsafe font path." }
        return path
    }

    suspend fun readFont(fileName: String): ByteArray? {
        return withContext(Dispatchers.IO) {
            val path = runCatching { fontPath(fileName) }.getOrNull() ?: return@withContext null
            if (!Files.isRegularFile(path)) return@withContext null
            runCatching { Files.readAllBytes(path) }.getOrNull()
        }
    }

    suspend fun writeFont(fileName: String, bytes: ByteArray): FileWriteResult {
        if (bytes.isEmpty()) return FileWriteResult.Failure("Font file was empty.")
        return withContext(Dispatchers.IO) {
            try {
                BackupPaths.requireSafeFontFileName(fileName)
                Files.createDirectories(fontsDirectory)
                val destination = fontPath(fileName)
                val temp = Files.createTempFile(fontsDirectory, ".$fileName-", ".tmp")
                try {
                    Files.write(temp, bytes)
                    try {
                        Files.move(
                            temp,
                            destination,
                            StandardCopyOption.REPLACE_EXISTING,
                            StandardCopyOption.ATOMIC_MOVE
                        )
                    } catch (_: Exception) {
                        Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING)
                    }
                    FileWriteResult.Success(destination)
                } finally {
                    Files.deleteIfExists(temp)
                }
            } catch (error: Exception) {
                FileWriteResult.Failure(error.message ?: "Could not write font file.", error)
            }
        }
    }
}
