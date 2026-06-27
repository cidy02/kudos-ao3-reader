package io.github.cidy02.kudos.network.ao3.browse

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

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

    fun parseFandomList(html: String): List<AO3Fandom> {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3BrowseParseException.Overloaded()
        val document = Jsoup.parse(html)
        val seen = linkedSetOf<String>()
        val fandoms = document.select("ol.fandom.index li").mapNotNull { li ->
            val link = li.selectFirst("a.tag") ?: return@mapNotNull null
            val name = link.normalizedText()
            if (name.isEmpty() || !seen.add(name)) return@mapNotNull null
            // The li's own text after the link is the work count, e.g. "(1,234)".
            val count = li.ownText().filter(Char::isDigit).takeIf { it.isNotEmpty() }?.toIntOrNull()
            AO3Fandom(name = name, workCount = count)
        }
        if (fandoms.isEmpty()) {
            throw AO3BrowseParseException.MissingRequiredStructure("No fandoms found on category page.")
        }
        return fandoms
    }
}

private fun Element.normalizedText(): String = text().replace(Regex("\\s+"), " ").trim()

private fun Iterable<String>.dedupeFirstSeen(): List<String> {
    val seen = linkedSetOf<String>()
    forEach { value -> value.trim().takeIf { it.isNotEmpty() }?.let { seen += it } }
    return seen.toList()
}
