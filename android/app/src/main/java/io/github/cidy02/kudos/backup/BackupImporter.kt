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
        var totalFontBytes = 0L
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
                            if (payload.size > BackupLimits.MAX_FONT_ENTRY_BYTES) {
                                throw BackupError.EntryTooLarge(path)
                            }
                            totalFontBytes += payload.size
                            if (totalFontBytes > BackupLimits.MAX_TOTAL_FONT_BYTES) {
                                throw BackupError.InvalidPackage("Total font size exceeds limit")
                            }
                            if (!isLoadableFont(payload)) {
                                throw BackupError.InvalidPackage("Invalid font file")
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
            val payload = readLimitedFile(file, "${BackupPaths.FONTS_DIRECTORY}/${font.fileName}")
            if (payload.size > BackupLimits.MAX_FONT_ENTRY_BYTES) {
                throw BackupError.EntryTooLarge("${BackupPaths.FONTS_DIRECTORY}/${font.fileName}")
            }
            totalFontBytes += payload.size
            if (totalFontBytes > BackupLimits.MAX_TOTAL_FONT_BYTES) {
                throw BackupError.InvalidPackage("Total font size exceeds limit")
            }
            if (!isLoadableFont(payload)) {
                throw BackupError.InvalidPackage("Invalid font file")
            }
            fontFiles[font.fileName] = payload
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
        if (!io.github.cidy02.kudos.files.CustomFontRepository.isSupportedFontFileName(parts[1])) {
            throw BackupError.InvalidPackage("Unsupported font extension")
        }
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

    private fun isLoadableFont(bytes: ByteArray): Boolean {
        if (bytes.size < 4) return false
        val b0 = bytes[0].toInt() and 0xFF
        val b1 = bytes[1].toInt() and 0xFF
        val b2 = bytes[2].toInt() and 0xFF
        val b3 = bytes[3].toInt() and 0xFF

        // TrueType (TTF) magic: 0x00 0x01 0x00 0x00 or 't' 'r' 'u' 'e' (0x74 0x72 0x75 0x65)
        if (b0 == 0x00 && b1 == 0x01 && b2 == 0x00 && b3 == 0x00) return true
        if (b0 == 0x74 && b1 == 0x72 && b2 == 0x75 && b3 == 0x65) return true

        // OpenType (OTF) magic: 'O' 'T' 'T' 'O' (0x4F 0x54 0x54 0x4F)
        if (b0 == 0x4F && b1 == 0x54 && b2 == 0x54 && b3 == 0x4F) return true

        // WOFF / WOFF2 magic
        if (b0 == 0x77 && b1 == 0x4F && b2 == 0x46 && (b3 == 0x46 || b3 == 0x32)) return true

        return false
    }
}
