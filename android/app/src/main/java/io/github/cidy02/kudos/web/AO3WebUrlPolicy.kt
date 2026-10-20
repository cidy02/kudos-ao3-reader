package io.github.cidy02.kudos.web

import okhttp3.HttpUrl.Companion.toHttpUrl
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
    /** iOS BrowserThemeStyle.navigationVerdict; demo AO3 loads are served by local interception. */
    fun navigationVerdict(url: String, isMainFrame: Boolean, isDemo: Boolean): WebNavDecision {
        if (url.trim().startsWith("about:", ignoreCase = true)) return WebNavDecision.Allow
        val decision = classify(url)
        if (decision == WebNavDecision.Block) return decision
        if (isDemo) return if (decision == WebNavDecision.Allow) decision else WebNavDecision.Block
        return if (isMainFrame) decision else WebNavDecision.Allow
    }

    fun mayOpenExternal(url: String, isDemo: Boolean): Boolean =
        !isDemo && classify(url) != WebNavDecision.Block

    fun addressUrl(input: String): String? {
        val text = input.trim().takeIf { it.isNotEmpty() } ?: return null
        if (Regex("^[A-Za-z][A-Za-z0-9+.-]*:").containsMatchIn(text)) return text
        return "https://archiveofourown.org/works/search".toHttpUrl().newBuilder()
            .addQueryParameter("work_search[query]", text).build().toString()
    }

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
