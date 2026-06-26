package io.github.cidy02.kudos.backup

import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.serialization.encodeToString

object BackupExporter {
    fun exportV2(kudosBackup: KudosBackupPackage): ByteArray {
        val manifest = BackupValidator.validateManifest(
            kudosBackup.manifest.copy(
                version = BackupVersion.ZIP_V2,
                exportedBy = kudosBackup.manifest.exportedBy ?: BackupExportedBy(
                    platform = "android",
                    appVersion = "0.1.0",
                    schemaVersion = 1
                )
            )
        )

        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            val seenEntries = mutableSetOf<String>()
            zip.writeEntry(
                path = BackupPaths.MANIFEST,
                bytes = BackupJson.encodeToString(manifest).toByteArray(Charsets.UTF_8),
                seenEntries = seenEntries
            )

            manifest.works
                .sortedBy { it.id }
                .forEach { work ->
                    val id = BackupPaths.canonicalUuid(work.id, "work.id")
                    val bytes = kudosBackup.epubFilesByWorkId[id] ?: return@forEach
                    zip.writeEntry(BackupPaths.workEntryName(id), bytes, seenEntries)
                }

            manifest.fonts
                .sortedBy { it.fileName }
                .forEach { font ->
                    val bytes = kudosBackup.fontFilesByFileName[font.fileName] ?: return@forEach
                    zip.writeEntry(BackupPaths.fontEntryName(font.fileName), bytes, seenEntries)
                }
        }

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
