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
 * **Fallback: refuse honestly.** When `libkudosmupdf.so` isn't in the APK
 * (`jniLibs/` is not committed — the library is AGPL-3.0 and built locally),
 * [convert] returns null rather than an EPUB it can't stand behind. An earlier
 * version regexed `( … )` over raw bytes and emitted decompressed binary as
 * paragraphs; measured on a real PDF, 10 of 18 "paragraphs" were noise and none
 * were document text.
 */
class PDFWorkConverter(private val cacheDir: File) {

    // MuPDF's structured-text walk is blocking native work — real PDFs run to
    // the hundreds of pages, and every caller reaches this through a suspend
    // function, so dispatching here once covers all of them rather than
    // relying on each call site to remember Dispatchers.IO itself.
    suspend fun convert(title: String, bytes: ByteArray): ByteArray? = withContext(Dispatchers.IO) {
        val temp = writeTemp(bytes) ?: return@withContext null
        try {
            val pages = KudosMuPDF.paragraphsPerPage(temp.absolutePath) ?: return@withContext null
            val paragraphs = pages.flatten().map { it.trim() }.filter { it.isNotEmpty() }
            if (paragraphs.isEmpty()) return@withContext null

            val body = paragraphs.joinToString("\n") { "<p>${escape(it)}</p>" }
            EpubBuilder.buildEpub(title, body)
        } finally {
            temp.delete()
        }
    }

    /**
     * The document's text as *lines*, for the calibre/FanFicFare label block.
     *
     * Deliberately not paragraphs: assembling a block joins its lines, which
     * merges `Label: value` rows into one blob and makes the parser read
     * `Storylink:` as part of `Story:`'s value.
     */
    suspend fun metadataLines(bytes: ByteArray): List<String> = withContext(Dispatchers.IO) {
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
    private fun writeTemp(bytes: ByteArray): File? = runCatching {
        val file = File.createTempFile("kudos-import-", ".pdf", cacheDir)
        try {
            file.writeBytes(bytes)
            file
        } catch (e: Exception) {
            file.delete()
            throw e
        }
    }.getOrNull()

    private fun escape(value: String): String =
        value.replace("&", "&amp;").replace("<", "&lt;")
}
