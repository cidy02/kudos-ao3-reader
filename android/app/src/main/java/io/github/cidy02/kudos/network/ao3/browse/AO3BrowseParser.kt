package io.github.cidy02.kudos.network.ao3.browse

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.parser.Parser

sealed class AO3BrowseParseException(message: String) : Exception(message) {
    class Overloaded : AO3BrowseParseException("AO3 returned an overload or capacity page.")
    class MissingRequiredStructure(detail: String) : AO3BrowseParseException(detail)
}

/**
 * Parses AO3's `/media` index and `/media/<name>/fandoms` pages. Selectors mirror
 * the Apple `mediaCategories()` / `fandoms(atPath:)` implementations. Overload pages
 * are detected before parsing so they never surface as an empty list.
 */
class AO3BrowseParser {

    fun parseMediaCategories(html: String): List<AO3MediaCategory> {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3BrowseParseException.Overloaded()
        val document = Jsoup.parse(html)
        val categories = document.select("ul.media.fandom.index.group li.medium.listbox.group")
            .mapNotNull { li ->
                val heading = li.selectFirst("h3.heading a") ?: return@mapNotNull null
                val name = heading.normalizedText()
                if (name.isEmpty()) return@mapNotNull null
                val fandomsPath = heading.attr("href").trim()
                val featured = li.select("a.tag")
                    .map { it.normalizedText() }
                    .filter { it.isNotEmpty() }
                    .dedupeFirstSeen()
                // Mirror Apple's mediaCategories() guard (`!name.isEmpty, !fandoms.isEmpty`):
                // drop categories with no featured fandoms so both platforms render the
                // same category list from the same /media markup.
                if (featured.isEmpty()) return@mapNotNull null
                AO3MediaCategory(name = name, fandomsPath = fandomsPath, featuredFandoms = featured)
            }
        if (categories.isEmpty()) {
            throw AO3BrowseParseException.MissingRequiredStructure("No AO3 media categories found.")
        }
        return categories
    }

    /**
     * Linear string scan, not a full Jsoup DOM parse — this page can list 10k+
     * fandoms (multi-MB HTML) and a full-DOM `select()` over that caused a
     * multi-second CPU spike + transient >1GB memory balloon on iOS, enough to
     * get the app jetsam-killed on device the moment Browse opened (BUG-5).
     * Mirrors Apple `AO3Client.parseFandomIndex`.
     */
    fun parseFandomList(html: String): List<AO3Fandom> {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3BrowseParseException.Overloaded()
        val fandoms = ArrayList<AO3Fandom>()
        val seen = linkedSetOf<String>()
        var cursor = 0

        // Each letter section is its own <ol class="fandom index group">.
        while (true) {
            val olOpen = html.indexOf("<ol", cursor)
            if (olOpen < 0) break
            val olTagEnd = html.indexOf('>', olOpen)
            if (olTagEnd < 0) break
            cursor = olTagEnd + 1
            val olClasses = tagClassList(html, olOpen + 3, olTagEnd)
            if ("fandom" !in olClasses || "index" !in olClasses) continue
            val blockEnd = html.indexOf("</ol>", cursor).let { if (it < 0) html.length else it }

            var linkCursor = cursor
            while (true) {
                val aOpen = html.indexOf("<a ", linkCursor)
                if (aOpen < 0 || aOpen >= blockEnd) break
                val aTagEnd = html.indexOf('>', aOpen)
                if (aTagEnd < 0 || aTagEnd >= blockEnd) break
                linkCursor = aTagEnd + 1
                val aClasses = tagClassList(html, aOpen + 3, aTagEnd)
                if ("tag" !in aClasses) continue
                val aClose = html.indexOf("</a>", aTagEnd + 1)
                if (aClose < 0 || aClose >= blockEnd) break

                val name = Parser.unescapeEntities(html.substring(aTagEnd + 1, aClose), false)
                    .replace(Regex("\\s+"), " ")
                    .trim()
                // The text between </a> and the next tag is the work count, e.g. " (1,234)".
                val tailEnd = html.indexOf('<', aClose + 4)
                    .let { if (it < 0 || it > blockEnd) blockEnd else it }
                val count = html.substring(aClose + 4, tailEnd).filter(Char::isDigit)
                    .takeIf { it.isNotEmpty() }?.toIntOrNull()

                if (name.isNotEmpty() && seen.add(name)) {
                    fandoms.add(AO3Fandom(name = name, workCount = count))
                }
                linkCursor = aClose + 4
            }
            cursor = blockEnd
        }
        if (fandoms.isEmpty()) {
            throw AO3BrowseParseException.MissingRequiredStructure("No fandoms found on category page.")
        }
        return fandoms
    }
}

/** The space-separated class names from a tag's attribute text (`<tag `..`>` span). */
private fun tagClassList(html: String, attrsStart: Int, attrsEnd: Int): List<String> {
    val attrs = html.substring(attrsStart, attrsEnd)
    val classAttr = attrs.indexOf("class=\"")
    if (classAttr < 0) return emptyList()
    val valueStart = classAttr + 7
    val valueEnd = attrs.indexOf('"', valueStart)
    if (valueEnd < 0) return emptyList()
    return attrs.substring(valueStart, valueEnd).split(" ").filter { it.isNotEmpty() }
}

private fun Element.normalizedText(): String = text().replace(Regex("\\s+"), " ").trim()

private fun Iterable<String>.dedupeFirstSeen(): List<String> {
    val seen = linkedSetOf<String>()
    forEach { value -> value.trim().takeIf { it.isNotEmpty() }?.let { seen += it } }
    return seen.toList()
}
