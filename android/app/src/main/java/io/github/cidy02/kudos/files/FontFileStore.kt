package io.github.cidy02.kudos.files

import io.github.cidy02.kudos.backup.BackupPaths
import io.github.cidy02.kudos.backup.BackupLimits
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

    suspend fun readAllFontFiles(
        contentRequiredForFileNames: Set<String> = emptySet()
    ): Map<String, ByteArray> {
        return withContext(Dispatchers.IO) {
            if (!Files.isDirectory(fontsDirectory)) return@withContext emptyMap()
            val requiredFoldedNames = contentRequiredForFileNames.mapTo(mutableSetOf()) {
                BackupPaths.fontFileNameKey(it)
            }
            Files.newDirectoryStream(fontsDirectory).use { stream ->
                stream
                    .filter(Files::isRegularFile)
                    .sortedBy { it.fileName.toString() }
                    .mapNotNull { path ->
                        val fileName = path.fileName.toString()
                        runCatching {
                            BackupPaths.requireSafeFontFileName(fileName)
                            val bytes = if (BackupPaths.fontFileNameKey(fileName) in requiredFoldedNames) {
                                runCatching {
                                    Files.newInputStream(path).use { input ->
                                        val maxBytes = (BackupLimits.MAX_FONT_ENTRY_BYTES + 1).toInt()
                                        val buffer = ByteArray(maxBytes)
                                        var totalRead = 0
                                        while (totalRead < maxBytes) {
                                            val read = input.read(buffer, totalRead, maxBytes - totalRead)
                                            if (read == -1) break
                                            totalRead += read
                                        }
                                        val bytes = buffer.copyOf(totalRead)
                                        bytes.takeIf {
                                            it.size.toLong() <= BackupLimits.MAX_FONT_ENTRY_BYTES
                                        }
                                    }
                                }.getOrNull()
                            } else {
                                null
                            }
                            // Every local file reserves its name. Only names that can
                            // collide with this incoming package have their bytes read,
                            // keeping snapshot memory bounded by the package's 32 MiB cap.
                            fileName to (bytes ?: ByteArray(0))
                        }.getOrNull()
                    }
                    .toMap(linkedMapOf())
            }
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

    suspend fun deleteFont(fileName: String): Boolean {
        return withContext(Dispatchers.IO) {
            val path = runCatching { fontPath(fileName) }.getOrNull() ?: return@withContext false
            runCatching { Files.deleteIfExists(path) }.getOrDefault(false)
        }
    }

    suspend fun fontExists(fileName: String): Boolean {
        return withContext(Dispatchers.IO) {
            val path = runCatching { fontPath(fileName) }.getOrNull() ?: return@withContext false
            runCatching { Files.isRegularFile(path) }.getOrDefault(false)
        }
    }
}
