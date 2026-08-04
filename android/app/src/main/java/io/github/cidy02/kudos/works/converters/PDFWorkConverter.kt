package io.github.cidy02.kudos.works.converters

/**
 * Best-effort PDF → EPUB text extraction.
 *
 * Kudos ships no PDF library, so this only reads text from *uncompressed* PDF
 * text objects — literals inside `( … )` in the content stream. Most real PDFs
 * compress their streams (`/FlateDecode`), where those parentheses match
 * compressed binary rather than words.
 *
 * That is why [convert] returns `null` instead of an EPUB it can't stand behind:
 * the previous version emitted that binary as paragraphs, so importing an
 * ordinary PDF produced a library entry full of mojibake instead of a clear
 * "can't read this" message. Measured on a real PDF, 10 of 18 emitted
 * "paragraphs" were raw binary and none were document text.
 *
 * ponytail: literal-only extraction. Swap in PdfBox-Android (plus ML Kit OCR for
 * scanned pages) if PDF import becomes a feature worth its dependency weight.
 */
class PDFWorkConverter {

    fun convert(title: String, bytes: ByteArray): ByteArray? {
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

        val paragraphs = Regex("""\((.*?)\)""", RegexOption.DOT_MATCHES_ALL)
            .findAll(rawData)
            .map { match ->
                match.groupValues[1]
                    .replace("\\(", "(")
                    .replace("\\)", ")")
                    .replace("\\\\", "\\")
            }
            .filter { it.isNotBlank() && it.isMostlyReadable() && !it.isPdfDateStamp() }
            .toList()

        if (paragraphs.isEmpty()) return null

        val body = paragraphs.joinToString("\n") { paragraph ->
            "<p>${paragraph.replace("&", "&amp;").replace("<", "&lt;")}</p>"
        }
        return EpubBuilder.buildEpub(title, body)
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
