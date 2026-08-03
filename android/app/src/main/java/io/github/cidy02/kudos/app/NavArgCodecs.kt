package io.github.cidy02.kudos.app

import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.works.WorkDetailSource
import java.net.URLDecoder
import java.net.URLEncoder

/**
 * Encodes/decodes the two nav-argument types that don't reduce to a single
 * primitive (T-90). Route arguments must be plain strings, so these turn each
 * sealed type into a short discriminated string and back. Pure/testable on
 * purpose - no Compose or NavController dependency.
 */
internal object NavArgCodecs {
    /**
     * [WorkDetailSource.RemoteSummary] collapses to the same `ao3:<id>` form as
     * [WorkDetailSource.Ao3WorkId] - the full [io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary]
     * can't travel through a route string. AppNavHost keeps a small id-keyed
     * cache alongside this so a summary navigated-to moments ago still shows
     * instantly; only a genuinely stale/evicted entry falls back to a fresh
     * AO3 fetch (the same fetch [WorkDetailSource.Ao3WorkId] already does).
     */
    fun encodeWorkDetailSource(source: WorkDetailSource): String = when (source) {
        is WorkDetailSource.LocalWork -> "local:${source.workId}"
        is WorkDetailSource.RemoteSummary -> "ao3:${source.summary.id}"
        is WorkDetailSource.RemoteUrl -> "url:${URLEncoder.encode(source.url, "UTF-8")}"
        is WorkDetailSource.Ao3WorkId -> "ao3:${source.workId}"
    }

    fun decodeWorkDetailSource(encoded: String): WorkDetailSource? {
        val kind = encoded.substringBefore(':', missingDelimiterValue = "")
        val value = encoded.substringAfter(':', missingDelimiterValue = "")
        if (value.isEmpty()) return null
        return when (kind) {
            "local" -> WorkDetailSource.LocalWork(value)
            "ao3" -> value.toLongOrNull()?.let { WorkDetailSource.Ao3WorkId(it) }
            "url" -> WorkDetailSource.RemoteUrl(URLDecoder.decode(value, "UTF-8"))
            else -> null
        }
    }

    fun encodeAccountListType(type: AccountListType): String = when (type) {
        AccountListType.MarkedForLater -> "MarkedForLater"
        AccountListType.Bookmarks -> "Bookmarks"
        AccountListType.History -> "History"
        AccountListType.Subscriptions -> "Subscriptions"
        AccountListType.MyWorks -> "MyWorks"
        is AccountListType.Collection ->
            "Collection:${URLEncoder.encode(type.name, "UTF-8")}:${URLEncoder.encode(type.displayTitle, "UTF-8")}"
    }

    fun decodeAccountListType(encoded: String): AccountListType? {
        if (encoded.startsWith("Collection:")) {
            val parts = encoded.removePrefix("Collection:").split(":", limit = 2)
            if (parts.size != 2) return null
            return AccountListType.Collection(
                name = URLDecoder.decode(parts[0], "UTF-8"),
                displayTitle = URLDecoder.decode(parts[1], "UTF-8")
            )
        }
        return when (encoded) {
            "MarkedForLater" -> AccountListType.MarkedForLater
            "Bookmarks" -> AccountListType.Bookmarks
            "History" -> AccountListType.History
            "Subscriptions" -> AccountListType.Subscriptions
            "MyWorks" -> AccountListType.MyWorks
            else -> null
        }
    }
}
