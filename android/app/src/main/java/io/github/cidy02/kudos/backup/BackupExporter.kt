package io.github.cidy02.kudos.backup

import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.serialization.encodeToString

object BackupExporter {
    /**
     * Refuses what [BackupImporter] would refuse (iOS `exportRefusesArchivesTheReaderWouldReject`,
     * A52): only each entry's size was checked, so a library past the archive or font limits
     * made a backup this app could not restore.
     */
    fun exportV2(
        kudosBackup: KudosBackupPackage,
        maxArchiveBytes: Long = BackupLimits.MAX_ARCHIVE_BYTES
    ): ByteArray {
        val manifest = BackupValidator.validateManifest(
            kudosBackup.manifest.copy(
                // Write current Apple-compatible version so cross-device restore
                // does not bounce on "unsupported version" either direction.
                version = BackupVersion.CURRENT,
                exportedBy = kudosBackup.manifest.exportedBy ?: BackupExportedBy(
                    platform = "android",
                    appVersion = "0.1.0",
                    schemaVersion = BackupVersion.CURRENT
                )
            )
        )

        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            val seenEntries = mutableSetOf<String>()
            fun checkArchiveSize() {
                // An entry's compressed bytes are in `output` once it is closed.
                if (output.size().toLong() > maxArchiveBytes) throw BackupError.ArchiveTooLarge()
            }
            val manifestBytes = BackupJson.encodeToString(manifest).toByteArray(Charsets.UTF_8)
            if (manifestBytes.size.toLong() > BackupLimits.MAX_MANIFEST_BYTES) {
                throw BackupError.EntryTooLarge(BackupPaths.MANIFEST)
            }
            zip.writeEntry(
                path = BackupPaths.MANIFEST,
                bytes = manifestBytes,
                seenEntries = seenEntries
            )
            checkArchiveSize()

            manifest.works
                .sortedBy { it.id }
                .forEach { work ->
                    val id = BackupPaths.canonicalUuid(work.id, "work.id")
                    val bytes = kudosBackup.epubFilesByWorkId[id] ?: return@forEach
                    zip.writeEntry(BackupPaths.workEntryName(id), bytes, seenEntries)
                    checkArchiveSize()
                }

            var totalFontBytes = 0L

            manifest.fonts
                .sortedBy { it.fileName }
                .forEach { font ->
                    val bytes = kudosBackup.fontFilesByFileName[font.fileName] ?: return@forEach
                    val path = BackupPaths.fontEntryName(font.fileName)
                    if (bytes.size.toLong() > BackupLimits.MAX_FONT_ENTRY_BYTES) throw BackupError.EntryTooLarge(path)
                    totalFontBytes += bytes.size
                    if (totalFontBytes > BackupLimits.MAX_TOTAL_FONT_BYTES) {
                        throw BackupError.InvalidPackage("Total font size exceeds limit")
                    }
                    zip.writeEntry(path, bytes, seenEntries)
                    checkArchiveSize()
                }

            kudosBackup.originalFilesByName.toSortedMap().forEach { (name, bytes) ->
                zip.writeEntry("${BackupPaths.ORIGINALS_DIRECTORY}/$name", bytes, seenEntries)
                checkArchiveSize()
            }
        }
        // The central directory is written on close.
        if (output.size().toLong() > maxArchiveBytes) throw BackupError.ArchiveTooLarge()

        return output.toByteArray()
    }

    private fun ZipOutputStream.writeEntry(
        path: String,
        bytes: ByteArray,
        seenEntries: MutableSet<String>
    ) {
        BackupPaths.requireSafeZipEntryName(path)
        if (!seenEntries.add(path)) throw BackupError.DuplicateEntry(path)
        if (bytes.size.toLong() > BackupLimits.MAX_ENTRY_BYTES) {
            throw BackupError.EntryTooLarge(path)
        }

        val entry = ZipEntry(path).apply { time = 0L }
        putNextEntry(entry)
        write(bytes)
        closeEntry()
    }
}
