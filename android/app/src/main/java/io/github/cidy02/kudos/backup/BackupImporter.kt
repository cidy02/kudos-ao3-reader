package io.github.cidy02.kudos.backup

import android.graphics.Typeface
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
        var totalFontBytes = 0L
        val seenEntries = mutableSetOf<String>()
        val seenFontFileNames = mutableSetOf<String>()

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

                    val fontFileName = if (path.startsWith("${BackupPaths.FONTS_DIRECTORY}/")) {
                        validateFontEntry(path).also { fileName ->
                            if (!seenFontFileNames.add(BackupPaths.fontFileNameKey(fileName))) {
                                throw BackupError.DuplicateEntry(path)
                            }
                        }
                    } else {
                        null
                    }

                    val payloadLimit = if (fontFileName != null) {
                        BackupLimits.MAX_FONT_ENTRY_BYTES
                    } else {
                        BackupLimits.MAX_ENTRY_BYTES
                    }
                    val payload = zip.readEntryBytes(path, payloadLimit)
                    when {
                        path == BackupPaths.MANIFEST -> manifestBytes = payload
                        path.startsWith("${BackupPaths.WORKS_DIRECTORY}/") -> {
                            val workId = validateWorkEntry(path)
                            epubFiles[workId] = payload
                        }
                        path.startsWith("${BackupPaths.FONTS_DIRECTORY}/") -> {
                            val fileName = requireNotNull(fontFileName)
                            totalFontBytes += payload.size.toLong()
                            if (totalFontBytes > BackupLimits.MAX_TOTAL_FONT_BYTES) {
                                throw BackupError.InvalidPackage("Total font size exceeds limit")
                            }
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
        // Apple writes ZIP for modern manifests (v2–v8). Accept any supported
        // version so a Flip7 can restore a phone's v8 .kudosbackup.
        if (!BackupVersion.isZipCompatible(manifest.version)) {
            throw BackupError.UnsupportedVersion(manifest.version)
        }
        BackupFontValidator.validate(fontFiles)

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
        // Directory packages are the legacy Apple shape (typically v1). Still
        // accept any supported version if someone hands us a directory tree.
        if (!BackupVersion.isSupported(manifest.version)) {
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
        var totalFontBytes = 0L
        manifest.fonts.forEach { font ->
            BackupPaths.requireSafeFontFileName(font.fileName)
            if (!io.github.cidy02.kudos.files.CustomFontRepository.isSupportedFontFileName(font.fileName)) {
                throw BackupError.InvalidPackage("Unsupported font extension")
            }
            val file = findCaseInsensitiveChild(fontsDirectory, font.fileName) ?: return@forEach
            val backupPath = "${BackupPaths.FONTS_DIRECTORY}/${font.fileName}"
            val payload = readLimitedFile(
                file,
                backupPath,
                BackupLimits.MAX_FONT_ENTRY_BYTES
            )
            totalFontBytes += payload.size.toLong()
            if (totalFontBytes > BackupLimits.MAX_TOTAL_FONT_BYTES) {
                throw BackupError.InvalidPackage("Total font size exceeds limit")
            }
            fontFiles[font.fileName] = payload
        }
        BackupFontValidator.validate(fontFiles)

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
        if (!io.github.cidy02.kudos.files.CustomFontRepository.isSupportedFontFileName(parts[1])) {
            throw BackupError.InvalidPackage("Unsupported font extension")
        }
        return parts[1]
    }

    private fun ZipInputStream.readEntryBytes(
        path: String,
        maxBytes: Long = BackupLimits.MAX_ENTRY_BYTES
    ): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            total += count
            if (total > maxBytes) throw BackupError.EntryTooLarge(path)
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

    private fun readLimitedFile(
        path: Path,
        backupPath: String,
        maxBytes: Long = BackupLimits.MAX_ENTRY_BYTES
    ): ByteArray {
        if (!Files.isRegularFile(path)) throw BackupError.UnsafePath(backupPath)
        val size = Files.size(path)
        if (size > maxBytes) throw BackupError.EntryTooLarge(backupPath)
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

internal object BackupFontValidator {
    fun validate(
        fontFiles: Map<String, ByteArray>,
        temporaryFileFactory: (String, String) -> Path = { prefix, suffix ->
            Files.createTempFile(prefix, suffix)
        }
    ) {
        var totalBytes = 0L
        fontFiles.forEach { (fileName, bytes) ->
            BackupPaths.requireSafeFontFileName(fileName)
            if (!io.github.cidy02.kudos.files.CustomFontRepository.isSupportedFontFileName(fileName)) {
                throw BackupError.InvalidPackage("Unsupported font extension")
            }
            if (bytes.size.toLong() > BackupLimits.MAX_FONT_ENTRY_BYTES) {
                throw BackupError.EntryTooLarge("${BackupPaths.FONTS_DIRECTORY}/$fileName")
            }
            totalBytes += bytes.size.toLong()
            if (totalBytes > BackupLimits.MAX_TOTAL_FONT_BYTES) {
                throw BackupError.InvalidPackage("Total font size exceeds limit")
            }
            if (!isLoadableFont(fileName, bytes, temporaryFileFactory)) {
                throw BackupError.InvalidPackage("Invalid font file")
            }
        }
    }

    private fun isLoadableFont(
        fileName: String,
        bytes: ByteArray,
        temporaryFileFactory: (String, String) -> Path
    ): Boolean {
        if (bytes.size < 4) return false
        val b0 = bytes[0].toInt() and 0xFF
        val b1 = bytes[1].toInt() and 0xFF
        val b2 = bytes[2].toInt() and 0xFF
        val b3 = bytes[3].toInt() and 0xFF

        val hasSupportedSfntSignature =
            (b0 == 0x00 && b1 == 0x01 && b2 == 0x00 && b3 == 0x00) ||
                (b0 == 0x74 && b1 == 0x72 && b2 == 0x75 && b3 == 0x65) ||
                (b0 == 0x4F && b1 == 0x54 && b2 == 0x54 && b3 == 0x4F)
        if (!hasSupportedSfntSignature) return false
        if (!hasValidSfntStructure(bytes)) return false

        val extension = fileName.substringAfterLast('.').lowercase(Locale.ROOT)
        val temporary = try {
            temporaryFileFactory("kudos-font-", ".$extension")
        } catch (error: Exception) {
            throw BackupError.FontValidationUnavailable(error)
        }
        return try {
            try {
                Files.write(temporary, bytes)
            } catch (error: Exception) {
                throw BackupError.FontValidationUnavailable(error)
            }
            try {
                Typeface.Builder(temporary.toFile()).build() != null
            } catch (_: IllegalArgumentException) {
                false
            } catch (error: Exception) {
                throw BackupError.FontValidationUnavailable(error)
            }
        } finally {
            runCatching { Files.deleteIfExists(temporary) }
        }
    }

    private fun hasValidSfntStructure(bytes: ByteArray): Boolean {
        if (bytes.size < 12) return false
        val tableCount = unsignedShort(bytes, 4)
        if (tableCount == 0) return false
        val directoryEnd = 12L + tableCount * 16L
        if (directoryEnd > bytes.size) return false

        val tables = mutableMapOf<String, Pair<Int, Int>>()
        repeat(tableCount) { index ->
            val entry = 12 + index * 16
            val tag = String(bytes, entry, 4, Charsets.US_ASCII)
            val offset = unsignedInt(bytes, entry + 8)
            val length = unsignedInt(bytes, entry + 12)
            if (length == 0L) {
                if (offset > bytes.size.toLong()) return false
            } else if (offset < directoryEnd || offset + length > bytes.size.toLong()) {
                return false
            }
            if (tables.put(tag, offset.toInt() to length.toInt()) != null) return false
        }

        val required = setOf("cmap", "head", "hhea", "hmtx", "maxp", "name")
        if (!required.all { tables[it]?.second?.let { length -> length > 0 } == true }) return false
        val hasTrueTypeOutlines = tables["glyf"]?.second?.let { it > 0 } == true &&
            tables["loca"]?.second?.let { it > 0 } == true
        val hasCffOutlines = tables["CFF "]?.second?.let { it > 0 } == true ||
            tables["CFF2"]?.second?.let { it > 0 } == true
        if (!hasTrueTypeOutlines && !hasCffOutlines) return false

        val (headOffset, headLength) = tables.getValue("head")
        if (headLength < 16 || unsignedInt(bytes, headOffset + 12) != 0x5F0F3CF5L) return false
        val (cmapOffset, cmapLength) = tables.getValue("cmap")
        if (cmapLength < 4 || unsignedShort(bytes, cmapOffset) != 0) return false
        return true
    }

    private fun unsignedShort(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xFF) shl 8) or
            (bytes[offset + 1].toInt() and 0xFF)
    }

    private fun unsignedInt(bytes: ByteArray, offset: Int): Long {
        return ((bytes[offset].toLong() and 0xFF) shl 24) or
            ((bytes[offset + 1].toLong() and 0xFF) shl 16) or
            ((bytes[offset + 2].toLong() and 0xFF) shl 8) or
            (bytes[offset + 3].toLong() and 0xFF)
    }
}
