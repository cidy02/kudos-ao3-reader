package io.github.cidy02.kudos.writing

import java.net.URI
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode

/** Read-only counterpart of iOS parseRichText, not a sanitizer or a source serializer. */
object WritingBufferPreview {
    data class Run(val text: String, val isBold: Boolean, val isItalic: Boolean, val link: String?)
    data class Block(val listItem: Boolean, val runs: List<Run>)
    sealed interface State {
        data class Rendered(val blocks: List<Block>) : State
        data object Failed : State
    }

    fun state(html: String): State = runCatching {
        val root = Jsoup.parseBodyFragment(html).body()
        val elements = mutableListOf<Pair<Element, Boolean>>()
        fun collect(element: Element) {
            for (child in element.children()) when (child.normalName()) {
                "p", "div", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6" -> elements += child to false
                "li" -> elements += child to true
                else -> collect(child)
            }
        }
        wrapLoose(root)
        collect(root)
        if (elements.isEmpty()) elements += root to false
        State.Rendered(elements.mapNotNull { (element, listItem) ->
            val runs = mutableListOf<Run>()
            fun append(node: Node, bold: Boolean, italic: Boolean, link: String?) {
                if (node is TextNode) {
                    runs += Run(node.wholeText, bold, italic, link)
                    return
                }
                if (node !is Element) return // Script/style DataNodes aren't displayed, matching SwiftSoup.
                val tag = node.normalName()
                if (tag == "br") { runs += Run("\n", bold, italic, link); return }
                val nextLink = if (tag == "a") safeRichTextURL(node.attr("href")) ?: link else link
                for (child in node.childNodes()) append(child, bold || tag in listOf("b", "strong"),
                    italic || tag in listOf("i", "em"), nextLink)
            }
            append(element, false, false, null)
            val normalized = mutableListOf<Run>()
            for (run in runs) {
                val text = run.text.replace(Regex("[\t\r ]+"), " ")
                if (text.isEmpty()) continue
                val last = normalized.lastOrNull()
                if (last != null && last.isBold == run.isBold && last.isItalic == run.isItalic && last.link == run.link) {
                    normalized[normalized.lastIndex] = last.copy(text = last.text + text)
                } else normalized += run.copy(text = text)
            }
            if (normalized.isEmpty()) null else Block(listItem, normalized)
        })
    }.getOrDefault(State.Failed)

    private const val BLOCKS = "p, div, blockquote, h1, h2, h3, h4, h5, h6, li"

    /**
     * AO3 puts loose text into paragraphs when it posts. iOS's parser keeps only block elements once
     * there is one, so words typed outside a tag vanished from the preview beside a single <p>.
     * Each stretch of loose nodes becomes a paragraph of its own, in place.
     */
    private fun wrapLoose(parent: Element) {
        var loose: Element? = null
        for (node in parent.childNodes().toList()) {
            if (node is Element && (node.`is`(BLOCKS) || node.selectFirst(BLOCKS) != null)) {
                loose = null
                if (!node.`is`(BLOCKS)) wrapLoose(node)
            } else if (loose != null || node !is TextNode || !node.isBlank) {
                val paragraph = loose ?: Element("p").also { node.before(it); loose = it }
                paragraph.appendChild(node)
            }
        }
        for (paragraph in parent.children().filter { it.normalName() == "p" }) {
            (paragraph.childNodes().firstOrNull() as? TextNode)?.let { it.text(it.wholeText.trimStart()) }
            (paragraph.childNodes().lastOrNull() as? TextNode)?.let { it.text(it.wholeText.trimEnd()) }
        }
    }

    fun publishes(generation: Int, current: Int, isPreviewing: Boolean): Boolean =
        isPreviewing && generation == current

    private fun safeRichTextURL(value: String): String? = runCatching {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return@runCatching null
        val url = URI("https://archiveofourown.org").resolve(trimmed)
        if (url.scheme?.lowercase() in listOf("http", "https")) url.toString() else null
    }.getOrNull()
}
