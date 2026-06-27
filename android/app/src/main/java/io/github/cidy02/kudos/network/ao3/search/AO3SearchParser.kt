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
            totalPages = parseTotalPages(document, currentPage)
        )
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
