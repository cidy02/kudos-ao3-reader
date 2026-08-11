package io.github.cidy02.kudos.files

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/**
 * Content-based format sniffing for imported files (iOS `ImportedFileFormat`).
 *
 * Extension alone is not enough: files that travel through Reddit, Discord and
 * forum attachments arrive renamed (`fic.epub.zip`, `story.txt` that is really
 * HTML), so the magic bytes decide and the file name is only a tie-breaker.
 */
enum class ImportedFileFormat {
    EPUB, PDF, HTML, TEXT, ZIP, UNKNOWN;

    companion object {
        private val ZIP_MAGIC = byteArrayOf(0x50, 0x4B)
        private val PDF_MAGIC = byteArrayOf(0x25, 0x50, 0x44, 0x46) // %PDF

        fun sniff(bytes: ByteArray, fileName: String?): ImportedFileFormat {
            val namedEpub = fileName?.endsWith(".epub", ignoreCase = true) == true
            if (bytes.startsWith(ZIP_MAGIC)) {
                // The container entry *rescues* a renamed EPUB (`fic.epub.zip`);
                // it never overrules a file the user already named `.epub`, whose
                // structure is validated downstream by the ZIP/EPUB check.
                return if (namedEpub || looksLikeEpubContainer(bytes)) EPUB else ZIP
            }
            if (bytes.startsWith(PDF_MAGIC)) return PDF

            val head = bytes.take(1024).toByteArray().decodeToString()
            if (head.contains("<html", true) || head.contains("<!doctype html", true)) return HTML

            return when (fileName?.substringAfterLast('.', "")?.lowercase()) {
                "epub" -> EPUB
                "pdf" -> PDF
                "html", "htm" -> HTML
                "txt" -> TEXT
                else -> if (head.isProbablyText()) TEXT else UNKNOWN
            }
        }

        /** True when the archive carries `META-INF/container.xml` (the OCF marker). */
        private fun looksLikeEpubContainer(bytes: ByteArray): Boolean = runCatching {
            ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
                // Bounded: the container entry lives at the front of a well-formed
                // EPUB, so a hostile archive can't make us walk thousands of entries.
                // ponytail: fixed 64-entry scan, raise only if a real EPUB is missed.
                repeat(64) {
                    val entry = zip.nextEntry ?: return false
                    if (entry.name.equals("META-INF/container.xml", ignoreCase = true)) return true
                }
                false
            }
        }.getOrDefault(false)

        private fun ByteArray.startsWith(prefix: ByteArray): Boolean {
            if (size < prefix.size) return false
            return prefix.indices.all { this[it] == prefix[it] }
        }

        /** No NUL bytes and mostly printable — good enough to call it plain text. */
        private fun String.isProbablyText(): Boolean {
            if (isEmpty() || any { it == '\u0000' }) return false
            val printable = count { it.isLetterOrDigit() || it.isWhitespace() || it in " .,;:!?'\"-()[]{}/\\@#$%^&*+=_<>|~`" }
            return printable.toDouble() / length >= 0.85
        }
    }
}
