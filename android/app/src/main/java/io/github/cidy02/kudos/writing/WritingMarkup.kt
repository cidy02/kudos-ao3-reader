package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.comments.CommentMarkupTag
import java.net.URI
import java.util.Locale

/** Reuse the existing vocabulary's names/order; writing alone also offers p and br. */
data class WritingTag(val element: String, val name: String) {
    val tagLabel: String get() = if (element == "a") "a href" else element
}

object WritingMarkup {
    val tags: List<WritingTag> = CommentMarkupTag.entries.map { WritingTag(it.element, it.label) }
        .toMutableList().apply {
            add(8, WritingTag("p", "Paragraph"))
            add(9, WritingTag("br", "Line break"))
        }

    data class Insertion(val text: String, val contentOffset: Int, val contentLength: Int)

    fun safeLink(value: String): Boolean = runCatching {
        URI(value.replace(" ", "%20").replace("\"", "%22").replace("<", "%3C").replace(">", "%3E")).scheme?.lowercase(Locale.ROOT) in listOf("http", "https", "mailto")
    }.getOrDefault(false)

    fun insertion(tag: String, selected: String, link: String = ""): Insertion? =
        insertion(tag, selected, 0, selected.length, link)

    /** UTF-16 coordinates. Never parse or normalize markup already in the buffer. */
    fun insertion(tag: String, text: CharSequence, start: Int, end: Int, link: String = ""): Insertion? {
        if (tags.none { it.element == tag } || start !in 0..text.length || end !in start..text.length) return null
        // Swift's Range(NSRange, in:) also refuses an offset inside a surrogate pair.
        fun splitsSurrogate(index: Int): Boolean = index > 0 && index < text.length &&
            Character.isHighSurrogate(text[index - 1]) && Character.isLowSurrogate(text[index])
        if (splitsSurrogate(start) || splitsSurrogate(end)) return null
        if (tag == "a" && !safeLink(link)) return null
        val selected = text.subSequence(start, end).toString()
        val prefix: String
        val body: String
        val suffix: String
        when (tag) {
            "hr" -> {
                val opensLine = end == 0 || text[end - 1] == '\n'
                val closesLine = end < text.length && text[end] == '\n'
                prefix = selected + (if (opensLine) "" else "\n") + "<hr>" + (if (closesLine) "" else "\n")
                body = ""; suffix = ""
            }
            "br" -> { prefix = "<br>"; body = selected; suffix = "" }
            "ul", "ol" -> {
                val items = selected.split('\n').map { it.trim { ch -> ch == '\t' || Character.getType(ch) == Character.SPACE_SEPARATOR.toInt() } }
                    .filter { it.isNotEmpty() }.map { "<li>$it</li>" }
                if (items.isEmpty()) {
                    prefix = "<$tag>\n<li>"; body = ""; suffix = "</li>\n</$tag>"
                } else {
                    prefix = "<$tag>\n"; body = items.joinToString("\n"); suffix = "\n</$tag>"
                }
            }
            "a" -> {
                val escaped = link.replace("&", "&amp;").replace("\"", "&quot;")
                    .replace("<", "&lt;").replace(">", "&gt;")
                prefix = "<a href=\"$escaped\">"; body = selected; suffix = "</a>"
            }
            "details" -> {
                prefix = "<details><summary>"; body = ""; suffix = "</summary>$selected</details>"
            }
            else -> { prefix = "<$tag>"; body = selected; suffix = "</$tag>" }
        }
        return Insertion(prefix + body + suffix, prefix.length, body.length)
    }
}
