package io.github.cidy02.kudos.backup

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import java.util.zip.ZipInputStream

object BackupImporter {
    fun decodeManifest(bytes: ByteArray): KudosBackupManifest {
        return BackupValidator.decodeManifest(bytes)
    }

    fun importV2Zip(bytes: ByteArray): KudosBackupPackage {
        if (bytes.size.toLong() > BackupLimits.MAX_ARCHIVE_BYTES) {
            throw BackupError.ArchiveTooLarge()
        }
        if (!hasEndOfCentralDirectory(bytes)) {
            throw BackupError.InvalidPackage("The backup ZIP appears to be incomplete or truncated.")
        }

        var manifestBytes: ByteArray? = null
        val epubFiles = mutableMapOf<String, ByteArray>()
        val fontFiles = mutableMapOf<String, ByteArray>()
        val seenEntries = mutableSetOf<String>()

        try {
            ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val path = entry.name
                    BackupPaths.requireSafeZipEntryName(path)

                    if (entry.isDirectory) {
                        zip.closeEntry()
                        continue
                    }
                    if (!seenEntries.add(path)) throw BackupError.DuplicateEntry(path)

                    val payload = zip.readEntryBytes(path)
                    when {
                        path == BackupPaths.MANIFEST -> manifestBytes = payload
                        path.startsWith("${BackupPaths.WORKS_DIRECTORY}/") -> {
                            val workId = validateWorkEntry(path)
                            epubFiles[workId] = payload
                        }
                        path.startsWith("${BackupPaths.FONTS_DIRECTORY}/") -> {
                            val fileName = validateFontEntry(path)
                            fontFiles[fileName] = payload
                        }
                        else -> Unit
                    }
                    zip.closeEntry()
                }
            }
        } catch (error: IOException) {
            throw BackupError.InvalidPackage("The backup ZIP could not be read: ${error.message}")
        }

        val manifest = BackupValidator.decodeManifest(manifestBytes ?: throw BackupError.MissingManifest)
        if (manifest.version != BackupVersion.ZIP_V2) {
            throw BackupError.UnsupportedVersion(manifest.version)
        }

        return KudosBackupPackage(
            manifest = manifest,
            epubFilesByWorkId = epubFiles,
            fontFilesByFileName = fontFiles
        )
    }

    fun importV1Directory(root: Path): KudosBackupPackage {
        val normalizedRoot = root.toAbsolutePath().normalize()
        if (!Files.isDirectory(normalizedRoot)) {
            throw BackupError.InvalidPackage("Apple v1 backups must be directory-backed packages.")
        }

        val manifestPath = resolveInsideRoot(normalizedRoot, BackupPaths.MANIFEST)
        if (!Files.isRegularFile(manifestPath)) throw BackupError.MissingManifest

        val manifest = BackupValidator.decodeManifest(Files.readAllBytes(manifestPath))
        if (manifest.version != BackupVersion.APPLE_V1) {
            throw BackupError.UnsupportedVersion(manifest.version)
        }

        val worksDirectory = resolveInsideRoot(normalizedRoot, BackupPaths.WORKS_DIRECTORY)
        val epubFiles = mutableMapOf<String, ByteArray>()
        manifest.works.forEach { work ->
            val fileName = "${BackupPaths.canonicalUuid(work.id, "work.id")}.epub"
            val file = findCaseInsensitiveChild(worksDirectory, fileName) ?: return@forEach
            epubFiles[work.id] = readLimitedFile(file, "${BackupPaths.WORKS_DIRECTORY}/$fileName")
        }

        val fontsDirectory = resolveInsideRoot(normalizedRoot, BackupPaths.FONTS_DIRECTORY)
        val fontFiles = mutableMapOf<String, ByteArray>()
        manifest.fonts.forEach { font ->
            BackupPaths.requireSafeFontFileName(font.fileName)
            val file = findCaseInsensitiveChild(fontsDirectory, font.fileName) ?: return@forEach
            fontFiles[font.fileName] = readLimitedFile(file, "${BackupPaths.FONTS_DIRECTORY}/${font.fileName}")
        }

        return KudosBackupPackage(
            manifest = manifest,
            epubFilesByWorkId = epubFiles,
            fontFilesByFileName = fontFiles
        )
    }

    private fun validateWorkEntry(path: String): String {
        val parts = path.split("/")
        if (parts.size != 2 || parts[0] != BackupPaths.WORKS_DIRECTORY || !parts[1].endsWith(".epub")) {
            throw BackupError.UnsafePath(path)
        }
        val id = parts[1].removeSuffix(".epub")
        return BackupPaths.canonicalUuid(id, "work file name")
    }

    private fun validateFontEntry(path: String): String {
        val parts = path.split("/")
        if (parts.size != 2 || parts[0] != BackupPaths.FONTS_DIRECTORY) {
            throw BackupError.UnsafePath(path)
        }
        BackupPaths.requireSafeFontFileName(parts[1])
        return parts[1]
    }

    private fun ZipInputStream.readEntryBytes(path: String): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            total += count
            if (total > BackupLimits.MAX_ENTRY_BYTES) throw BackupError.EntryTooLarge(path)
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun resolveInsideRoot(root: Path, relativePath: String): Path {
        BackupPaths.requireSafeZipEntryName(relativePath)
        val resolved = root.resolve(relativePath).normalize()
        if (!resolved.startsWith(root)) throw BackupError.UnsafePath(relativePath)
        return resolved
    }

    private fun findCaseInsensitiveChild(directory: Path, fileName: String): Path? {
        if (!Files.isDirectory(directory)) return null
        Files.newDirectoryStream(directory).use { stream ->
            return stream.firstOrNull { child ->
                Files.isRegularFile(child) &&
                    child.fileName.toString().lowercase(Locale.ROOT) == fileName.lowercase(Locale.ROOT)
            }
        }
    }

    private fun readLimitedFile(path: Path, backupPath: String): ByteArray {
        if (!Files.isRegularFile(path)) throw BackupError.UnsafePath(backupPath)
        val size = Files.size(path)
        if (size > BackupLimits.MAX_ENTRY_BYTES) throw BackupError.EntryTooLarge(backupPath)
        return Files.readAllBytes(path)
    }

    private fun hasEndOfCentralDirectory(bytes: ByteArray): Boolean {
        if (bytes.size < 22) return false
        val firstPossibleOffset = (bytes.size - 22).coerceAtLeast(0)
        val lastPossibleOffset = (bytes.size - 22 - 65_535).coerceAtLeast(0)
        for (index in firstPossibleOffset downTo lastPossibleOffset) {
            if (
                bytes[index] == 0x50.toByte() &&
                bytes[index + 1] == 0x4b.toByte() &&
                bytes[index + 2] == 0x05.toByte() &&
                bytes[index + 3] == 0x06.toByte()
            ) {
                return true
            }
        }
        return false
    }
}
