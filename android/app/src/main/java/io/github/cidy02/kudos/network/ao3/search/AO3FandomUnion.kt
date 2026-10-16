package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import org.jsoup.Jsoup

/** Numeric canonical filter IDs, never autocomplete's name-valued IDs (iOS AO3FandomUnion). */
object AO3FandomUnion {
    fun queryClause(filterIDs: List<Long>): String? {
        val ids = filterIDs.distinct()
        return when (ids.size) {
            0 -> null
            1 -> "filter_ids:${ids.single()}"
            else -> "filter_ids:(${ids.joinToString(" OR ")})"
        }
    }

    fun filterID(html: String, tagName: String): Long? {
        val document = Jsoup.parse(html)
        for (feed in document.select(
            "head link[rel=alternate][type='application/atom+xml'], " +
                "#main > div.navigation.actions > ul.user.navigation.actions a[href]"
        )) {
            val href = feed.attr("href")
            if (href.startsWith("//")) continue
            val url = AO3Constants.baseHttpUrl.resolve(href) ?: continue
            if (!AO3RedirectCookieRelay.isTrustedUrl(url)) continue
            val match = Regex("^/tags/([0-9]+)/feed\\.atom$").matchEntire(url.encodedPath) ?: continue
            positiveID(match.groupValues[1])?.let { return it }
        }
        for (label in document.select("#work-filters label")) {
            val input = label.selectFirst("input") ?: continue
            if (input.attr("name") != "include_work_search[fandom_ids][]") continue
            val id = positiveID(input.attr("value")) ?: continue
            val name = label.text().replace(Regex("\\s+\\([0-9,]+\\)$"), "")
            if (name == tagName.trim()) return id
        }
        return null
    }

    private fun positiveID(value: String): Long? =
        value.takeIf { it.matches(Regex("[0-9]+")) }?.toLongOrNull()?.takeIf { it > 0 }
}
