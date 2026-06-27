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
            AccountListType.Bookmarks -> searchParser.parseWorksListPage(html, page, "li.bookmark.blurb")
            AccountListType.Subscriptions -> parseSubscriptionsPage(html, page)
            AccountListType.MarkedForLater,
            AccountListType.History,
            AccountListType.MyWorks -> searchParser.parseSearchPage(html, page)
        }
    }

    fun parseSubscriptionsPage(html: String, page: Int): AO3SearchPage {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3AccountParseException.Overloaded()
        if (usernameParser.isLoginRequiredPage(html)) throw AO3AccountParseException.LoginRequired()

        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        val works = document.select("dl.subscription dt").mapNotNull { element ->
            val workLink = element.selectFirst("a[href*=/works/]") ?: return@mapNotNull null
            val workId = workIdFromPath(workLink.attr("href")) ?: return@mapNotNull null
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
            totalPages = document.parseTotalPages(page.coerceAtLeast(1))
        )
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

private fun org.jsoup.nodes.Document.parseTotalPages(currentPage: Int): Int {
    return select("ol.pagination li")
        .mapNotNull { it.normalizedText().toIntOrNull() }
        .fold(currentPage) { total, page -> maxOf(total, page) }
}

private fun org.jsoup.nodes.Element.normalizedText(): String {
    return text().replace(Regex("\\s+"), " ").trim()
}
