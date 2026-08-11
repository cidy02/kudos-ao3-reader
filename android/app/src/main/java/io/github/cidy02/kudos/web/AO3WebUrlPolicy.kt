package io.github.cidy02.kudos.web

import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls

/** What the WebView fallback should do with a navigation target. */
sealed interface WebNavDecision {
    /** An AO3 https URL — keep it inside the in-app WebView. */
    data object Allow : WebNavDecision

    /** A non-AO3 http(s) URL — hand off to an external browser, do not load in-app. */
    data class External(val url: String) : WebNavDecision

    /** A non-web scheme (intent:, javascript:, file:, etc.) — refuse entirely. */
    data object Block : WebNavDecision
}

/**
 * URL policy for the read-only AO3 WebView fallback: only AO3 https pages stay in
 * the app WebView; other http(s) links are externalized; non-web schemes are blocked.
 * This prevents the in-app WebView from becoming an open browser or following
 * `javascript:`/`intent:` redirects.
 */
object AO3WebUrlPolicy {
    fun classify(url: String): WebNavDecision {
        val trimmed = url.trim()
        if (AO3BrowseUrls.isAo3Url(trimmed)) return WebNavDecision.Allow
        val lower = trimmed.lowercase()
        return if (lower.startsWith("http://") || lower.startsWith("https://")) {
            WebNavDecision.External(trimmed)
        } else {
            WebNavDecision.Block
        }
    }

    fun isAllowedInApp(url: String): Boolean = classify(url) is WebNavDecision.Allow
}
