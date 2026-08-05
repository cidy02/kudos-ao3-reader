package io.github.cidy02.kudos.works.converters

import io.github.cidy02.kudos.files.TextDecoding

/**
 * Plain text / Markdown → EPUB (iOS `PlainTextWorkConverter`).
 *
 * Reflows hard-wrapped prose: archives from the mailing-list era wrap at ~70
 * columns, and treating each wrapped line as its own paragraph makes the work
 * unreadable in a reflowable reader.
 */
class PlainTextWorkConverter {

    fun convert(title: String, bytes: ByteArray): ByteArray? {
        val text = TextDecoding.decode(bytes) ?: return null
        val body = paragraphs(text)
        return if (body.isBlank()) null else EpubBuilder.buildEpub(title, body)
    }

    /** Blank-line-separated blocks become paragraphs; single newlines are unwrapped. */
    fun paragraphs(text: String): String {
        val normalized = text.replace("\r\n", "\n").replace('\r', '\n')
        return normalized.split(Regex("\n[ \t]*\n+"))
            .map { block -> block.trim() }
            .filter { it.isNotEmpty() }
            .joinToString("\n") { block ->
                if (block.looksLikeHeading()) {
                    "<h2>${escape(block)}</h2>"
                } else {
                    // Unwrap hard line breaks inside a paragraph.
                    "<p>${escape(block.replace(Regex("\n[ \t]*"), " "))}</p>"
                }
            }
    }

    /** `Chapter 3`, `## Heading`, or a short standalone line in title case. */
    private fun String.looksLikeHeading(): Boolean {
        if (contains('\n')) return false
        if (startsWith("#")) return true
        return length <= 60 && Regex("""^(chapter|part|prologue|epilogue)\b.*""", RegexOption.IGNORE_CASE).matches(this)
    }

    private fun escape(value: String): String = value
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
}
