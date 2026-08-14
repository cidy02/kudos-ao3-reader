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
