package io.github.cidy02.kudos.network.ao3.series

import io.github.cidy02.kudos.network.ao3.AO3Constants
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * Series page URL helpers. Mirrors Apple `AO3Client.seriesPageURL(_:page:)`:
 * strip any existing `page` query item, then re-add only for pages past the first.
 */
object AO3SeriesUrls {
    /**
     * Absolute AO3 series listing URL for [page].
     *
     * @return absolute https series URL, or null when [seriesUrl] is empty, not AO3,
     * or unparseable.
     */
    fun seriesPageUrl(seriesUrl: String, page: Int): String? {
        val trimmed = seriesUrl.trim()
        if (trimmed.isEmpty()) return null

        val parsed = trimmed.toHttpUrlOrNull()
            ?: AO3Constants.baseHttpUrl.resolve(trimmed)
            ?: return null

        if (!isAo3Host(parsed.host)) return null

        val safePage = page.coerceAtLeast(1)
        val builder = parsed.newBuilder().scheme("https")

        // Drop every existing `page` query item, then add only when needed.
        val names = parsed.queryParameterNames
        builder.query(null)
        for (name in names) {
            if (name.equals("page", ignoreCase = true)) continue
            for (value in parsed.queryParameterValues(name)) {
                if (value != null) {
                    builder.addQueryParameter(name, value)
                }
            }
        }
        if (safePage > 1) {
            builder.addQueryParameter("page", safePage.toString())
        }

        return builder.build().toString()
    }

    private fun isAo3Host(host: String): Boolean =
        host.equals(AO3Constants.WORKS_HOST, ignoreCase = true) ||
            host.endsWith(".${AO3Constants.WORKS_HOST}", ignoreCase = true)

    /** True when [url] looks like an AO3 `/series/<id>` path. */
    fun isSeriesUrl(url: String): Boolean {
        val parsed = url.trim().toHttpUrlOrNull() ?: return false
        if (!isAo3Host(parsed.host)) return false
        return parsed.encodedPath.matches(Regex("""/series/\d+/?"""))
    }
}
