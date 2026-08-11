package io.github.cidy02.kudos.works.converters

import io.github.cidy02.kudos.files.ImportedFileFormat
import io.github.cidy02.kudos.files.TextDecoding
import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/**
 * Non-EPUB ZIP handling (iOS `ImportedDocumentConverter.convertArchive`).
 *
 * Two cases, in order:
 *  1. The archive *contains* an EPUB — extract and use it directly.
 *  2. Otherwise, stitch readable HTML/text members into one work, in natural
 *     sort order so `chapter2` sorts before `chapter10`.
 */
object ArchiveWorkConverter {

    /** Members bigger than this are almost certainly not a chapter of prose. */
    private const val MAX_MEMBER_BYTES = 8 * 1024 * 1024

    /** ponytail: bounded walk so a zip bomb can't spin us; raise if real works exceed it. */
    private const val MAX_MEMBERS = 512

    fun convert(title: String, bytes: ByteArray): ByteArray? {
        val members = readMembers(bytes) ?: return null

        // 1. A nested EPUB wins outright — it's already the format we want.
        members.firstOrNull { (name, body) ->
            name.endsWith(".epub", ignoreCase = true) &&
                ImportedFileFormat.sniff(body, name) == ImportedFileFormat.EPUB
        }?.let { return it.second }

        // 2. Stitch readable members together.
        val chapters = members
            .filter { (name, _) -> name.isReadableMember() }
            .sortedWith(compareBy(NaturalOrder) { it.first })
            .mapNotNull { (name, body) -> chapterFrom(name, body) }

        if (chapters.isEmpty()) return null
        return EpubBuilder.buildEpub(title, chapters)
    }

    private fun chapterFrom(name: String, body: ByteArray): EpubBuilder.Chapter? {
        val text = TextDecoding.decode(body) ?: return null
        if (text.isBlank()) return null
        val chapterTitle = name.substringAfterLast('/').substringBeforeLast('.')
        val html = when (ImportedFileFormat.sniff(body, name)) {
            ImportedFileFormat.HTML -> HTMLWorkConverter().sanitizedBody(text)
            else -> PlainTextWorkConverter().paragraphs(text)
        }
        return if (html.isBlank()) null else EpubBuilder.Chapter(chapterTitle, html)
    }

    private fun String.isReadableMember(): Boolean {
        val lower = substringAfterLast('/').lowercase()
        if (lower.isEmpty() || lower.startsWith(".") || contains("__MACOSX")) return false
        return lower.endsWith(".html") || lower.endsWith(".htm") ||
            lower.endsWith(".txt") || lower.endsWith(".md") || lower.endsWith(".xhtml")
    }

    private fun readMembers(bytes: ByteArray): List<Pair<String, ByteArray>>? = runCatching {
        val out = mutableListOf<Pair<String, ByteArray>>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            repeat(MAX_MEMBERS) {
                val entry = zip.nextEntry ?: return@use
                if (entry.isDirectory) return@repeat
                val body = zip.readBoundedBytes(MAX_MEMBER_BYTES) ?: return@repeat
                out += entry.name to body
            }
        }
        out.takeIf { it.isNotEmpty() }
    }.getOrNull()

    private fun ZipInputStream.readBoundedBytes(limit: Int): ByteArray? {
        val buffer = java.io.ByteArrayOutputStream()
        val chunk = ByteArray(16 * 1024)
        while (true) {
            val read = read(chunk)
            if (read <= 0) break
            if (buffer.size() + read > limit) return null
            buffer.write(chunk, 0, read)
        }
        return buffer.toByteArray()
    }

    /** `chapter2.html` must sort before `chapter10.html`. */
    internal object NaturalOrder : Comparator<String> {
        private val chunk = Regex("\\d+|\\D+")
        override fun compare(a: String, b: String): Int {
            val left = chunk.findAll(a.lowercase()).map { it.value }.toList()
            val right = chunk.findAll(b.lowercase()).map { it.value }.toList()
            for (i in 0 until minOf(left.size, right.size)) {
                val l = left[i]; val r = right[i]
                val ln = l.toLongOrNull(); val rn = r.toLongOrNull()
                val cmp = if (ln != null && rn != null) ln.compareTo(rn) else l.compareTo(r)
                if (cmp != 0) return cmp
            }
            return left.size.compareTo(right.size)
        }
    }
}
