package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import org.jsoup.Jsoup

sealed class AO3AccountParseException(message: String) : Exception(message) {
    class LoginRequired : AO3AccountParseException("AO3 account login is required.")
    class Overloaded : AO3AccountParseException("AO3 returned an overload or capacity page.")
    class MissingRequiredStructure(detail: String) : AO3AccountParseException(detail)
}

class AO3AccountParser(
    private val searchParser: AO3SearchParser = AO3SearchParser(),
    private val usernameParser: AO3UsernameParser = AO3UsernameParser()
) {
    fun parseAccountList(
        html: String,
        page: Int,
        type: AccountListType,
        finalUrl: String? = null
    ): AO3SearchPage {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3AccountParseException.Overloaded()
        if (usernameParser.isLoginRequiredPage(html, finalUrl)) throw AO3AccountParseException.LoginRequired()

        return when (type) {
            AccountListType.Bookmarks -> {
                val searchPage = searchParser.parseWorksListPage(html, page, "li.bookmark.blurb")
                val authorBookmarks = runCatching {
                    io.github.cidy02.kudos.network.ao3.author.AO3AuthorParser().parseBookmarksPage(html, page).bookmarks
                }.getOrDefault(emptyList())
                searchPage.copy(bookmarkDetails = authorBookmarks)
            }
            AccountListType.Subscriptions -> parseSubscriptionsPage(html, page)
            AccountListType.MarkedForLater,
            AccountListType.History -> {
                val searchPage = searchParser.parseSearchPage(html, page)
                val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
                val readings = doc.select("ol.reading.work > li, ol.work > li, li.reading.work")
                    .mapNotNull { AO3ReadingEntry.parseFromBlurb(it) }
                searchPage.copy(readingEntries = readings)
            }
            AccountListType.MyWorks,
            is AccountListType.Collection -> searchParser.parseSearchPage(html, page)
        }
    }

    /**
     * Parses a collections index (`li.collection.blurb`) into name/title/byline.
     * Mirrors Apple `AO3Client.parseCollections`.
     */
    fun parseCollections(html: String, finalUrl: String? = null): List<AO3Collection> {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3AccountParseException.Overloaded()
        if (usernameParser.isLoginRequiredPage(html, finalUrl)) throw AO3AccountParseException.LoginRequired()

        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        return document.select("li.collection.blurb").mapNotNull { li ->
            val link = li.selectFirst("h4.heading a[href*=/collections/]") ?: return@mapNotNull null
            val href = link.attr("href")
            val marker = "/collections/"
            val start = href.indexOf(marker)
            if (start < 0) return@mapNotNull null
            val slug = href.substring(start + marker.length)
                .substringBefore("/")
                .trim()
            if (slug.isEmpty()) return@mapNotNull null
            val title = link.normalizedText().ifBlank { slug }
            
            val maintainerLinks = li.select("h4.heading a[href*=/users/]")
            val maintainerNames = maintainerLinks.map { it.normalizedText() }
            val maintainerIdentities = maintainerLinks.map { linkEl ->
                AO3AuthorIdentity(displayName = linkEl.normalizedText(), href = linkEl.attr("href"))
            }
            val fallbackByline = li.selectFirst(".byline, .heading .byline")?.normalizedText().orEmpty()
            
            val typeText = li.selectFirst("p.type")?.normalizedText().orEmpty().lowercase()
            val isClosed = typeText.contains("closed")
            val isModerated = typeText.contains("moderated") && !typeText.contains("unmoderated")
            val isUnrevealed = typeText.contains("unrevealed")
            val isAnonymous = typeText.contains("anonymous")
            val challengeKind = when {
                typeText.contains("gift exchange") -> AO3ChallengeKind.GiftExchange
                typeText.contains("prompt meme") -> AO3ChallengeKind.PromptMeme
                else -> null
            }
            
            val worksText = li.selectFirst("dd.works")?.normalizedText()?.replace(",", "")?.toIntOrNull()
            val bookmarksText = li.selectFirst("dd.bookmarks")?.normalizedText()?.replace(",", "")?.toIntOrNull()
            
            val summary = li.selectFirst("blockquote.userstuff.summary")?.normalizedText().orEmpty()
            val updated = li.selectFirst("p.datetime")?.normalizedText().orEmpty()
            
            val viewerIsOwner = li.classNames().contains("own")
            
            AO3Collection(
                name = slug,
                title = title,
                summary = summary,
                byline = if (maintainerNames.isEmpty()) fallbackByline else maintainerNames.joinToString(", "),
                maintainerNames = maintainerNames,
                maintainerIdentities = maintainerIdentities,
                isClosed = isClosed,
                isModerated = isModerated,
                isUnrevealed = isUnrevealed,
                isAnonymous = isAnonymous,
                challengeKind = challengeKind,
                worksCount = worksText,
                bookmarksCount = bookmarksText,
                updatedAtText = updated,
                viewerIsOwner = viewerIsOwner
            )
        }
    }

    fun parseCollectionsIndex(
        html: String,
        page: Int = 1,
        finalUrl: String? = null
    ): AO3CollectionsIndexPage {
        val collections = parseCollections(html, finalUrl)
        val currentPage = page.coerceAtLeast(1)
        return AO3CollectionsIndexPage(
            collections, currentPage, Jsoup.parse(html).parseTotalPages(currentPage)
        )
    }

    fun parseSubscriptionsPage(html: String, page: Int): AO3SearchPage {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3AccountParseException.Overloaded()
        if (usernameParser.isLoginRequiredPage(html)) throw AO3AccountParseException.LoginRequired()

        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        val paths = mutableMapOf<Long, String>()
        val works = document.select("dl.subscription dt").mapNotNull { element ->
            val workLink = element.selectFirst("a[href*=/works/]") ?: return@mapNotNull null
            val workId = workIdFromPath(workLink.attr("href")) ?: return@mapNotNull null
            element.unsubscribeAction()?.let { paths.putIfAbsent(workId, it) }
            val title = workLink.normalizedText().ifBlank { "Untitled" }
            val authors = element.select("a[href*=/users/]").map { it.normalizedText() }
                .filter { it.isNotBlank() }
                .distinct()
            AO3WorkSummary(
                id = workId,
                title = title,
                authors = authors,
                fandoms = emptyList(),
                rating = "",
                warnings = emptyList(),
                categories = emptyList()
            )
        }

        return AO3SearchPage(
            works = works,
            currentPage = page.coerceAtLeast(1),
            totalPages = document.parseTotalPages(page.coerceAtLeast(1)),
            unsubscribePaths = paths
        )
    }

    /** iOS parseNamedSubscriptions: the first link selects the kind, not a byline link. */
    fun parseNamedSubscriptions(
        html: String,
        scope: AO3NamedSubscriptionsScope,
        page: Int = 1,
        finalUrl: String? = null
    ): AO3NamedSubscriptionsPage {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3AccountParseException.Overloaded()
        if (usernameParser.isLoginRequiredPage(html, finalUrl)) throw AO3AccountParseException.LoginRequired()
        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        val seen = mutableSetOf<String>()
        val rows = document.select("dl.subscription dt").mapNotNull { heading ->
            val links = heading.select("a[href]")
            val first = links.firstOrNull() ?: return@mapNotNull null
            val url = AO3Constants.baseHttpUrl.resolve(first.attr("href")) ?: return@mapNotNull null
            val parts = url.pathSegments.filter { it.isNotEmpty() }
            if (parts.size != 2 || parts[0] != scope.parameter) return@mapNotNull null
            if (scope == AO3NamedSubscriptionsScope.Series && parts[1].toLongOrNull() == null) return@mapNotNull null
            val path = url.encodedPath
            if (!seen.add(path)) return@mapNotNull null
            val creators = if (scope == AO3NamedSubscriptionsScope.Series) {
                links.drop(1).filter { it.attr("rel") == "author" }.map {
                    AO3AuthorIdentity(it.normalizedText(), it.attr("href"))
                }
            } else emptyList()
            AO3NamedSubscription(path, first.normalizedText(), creators, heading.unsubscribeAction())
        }
        val currentPage = page.coerceAtLeast(1)
        return AO3NamedSubscriptionsPage(rows, currentPage, document.parseTotalPages(currentPage))
    }

    private fun workIdFromPath(path: String): Long? {
        val marker = "/works/"
        val start = path.indexOf(marker)
        if (start < 0) return null
        return path.substring(start + marker.length)
            .takeWhile(Char::isDigit)
            .toLongOrNull()
    }
}

/** Same adjacent-dd action lookup as iOS unsubscribeAction(after:). */
private fun org.jsoup.nodes.Element.unsubscribeAction(): String? {
    val details = nextElementSibling()?.takeIf { it.tagName() == "dd" } ?: return null
    return details.selectFirst("form")?.attr("action")?.trim()?.takeIf { it.isNotEmpty() }
}

private fun org.jsoup.nodes.Document.parseTotalPages(currentPage: Int): Int {
    return select("ol.pagination li")
        .mapNotNull { it.normalizedText().toIntOrNull() }
        .fold(currentPage) { total, page -> maxOf(total, page) }
}

private fun org.jsoup.nodes.Element.normalizedText(): String {
    return text().replace(Regex("\\s+"), " ").trim()
}
