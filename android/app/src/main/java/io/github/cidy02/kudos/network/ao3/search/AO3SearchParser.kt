package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

sealed class AO3SearchParseException(message: String) : Exception(message) {
    class Overloaded : AO3SearchParseException("AO3 returned an overload or capacity page.")
    class MissingRequiredStructure(detail: String) : AO3SearchParseException(detail)
}

class AO3SearchParser {
    fun parseSearchPage(html: String, page: Int): AO3SearchPage {
        return parseWorksListPage(html, page, blurbSelector = "li.work.blurb")
    }

    fun parseWorksListPage(
        html: String,
        page: Int,
        blurbSelector: String
    ): AO3SearchPage {
        if (AO3OverloadDetector.isOverloadPage(html)) {
            throw AO3SearchParseException.Overloaded()
        }

        val currentPage = page.coerceAtLeast(1)
        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        val works = document.select(blurbSelector)
            .mapNotNull { element ->
                runCatching { parseWorkSummary(element) }.getOrNull()
            }

        return AO3SearchPage(
            works = works,
            currentPage = currentPage,
            totalPages = parseTotalPages(document, currentPage),
            summary = parseResultSummary(document)
        )
    }

    /**
     * AO3's result-count heading. `/works/search` puts it in an `h3.heading`
     * ("92,495 Found"); tag and user works lists use an `h2.heading`
     * ("1 - 20 of 142,322 Works in <tag>"). Both live under `#main`, so this takes
     * the first heading there that parses rather than guessing per endpoint.
     *
     * Null is a normal outcome, not a failure: a search with no matches omits the
     * heading entirely (measured — a zero-result `/works/search` renders only
     * "Search Results"), and the count is decoration, so it must never fail a page
     * whose works parsed fine.
     */
    private fun parseResultSummary(document: Document): AO3ResultSummary? {
        return document.select("#main h2.heading, #main h3.heading")
            .firstNotNullOfOrNull { parseResultSummary(it.text()) }
    }

    fun parseWorkSummary(element: Element): AO3WorkSummary {
        val id = parseWorkId(element)
            ?: throw AO3SearchParseException.MissingRequiredStructure("Work blurb has no AO3 work id.")

        val title = element.selectFirst("h4.heading a[href^=/works/]")
            ?.normalizedText()
            ?.takeIf { it.isNotBlank() }
            ?: element.selectFirst("h4.heading a")
                ?.normalizedText()
                ?.takeIf { it.isNotBlank() }
            ?: "Untitled"

        val authors = element.select("h4.heading a[rel=author]").normalizedTexts()
        val fandoms = element.select("h5.fandoms a.tag").normalizedTexts()
        val rating = element.selectFirst("ul.required-tags .rating .text")?.normalizedText().orEmpty()
        val warnings = element.select("ul.required-tags .warnings .text").normalizedTexts()
        val categories = element.select("ul.required-tags .category .text").normalizedTexts()
        val wipText = element.selectFirst("ul.required-tags .iswip .text")?.normalizedText().orEmpty()
        val isComplete = wipText.takeIf { it.isNotBlank() }
            ?.lowercase()
            ?.contains("complete")
        val updatedDate = element.selectFirst("p.datetime")?.normalizedText().orEmpty()

        val allTags = element.select("ul.tags li a.tag").normalizedTexts()
        val relationships = element.select("ul.tags li.relationships a.tag").normalizedTexts()
        val characters = element.select("ul.tags li.characters a.tag").normalizedTexts()
        val warningTags = element.select("ul.tags li.warnings a.tag").normalizedTexts()
        val categorized = (relationships + characters + warningTags).toSet()
        val freeforms = allTags.filterNot(categorized::contains).dedupeFirstSeen()

        val seriesLink = element.selectFirst("ul.series li a[href*=/series/]")
        val seriesHref = seriesLink?.attr("href")
        val seriesUrl = seriesHref?.takeIf { it.isNotBlank() }?.let(::absoluteAO3Url)
        val seriesTitle = seriesLink?.normalizedText()?.takeIf { it.isNotBlank() }
        val seriesPosition = element.selectFirst("ul.series li strong")
            ?.normalizedText()
            ?.toIntOrNull()

        return AO3WorkSummary(
            id = id,
            title = title,
            authors = authors,
            fandoms = fandoms,
            rating = rating,
            warnings = warnings,
            categories = categories,
            relationships = relationships,
            characters = characters,
            freeforms = freeforms,
            summary = element.selectFirst("blockquote.userstuff.summary")?.normalizedText().orEmpty(),
            language = stat(element, "language"),
            wordCount = statInt(element, "words"),
            chapters = stat(element, "chapters"),
            kudos = statInt(element, "kudos"),
            comments = statInt(element, "comments"),
            hits = statInt(element, "hits"),
            bookmarks = statInt(element, "bookmarks"),
            seriesTitle = seriesTitle,
            seriesPosition = seriesPosition,
            seriesUrl = seriesUrl,
            isComplete = isComplete,
            isRestricted = element.hasVisibleRestrictedMarker(),
            updatedDate = updatedDate,
            publishedDate = element.selectFirst("p.published, dd.published")?.normalizedText()
        )
    }

    private fun parseWorkId(element: Element): Long? {
        element.id()
            .removePrefix("work_")
            .toLongOrNull()
            ?.let { return it }

        val href = element.selectFirst("h4.heading a[href*=/works/]")?.attr("href")
            ?: element.selectFirst("a[href*=/works/]")?.attr("href")
        return href?.let(::workIdFromPath)
    }

    private fun workIdFromPath(path: String): Long? {
        val marker = "/works/"
        val start = path.indexOf(marker)
        if (start < 0) return null
        return path.substring(start + marker.length)
            .takeWhile(Char::isDigit)
            .toLongOrNull()
    }

    private fun parseTotalPages(document: Document, currentPage: Int): Int {
        return document.select("ol.pagination li")
            .mapNotNull { it.normalizedText().toIntOrNull() }
            .fold(currentPage) { total, page -> maxOf(total, page) }
    }

    private fun stat(element: Element, className: String): String {
        return element.selectFirst("dl.stats dd.$className")?.normalizedText().orEmpty()
    }

    private fun statInt(element: Element, className: String): Int? {
        val digits = stat(element, className).filter(Char::isDigit)
        return digits.takeIf { it.isNotEmpty() }?.toIntOrNull()
    }

    private fun absoluteAO3Url(href: String): String {
        return when {
            href.startsWith("http://") || href.startsWith("https://") -> href
            href.startsWith("/") -> AO3Constants.BASE_URL + href
            else -> "${AO3Constants.BASE_URL}/$href"
        }
    }
}

/**
 * Pure (unit-tested): AO3's heading text -> total + scope + range.
 *
 * Handles the live shapes with one pass, because they differ only in which noun
 * follows the number and whether a "1 - 20 of" range precedes it:
 *   - `92,495 Found`
 *   - `1 - 20 of 142,322 Works in Naruto (Anime & Manga)`
 *   - `1 - 20 of 535 Works by astolat`
 *   - `1 - 20 of 88,698 Works **found** in <tag>`, the moment a query is applied
 *
 * The number taken is always the one immediately before `Works`/`Found`, so a
 * leading range can never be mistaken for the total — that is the whole reason
 * this anchors on the noun rather than on "the first number".
 */
fun parseResultSummary(text: String): AO3ResultSummary? {
    val collapsed = text.replace(Regex("\\s+"), " ").trim()
    val noun = Regex("([\\d,]+)\\s+(Works|Work|Found)\\b").find(collapsed) ?: return null
    val total = noun.groupValues[1].filter { it.isDigit() }.toIntOrNull() ?: return null

    // "1 - 20 of " immediately before the total — which works this page shows.
    // Anchored to the end of the prefix so it can only be the range belonging to
    // this count, never a stray pair of numbers elsewhere in the heading (a fandom
    // named "5 - 10 Years Later" must not produce one).
    val prefix = collapsed.substring(0, noun.range.first)
    val range = Regex("([\\d,]+)\\s*-\\s*([\\d,]+)\\s+of\\s+$").find(prefix)?.let { match ->
        val from = match.groupValues[1].filter { it.isDigit() }.toIntOrNull()
        val to = match.groupValues[2].filter { it.isDigit() }.toIntOrNull()
        if (from != null && to != null && from <= to) from..to else null
    }

    // What follows the noun is AO3's qualifier, kept verbatim (preposition
    // included). It is always "in <tag>" or "by <user>", and requiring that is not
    // pedantry: `/works/search` appends a help link inside the same heading, so the
    // heading's *text* is "92,495 Found  ?" and a naive "everything after the noun"
    // would make the scope "?".
    var rest = collapsed.substring(noun.range.last + 1).trim()
    // A tag list says "N Works in <tag>" — but with a `work_search[query]` active it
    // says "N Works **found** in <tag>". Browse sends a query for excluded warnings
    // and categories, so that is its common case, not an oddity. Measured live.
    if (rest.startsWith("found ")) rest = rest.removePrefix("found ")
    val scope = if (rest.startsWith("in ") || rest.startsWith("by ")) rest else null

    return AO3ResultSummary(total = total, scope = scope, range = range)
}

private fun Iterable<Element>.normalizedTexts(): List<String> {
    return map { it.normalizedText() }
        .filter { it.isNotBlank() }
        .dedupeFirstSeen()
}

private fun Element.normalizedText(): String {
    return text().replace(Regex("\\s+"), " ").trim()
}

private fun Element.hasVisibleRestrictedMarker(): Boolean {
    if (select(".restricted, .locked, .icon.locked, span.restricted, span.locked").isNotEmpty()) {
        return true
    }
    return select("span, p, li")
        .any { it.normalizedText().equals("Restricted", ignoreCase = true) }
}
