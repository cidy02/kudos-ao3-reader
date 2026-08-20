package io.github.cidy02.kudos.works.converters

import java.io.File

/**
 * PDF → EPUB.
 *
 * **Preferred path: MuPDF structured text.** MuPDF returns ordered blocks with
 * reliable bounding boxes, which is the data a converter actually needs. The
 * platform text APIs on both platforms are *text* APIs, not *layout* ones —
 * iOS's docs/PDF_ENGINE_MUPDF.md records five defects that came out of
 * reconstructing paragraphs from PDFKit, the worst being prose silently
 * relocated into the wrong paragraph, which is the worst failure mode a
 * preservation app can have.
 *
 * **Fallback: uncompressed text only, else refuse honestly.** When
 * `libkudosmupdf.so` isn't in the APK (`jniLibs/` is not committed — the library
 * is AGPL-3.0 and built locally), only literals inside `( … )` in an
 * *uncompressed* content stream are read, and [convert] returns `null` rather
 * than an EPUB it can't stand behind. An earlier version regexed compressed
 * bytes too; measured on a real PDF, 10 of 18 "paragraphs" were raw binary and
 * none were document text.
 *
 * Either way, [AuthorNoteDetector] marks author's notes the same way as
 * plain-text import (iOS's PDF path uses the same detector via
 * `HTMLWorkSanitizer.paragraphs`).
 */
class PDFWorkConverter(private val cacheDir: File? = null) {

    fun convert(title: String, bytes: ByteArray): ByteArray? {
        val paragraphs = muPdfParagraphs(bytes) ?: extractParagraphs(bytes) ?: return null
        if (paragraphs.isEmpty()) return null
        val body = paragraphsWithAuthorNotes(paragraphs)
        return if (body.isBlank()) null else EpubBuilder.buildEpub(title, body)
    }

    /** MuPDF's paragraphs in reading order, or null when MuPDF can't read the file. */
    private fun muPdfParagraphs(bytes: ByteArray): List<String>? {
        if (!KudosMuPDF.isAvailable) return null
        val temp = writeTemp(bytes) ?: return null
        return try {
            KudosMuPDF.paragraphsPerPage(temp.absolutePath)
                ?.flatten()
                ?.map { it.trim() }
                ?.filter { it.isNotEmpty() }
        } finally {
            temp.delete()
        }
    }

    /**
     * Readable paragraph strings from an uncompressed PDF content stream, or
     * null when the file is compressed / encrypted / empty. Exposed for tests.
     */
    fun extractParagraphs(bytes: ByteArray): List<String>? {
        val rawData = String(bytes, Charsets.ISO_8859_1)

        // Compressed content streams need an inflater + object parser to read.
        // Bail before the regex turns compressed bytes into "paragraphs".
        if (rawData.contains("/FlateDecode") ||
            rawData.contains("/LZWDecode") ||
            rawData.contains("/DCTDecode") ||
            rawData.contains("/Encrypt")
        ) {
            return null
        }

        return Regex("""\((.*?)\)""", RegexOption.DOT_MATCHES_ALL)
            .findAll(rawData)
            .map { match ->
                match.groupValues[1]
                    .replace("\\(", "(")
                    .replace("\\)", ")")
                    .replace("\\\\", "\\")
            }
            .filter { it.isNotBlank() && it.isMostlyReadable() && !it.isPdfDateStamp() }
            .toList()
    }

    /**
     * The document's text as *lines*, for the calibre/FanFicFare label block.
     *
     * Deliberately not paragraphs: assembling a block joins its lines, which
     * merges `Label: value` rows into one blob and makes the parser read
     * `Storylink:` as part of `Story:`'s value.
     */
    fun metadataLines(bytes: ByteArray): List<String> {
        if (!KudosMuPDF.isAvailable) return emptyList()
        val temp = writeTemp(bytes) ?: return emptyList()
        return try {
            KudosMuPDF.linesPerPage(temp.absolutePath)?.firstOrNull().orEmpty()
        } finally {
            temp.delete()
        }
    }

    /**
     * MuPDF opens a path, not a buffer, so the bytes land in the cache dir
     * briefly. Explicit directory, not the bare 2-arg overload: Android doesn't
     * reliably populate `java.io.tmpdir`, so that version can throw — every
     * other temp-file write in this codebase (`WorkFileStore`, `FontFileStore`,
     * `FandomCatalogCache`) passes its directory explicitly for the same reason.
     */
    private fun writeTemp(bytes: ByteArray): File? {
        val dir = cacheDir ?: return null
        return runCatching {
            File.createTempFile("kudos-import-", ".pdf", dir).apply { writeBytes(bytes) }
        }.getOrNull()
    }

    /** Rejects binary that happened to sit between parentheses. */
    private fun String.isMostlyReadable(): Boolean {
        val readable = count { it.isLetterOrDigit() || it.isWhitespace() || it in ".,;:!?'\"-()[]{}" }
        return readable.toDouble() / length >= 0.9
    }

    /** `D:20181013142839-08'00'` is PDF metadata, not prose. */
    private fun String.isPdfDateStamp(): Boolean = startsWith("D:") && length > 6 &&
        this[2].isDigit() && this[3].isDigit() && this[4].isDigit() && this[5].isDigit()
}
