package io.github.cidy02.kudos.network.ao3.browse

import io.github.cidy02.kudos.network.ao3.AO3Constants
import okhttp3.HttpUrl.Companion.toHttpUrl

/**
 * Builds and validates AO3 Browse URLs. All output is guaranteed to live on the
 * AO3 host; non-AO3 input resolves to null so callers can externalize it.
 */
object AO3BrowseUrls {
    const val MEDIA_PATH = "/media"

    /** AO3's media index listing the fandom categories. */
    fun mediaIndexUrl(): String =
        AO3Constants.baseHttpUrl.newBuilder().encodedPath(MEDIA_PATH).build().toString()

    /**
     * Resolve a category's fandom-index href (relative like `/media/TV%20Shows/fandoms`
     * or absolute) to an absolute AO3 URL. Returns null when the result is not an AO3
     * URL (open-redirect / off-site protection). Preserves existing percent-encoding;
     * does not double-encode.
     */
    fun resolveAo3Url(pathOrUrl: String): String? {
        val trimmed = pathOrUrl.trim()
        if (trimmed.isEmpty()) return null
        val resolved = runCatching { AO3Constants.baseHttpUrl.resolve(trimmed) }.getOrNull() ?: return null
        return if (isAo3Host(resolved.host)) resolved.toString() else null
    }

    /** True when [url] is an absolute https AO3 URL (apex or subdomain). */
    fun isAo3Url(url: String): Boolean {
        val parsed = runCatching { url.trim().toHttpUrl() }.getOrNull() ?: return false
        return parsed.scheme == "https" && isAo3Host(parsed.host)
    }

    private fun isAo3Host(host: String): Boolean =
        host.equals(AO3Constants.WORKS_HOST, ignoreCase = true) ||
            host.endsWith(".${AO3Constants.WORKS_HOST}", ignoreCase = true)
}
