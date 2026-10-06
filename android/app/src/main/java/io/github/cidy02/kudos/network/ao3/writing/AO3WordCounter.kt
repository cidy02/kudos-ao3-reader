package io.github.cidy02.kudos.network.ao3.writing

import org.jsoup.Jsoup
import org.jsoup.nodes.Comment
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode

/** iOS AO3WordCounter: count independently per HTML text node, using whole decoded text. */
object AO3WordCounter {
    fun count(html: String): Int {
        if (html.isEmpty()) return 0
        val body = runCatching { Jsoup.parseBodyFragment(html).body() }.getOrNull()
            ?: return countText(html)
        val pending = ArrayDeque<Node>()
        pending.addLast(body)
        var total = 0
        while (pending.isNotEmpty()) {
            when (val node = pending.removeLast()) {
                is TextNode -> total += countText(node.wholeText)
                is Comment -> Unit
                else -> pending.addAll(node.childNodes())
            }
        }
        return total
    }

    fun countText(text: String): Int {
        val normalized = text.replace("--", "—").replace(removed, "")
        var count = 0
        var inRun = false
        var offset = 0
        while (offset < normalized.length) {
            val point = normalized.codePointAt(offset)
            offset += Character.charCount(point)
            if (Character.UnicodeScript.of(point) in characterScripts) {
                count += 1
                inRun = false
            } else if (isWordCharacter(point)) {
                if (!inRun) count += 1
                inRun = true
            } else {
                inRun = false
            }
        }
        return count
    }

    private val removed = Regex("['’‘-]")
    private val characterScripts = setOf(Character.UnicodeScript.HAN, Character.UnicodeScript.HIRAGANA,
        Character.UnicodeScript.KATAKANA, Character.UnicodeScript.THAI)

    // Ruby's word class (and the iOS ICU expression): Alphabetic + M + Nd + Pc.
    private fun isWordCharacter(point: Int): Boolean = Character.isAlphabetic(point) ||
        Character.getType(point) in wordCategories

    private val wordCategories = setOf(Character.NON_SPACING_MARK.toInt(),
        Character.COMBINING_SPACING_MARK.toInt(), Character.ENCLOSING_MARK.toInt(),
        Character.DECIMAL_DIGIT_NUMBER.toInt(), Character.CONNECTOR_PUNCTUATION.toInt())
}

object WritingWordCount {
    fun count(html: String): Int = AO3WordCounter.count(html)
}
