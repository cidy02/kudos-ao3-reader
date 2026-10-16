package io.github.cidy02.kudos.works.converters

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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
 * Without MuPDF, refuse the import. PDF literals may be document metadata rather
 * than text streams, so guessing at them can silently import the wrong content.
 * OCR for scans is not yet available on Android.
 *
 * Either way, [AuthorNoteDetector] marks author's notes the same way as
 * plain-text import (iOS's PDF path uses the same detector via
 * `HTMLWorkSanitizer.paragraphs`).
 */
class PDFWorkConverter(private val cacheDir: File? = null) {

    // MuPDF's structured-text walk is blocking native work — real PDFs run to
    // the hundreds of pages, and every caller reaches this through a suspend
    // function, so dispatching here once covers all of them rather than
    // relying on each call site to remember Dispatchers.IO itself.
    suspend fun convert(title: String, bytes: ByteArray): ByteArray? = withContext(Dispatchers.IO) {
        val pages = muPdfPages(bytes) ?: return@withContext null
        val body = body(title, pages)
        if (body.isBlank()) null else EpubBuilder.buildEpub(title, body)
    }

    /** MuPDF's paragraphs in reading order, or null when MuPDF can't read the file. */
    private fun muPdfPages(bytes: ByteArray): List<List<String>>? {
        if (!KudosMuPDF.isAvailable) return null
        val temp = writeTemp(bytes) ?: return null
        return try {
            KudosMuPDF.paragraphsPerPage(temp.absolutePath)
        } finally {
            temp.delete()
        }
    }

    /** iOS withoutRunningHeadersAndFooters / withoutEchoedTitle / line reflow. */
    internal fun body(title: String, pages: List<List<String>>): String {
        val normalized = pages.map { page -> page.map { block ->
            block.replace(Regex("([\\p{L}])-\\s*\\n\\s*(?=[\\p{L}])"), "$1")
                .replace(Regex("[ \\t]*\\n[ \\t]*"), " ").trim()
        }.filter { it.isNotEmpty() } }
        val edgeCounts = normalized.flatMap { page -> listOfNotNull(page.firstOrNull(), page.lastOrNull()).distinct() }
            .groupingBy { it }.eachCount()
        val repeated = edgeCounts.filterValues { it >= maxOf(3, pages.size / 3) }.keys
        val pageNumber = Regex("^[\\-–—\\s]*[0-9]{1,4}[.\\-–—\\s]*$")
        val paragraphs = normalized.flatMap { page -> page.filter { text ->
            pages.size < 4 || (text !in repeated && !pageNumber.matches(text))
        } }.toMutableList()
        if (paragraphs.firstOrNull() == title) paragraphs.removeAt(0)
        return paragraphsWithAuthorNotes(paragraphs)
    }

    /**
     * The document's text as *lines*, for the calibre/FanFicFare label block.
     *
     * Deliberately not paragraphs: assembling a block joins its lines, which
     * merges `Label: value` rows into one blob and makes the parser read
     * `Storylink:` as part of `Story:`'s value.
     */
    suspend fun metadataLines(bytes: ByteArray): List<String> = withContext(Dispatchers.IO) {
        if (!KudosMuPDF.isAvailable) return@withContext emptyList()
        val temp = writeTemp(bytes) ?: return@withContext emptyList()
        try {
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
            val file = File.createTempFile("kudos-import-", ".pdf", dir)
            try {
                file.writeBytes(bytes)
                file
            } catch (e: Exception) {
                file.delete()
                throw e
            }
        }.getOrNull()
    }

}
