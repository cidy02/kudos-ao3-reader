package io.github.cidy02.kudos.files

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream
import java.util.Locale
import java.util.zip.ZipFile

/**
 * Content-based format sniffing for imported files (iOS `ImportedFileFormat`).
 *
 * Extension alone is not enough: files that travel through Reddit, Discord and
 * forum attachments arrive renamed (`fic.epub.zip`, `story.txt` that is really
 * HTML), so the magic bytes decide and the file name is only a tie-breaker.
 */
enum class ImportedFileFormat {
    EPUB, PDF, HTML, TEXT, ZIP, DOCX, ODT, RTF, MOBI, RAR, SEVEN_ZIP, UNKNOWN;

    val isConvertible: Boolean
        get() = this in setOf(EPUB, PDF, HTML, TEXT, ZIP)

    companion object {
        private val ZIP_MAGIC = byteArrayOf(0x50, 0x4B)
        private val PDF_MAGIC = byteArrayOf(0x25, 0x50, 0x44, 0x46) // %PDF

        fun sniff(bytes: ByteArray, fileName: String?): ImportedFileFormat {
            val prefixFormat = sniffPrefix(bytes, fileName)
            if (prefixFormat != ZIP) return prefixFormat
            return sniffZipBytes(bytes, fileName)
        }

        /** No archive traversal: safe to call with only the first 4 KB of a picked file. */
        fun sniffPrefix(bytes: ByteArray, fileName: String?): ImportedFileFormat {
            if (bytes.startsWith(ZIP_MAGIC)) return ZIP
            if (bytes.startsWith(PDF_MAGIC)) return PDF
            if (bytes.startsWith("{\\rtf".toByteArray())) return RTF
            if (bytes.startsWith("Rar!".toByteArray())) return RAR
            if (bytes.startsWith(byteArrayOf(0x37, 0x7A, 0xBC.toByte(), 0xAF.toByte(), 0x27, 0x1C))) return SEVEN_ZIP
            if (bytes.size >= 68 && String(bytes, 60, 8, Charsets.US_ASCII) in setOf("BOOKMOBI", "TEXtREAd")) return MOBI

            val head = bytes.take(4096).toByteArray().decodeToString()
            if (head.contains("<html", true) || head.contains("<!doctype html", true)) return HTML
            return when (fileName?.substringAfterLast('.', "")?.lowercase(Locale.ROOT)) {
                "epub" -> EPUB
                "pdf" -> PDF
                "html", "htm", "xhtml" -> HTML
                "txt", "text", "md", "markdown" -> TEXT
                "docx" -> DOCX
                "odt" -> ODT
                "rtf" -> RTF
                "mobi", "azw", "azw3", "prc" -> MOBI
                "rar" -> RAR
                "7z" -> SEVEN_ZIP
                else -> if (head.isProbablyText()) TEXT else UNKNOWN
            }
        }

        /** Central-directory inspection never inflates unrelated archive entries. */
        fun sniffZip(zip: ZipFile, fileName: String?): ImportedFileFormat {
            if (zip.getEntry("META-INF/container.xml") != null) return EPUB
            if (zip.getEntry("word/document.xml") != null) return DOCX
            val mimetype = zip.getEntry("mimetype")?.let { entry ->
                zip.getInputStream(entry).use { input ->
                    val buffer = ByteArray(256)
                    val count = input.read(buffer)
                    if (count > 0) String(buffer, 0, count, Charsets.UTF_8).trim() else null
                }
            }
            if (mimetype == "application/epub+zip") return EPUB
            if (mimetype?.startsWith("application/vnd.oasis.opendocument") == true) return ODT
            return namedZipFormat(fileName)
        }

        private fun namedZipFormat(fileName: String?): ImportedFileFormat = when (
            fileName?.substringAfterLast('.', "")?.lowercase(Locale.ROOT)
        ) {
            "epub" -> EPUB
            "docx" -> DOCX
            "odt" -> ODT
            else -> ZIP
        }

        private fun sniffZipBytes(bytes: ByteArray, fileName: String?): ImportedFileFormat = runCatching {
            ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
                var scanned = 0L
                val buffer = ByteArray(8192)
                repeat(64) {
                    val entry = zip.nextEntry ?: return@use namedZipFormat(fileName)
                    if (entry.name.equals("META-INF/container.xml", ignoreCase = true)) return@use EPUB
                    if (entry.name == "word/document.xml") return@use DOCX
                    val mime = StringBuilder()
                    while (true) {
                        val count = zip.read(buffer)
                        if (count < 0) break
                        scanned += count
                        if (scanned > 8L * 1024 * 1024) return@use namedZipFormat(fileName)
                        if (entry.name == "mimetype" && mime.length < 256) {
                            mime.append(String(buffer, 0, minOf(count, 256 - mime.length), Charsets.UTF_8))
                        }
                    }
                    val value = mime.toString().trim()
                    if (value == "application/epub+zip") return@use EPUB
                    if (value.startsWith("application/vnd.oasis.opendocument")) return@use ODT
                }
                namedZipFormat(fileName)
            }
        }.getOrDefault(namedZipFormat(fileName))

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
