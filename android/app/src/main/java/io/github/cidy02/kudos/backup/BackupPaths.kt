package io.github.cidy02.kudos.backup

import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

object BackupPaths {
    const val MANIFEST = "manifest.json"
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

    fun requireSafeFontFileName(fileName: String) {
        if (!isSafeFontFileName(fileName)) {
            throw BackupError.UnsafePath("$FONTS_DIRECTORY/$fileName")
        }
    }

    fun isSafeFontFileName(fileName: String): Boolean {
        if (fileName.isBlank() || fileName.length > 128) return false
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
            .take(128)
            .trim('.', ' ')

        return if (isSafeFontFileName(sanitized)) sanitized else "font.ttf"
    }

    fun uniqueSuffixedFontFileName(fileName: String, existingNames: Set<String>): String {
        val safeName = sanitizeFontFileName(fileName)
        if (safeName !in existingNames) return safeName

        val dotIndex = safeName.lastIndexOf('.').takeIf { it > 0 }
        val base = dotIndex?.let { safeName.substring(0, it) } ?: safeName
        val extension = dotIndex?.let { safeName.substring(it) }.orEmpty()

        var index = 1
        while (true) {
            val candidate = "$base-restored-$index$extension"
            if (candidate !in existingNames && isSafeFontFileName(candidate)) return candidate
            index += 1
        }
    }

    fun sha256(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { byte -> "%02x".format(byte) }
    }
}
