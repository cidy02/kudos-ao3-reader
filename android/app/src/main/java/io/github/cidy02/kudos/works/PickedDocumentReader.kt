package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.backup.BackupLimits
import io.github.cidy02.kudos.backup.BackupPaths
import io.github.cidy02.kudos.files.ImportedFileFormat
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.time.Instant
import java.util.zip.ZipFile
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/** The converters and backup preview need heap bytes; refuse oversized input before allocating them. */
internal object PickedDocumentReader {
    const val MAX_BYTES = 32L * 1024 * 1024
    const val PREFIX_BYTES = 4096
    private const val TooLarge = "This file is too large to import on this device (limit: 32 MB)."

    data class Inspection(val format: ImportedFileFormat, val isBackup: Boolean, val generatedAt: Instant?)

    fun inspect(input: InputStream, size: Long?, name: String?, cacheDirectory: File): Inspection {
        checkSize(size)
        val prefix = readPrefix(input)
        require(prefix.isNotEmpty()) { "The selected file was empty." }
        val format = ImportedFileFormat.sniffPrefix(prefix, name)
        require(format.isConvertible) { WorkImporter.unsupportedMessage(format, name) }
        if (format != ImportedFileFormat.ZIP) {
            // A provider may omit or lie about size. Count the rest without retaining it.
            copyBounded(input, null, prefix.size.toLong())
            return Inspection(format, false, null)
        }

        // ZIP's central directory allows inspection without inflating unrelated entries.
        val temporary = File.createTempFile("picked-document-", ".zip", cacheDirectory)
        try {
            temporary.outputStream().use { out ->
                out.write(prefix)
                copyBounded(input, out, prefix.size.toLong())
            }
            return ZipFile(temporary).use { zip ->
                val manifest = zip.getEntry(BackupPaths.MANIFEST)
                val backup = manifest?.let { entry ->
                    require(entry.size <= BackupLimits.MAX_MANIFEST_BYTES) { "The backup manifest is too large." }
                    zip.getInputStream(entry).use { stream ->
                        isBackupManifest(readLimited(stream, BackupLimits.MAX_MANIFEST_BYTES))
                    }
                } == true
                if (backup) return@use Inspection(ImportedFileFormat.ZIP, true, null)
                val actual = ImportedFileFormat.sniffZip(zip, name)
                require(actual.isConvertible) { WorkImporter.unsupportedMessage(actual, name) }
                Inspection(actual, false, if (actual == ImportedFileFormat.EPUB) DownloadDateDetector.epubGeneratedAt(zip) else null)
            }
        } finally {
            temporary.delete()
        }
    }

    /** Recheck size on confirmation; never trust stale provider metadata. */
    fun readBytes(input: InputStream, size: Long?): ByteArray {
        checkSize(size)
        return readLimited(input, MAX_BYTES)
    }

    fun isBackupManifest(bytes: ByteArray): Boolean = runCatching {
        val json = Json.parseToJsonElement(bytes.decodeToString()) as? JsonObject
        json != null && (json["version"] as? JsonPrimitive)?.intOrNull != null && json["works"] is JsonArray
    }.getOrDefault(false)

    private fun checkSize(size: Long?) {
        require(size == null || size <= MAX_BYTES) { TooLarge }
    }

    private fun readPrefix(input: InputStream): ByteArray {
        val buffer = ByteArray(PREFIX_BYTES)
        var count = 0
        while (count < buffer.size) {
            val read = input.read(buffer, count, buffer.size - count)
            if (read < 0) break
            count += read
        }
        return buffer.copyOf(count)
    }

    private fun readLimited(input: InputStream, limit: Long): ByteArray {
        val output = ByteArrayOutputStream()
        copyBounded(input, output, 0, limit)
        return output.toByteArray()
    }

    private fun copyBounded(input: InputStream, output: OutputStream?, alreadyRead: Long, limit: Long = MAX_BYTES) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = alreadyRead
        while (true) {
            // At the limit read only one byte, sufficient to reject a lying/unknown length.
            val count = input.read(buffer, 0, minOf(buffer.size.toLong(), limit - total + 1).toInt())
            if (count < 0) return
            total += count
            require(total <= limit) {
                if (limit == MAX_BYTES) TooLarge else "An archive metadata entry is too large."
            }
            output?.write(buffer, 0, count)
        }
    }
}
