package io.github.cidy02.kudos.backup

import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

object BackupPaths {
    const val MANIFEST = "manifest.json"

    /**
     * The previous manifest, kept beside the live one. SAF offers no atomic
     * replace, so this is the recovery half of [MANIFEST]'s write: sync-down
     * falls back to it when the primary is missing, empty or unparseable.
     */
    const val MANIFEST_BACKUP = "manifest.json.bak"

    /**
     * Staging name for a manifest being written. Never authoritative — a temp
     * left behind by an interrupted run is deleted, not folded in as a conflict
     * copy. `createDocument` may append its own extension for the MIME type, so
     * this is only ever matched as a *prefix*.
     */
    const val MANIFEST_TEMP = "manifest.json.tmp"

    const val WORKS_DIRECTORY = "Works"
    const val FONTS_DIRECTORY = "Fonts"

    /**
     * iOS `Originals/`: the file a converted import was made from (`<work>.<ext>`) and the
     * record of its conversion (`<work>.conversion.json`). In a backup archive and in the
     * sync folder alike.
     */
    const val ORIGINALS_DIRECTORY = "Originals"
    const val CONVERSION_RECORD_SUFFIX = ".conversion.json"

    /** iOS `Storage.originalDocumentURL`: the work's UUID in capitals, then the extension. */
    fun iosOriginalFileName(workId: String, extension: String): String =
        "${canonicalUuid(workId, "work.id").uppercase(Locale.ROOT)}.$extension"

    /** iOS `WorkConversionRecord.url`. */
    fun iosConversionRecordFileName(workId: String): String =
        "${canonicalUuid(workId, "work.id").uppercase(Locale.ROOT)}$CONVERSION_RECORD_SUFFIX"

    /**
     * The work an `Originals/` file belongs to (its id, lowercase), and whether the file is the
     * conversion record. Null for a name iOS would not have written; such a file is ignored,
     * as iOS's restore ignores it.
     */
    fun parseOriginalFileName(fileName: String): Pair<String, Boolean>? {
        if (!isSafeFontFileName(fileName)) return null
        val base = fileName.substringBeforeLast('.', fileName)
        val isRecord = base.endsWith(".conversion")
        val id = if (isRecord) base.removeSuffix(".conversion") else base
        return runCatching { UUID.fromString(id).toString() }.getOrNull()?.let { it to isRecord }
    }

    fun canonicalUuid(value: String, field: String = "id"): String {
        return try {
            UUID.fromString(value).toString()
        } catch (_: IllegalArgumentException) {
            throw BackupError.InvalidUuid(field, value)
        }
    }

    fun normalizeIdForComparison(value: String): String {
        return try {
            UUID.fromString(value).toString()
        } catch (_: IllegalArgumentException) {
            value.trim().lowercase(Locale.ROOT)
        }
    }

    fun workEntryName(workId: String): String {
        return "$WORKS_DIRECTORY/${canonicalUuid(workId, "work.id")}.epub"
    }

    /**
     * Apple `Storage.defaultEPUBAssetIdentifier` / `UUID.uuidString`: uppercase
     * UUID plus `.epub`. A new restore row on iOS is born with this name, and
     * `apply` will not replace a non-empty local identifier, so a custom
     * archived name does not survive a restore onto an empty library.
     */
    fun iosEpubAssetIdentifier(workId: String): String {
        return "${canonicalUuid(workId, "work.id").uppercase(Locale.ROOT)}.epub"
    }

    fun fontEntryName(fileName: String): String {
        requireSafeFontFileName(fileName)
        return "$FONTS_DIRECTORY/$fileName"
    }

    fun requireSafeZipEntryName(path: String) {
        if (!isSafeZipEntryName(path)) {
            throw BackupError.UnsafePath(path)
        }
    }

    fun isSafeZipEntryName(path: String): Boolean {
        val normalized = path.removeSuffix("/")
        if (normalized.isBlank()) return false
        if (normalized.startsWith("/") || normalized.contains("\\") || normalized.contains('\u0000')) {
            return false
        }

        val segments = normalized.split("/")
        return segments.all { segment ->
            segment.isNotBlank() && segment != "." && segment != ".."
        }
    }

    const val MAX_FONT_FILE_NAME_LENGTH = 128

    fun requireSafeFontFileName(fileName: String) {
        if (!isSafeFontFileName(fileName)) {
            throw BackupError.UnsafePath("$FONTS_DIRECTORY/$fileName")
        }
    }

    fun isSafeFontFileName(fileName: String): Boolean {
        if (fileName.isBlank() || fileName.length > MAX_FONT_FILE_NAME_LENGTH) return false
        if (fileName == "." || fileName == "..") return false
        if (fileName.contains("/") || fileName.contains("\\") || fileName.contains('\u0000')) return false
        return true
    }

    fun sanitizeFontFileName(rawName: String): String {
        val lastComponent = rawName.substringAfterLast('/').substringAfterLast('\\')
        val sanitized = lastComponent
            .map { char ->
                when {
                    char.isLetterOrDigit() -> char
                    char == '.' || char == '_' || char == '-' || char == ' ' -> char
                    else -> '_'
                }
            }
            .joinToString("")
            .trim()
            .take(MAX_FONT_FILE_NAME_LENGTH)
            .trim('.', ' ')

        return if (isSafeFontFileName(sanitized)) sanitized else "font.ttf"
    }

    fun uniqueSuffixedFontFileName(fileName: String, existingNames: Set<String>): String {
        val safeName = sanitizeFontFileName(fileName)
        val foldedExistingNames = existingNames.mapTo(mutableSetOf()) { fontFileNameKey(it) }
        if (fontFileNameKey(safeName) !in foldedExistingNames) return safeName

        val dotIndex = safeName.lastIndexOf('.').takeIf { it > 0 }
        val originalBase = dotIndex?.let { safeName.substring(0, it) } ?: safeName
        val extension = dotIndex?.let { safeName.substring(it) }.orEmpty()

        var index = 1
        while (true) {
            val suffix = "-restored-$index"
            // Suffix room comes out of the 128-char cap; otherwise a valid
            // occupied name of length 118–128 can never produce a safe candidate.
            val budget = (MAX_FONT_FILE_NAME_LENGTH - suffix.length).coerceAtLeast(0)
            val extensionToUse = extension.take(budget)
            val baseToUse = originalBase.take(budget - extensionToUse.length)
            val candidate = "$baseToUse$suffix$extensionToUse"
            if (fontFileNameKey(candidate) !in foldedExistingNames && isSafeFontFileName(candidate)) {
                return candidate
            }
            index += 1
        }
    }

    fun fontFileNameKey(fileName: String): String = fileName.lowercase(Locale.ROOT)

    fun sha256(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { byte -> "%02x".format(byte) }
    }
}
