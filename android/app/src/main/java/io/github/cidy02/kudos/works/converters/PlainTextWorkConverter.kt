package io.github.cidy02.kudos.works.converters

import io.github.cidy02.kudos.files.TextDecoding

/**
 * Plain text / Markdown → EPUB (iOS `PlainTextWorkConverter`).
 *
 * Reflows hard-wrapped prose: archives from the mailing-list era wrap at ~70
 * columns, and treating each wrapped line as its own paragraph makes the work
 * unreadable in a reflowable reader.
 *
 * Author's notes are recognised with [AuthorNoteDetector] (iOS port) and wrapped
 * as `<aside class="author-note">`, matching HTML imports and
 * [EpubBuilder.AUTHOR_NOTE_STYLESHEET].
 */
class PlainTextWorkConverter {

    fun convert(title: String, bytes: ByteArray): ByteArray? {
        val text = TextDecoding.decode(bytes) ?: return null
        val body = paragraphs(text)
        return if (body.isBlank()) null else EpubBuilder.buildEpub(title, body)
    }

    /**
     * Blank-line-separated blocks become paragraphs; single newlines are unwrapped.
     * Consecutive author's-note blocks share one `<aside>` (iOS
     * `HTMLWorkSanitizer.paragraphs`).
     */
    fun paragraphs(text: String): String {
        val blocks = paragraphBlocks(text)
        if (blocks.isEmpty()) return ""
        // Headings stay structural (not fed through the note detector as prose).
        // Build per-block HTML for headings, then note-wrap the rest as a run.
        // Simpler and iOS-aligned: detect notes on unwrapped prose blocks only;
        // headings are never notes in the iOS converter path either.
        val rendered = mutableListOf<String>()
        val proseRun = mutableListOf<String>()
        fun flushProse() {
            if (proseRun.isEmpty()) return
            rendered += paragraphsWithAuthorNotes(proseRun)
            proseRun.clear()
        }
        for (block in blocks) {
            if (block.looksLikeHeading()) {
                flushProse()
                rendered += "<h2>${escape(block)}</h2>"
            } else {
                proseRun += block
            }
        }
        flushProse()
        return rendered.joinToString("\n")
    }

    /** Unwrapped paragraph strings (blank-line separated). Exposed for tests. */
    fun paragraphBlocks(text: String): List<String> {
        val normalized = text.replace("\r\n", "\n").replace('\r', '\n')
        return normalized.split(Regex("\n[ \t]*\n+"))
            .map { block ->
                // Unwrap hard line breaks inside a paragraph.
                block.trim().replace(Regex("\n[ \t]*"), " ")
            }
            .filter { it.isNotEmpty() }
    }

    /** `Chapter 3`, `## Heading`, or a short standalone line in title case. */
    private fun String.looksLikeHeading(): Boolean {
        if (contains('\n')) return false
        if (startsWith("#")) return true
        return length <= 60 && Regex(
            """^(chapter|part|prologue|epilogue)\b.*""",
            RegexOption.IGNORE_CASE
        ).matches(this)
    }

    private fun escape(value: String): String = value
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
}
