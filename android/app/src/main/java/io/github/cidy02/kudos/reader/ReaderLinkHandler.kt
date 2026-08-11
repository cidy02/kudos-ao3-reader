package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.works.WorkTags
import java.net.URLDecoder
import java.net.URI

/** Where a link tapped inside the reader should be routed. */
sealed interface ReaderLinkDestination {
    /** An AO3 work link -> open native Work Detail. */
    data class WorkDetail(val workId: Long) : ReaderLinkDestination

    /** An AO3 tag link -> Search/Browse (wiring deferred; see HANDOFF.md). */
    data class TagSearch(val tag: String) : ReaderLinkDestination

    /** Any other absolute URL -> open externally (browser/custom tab/intent). */
    data class External(val url: String) : ReaderLinkDestination

    /** Relative/in-publication links and empty input -> let the navigator handle it. */
    data object Unhandled : ReaderLinkDestination
}

/**
 * Classifies links tapped inside the reader. Pure and side-effect free so it is
 * unit-testable; actual navigation/intent dispatch happens in the UI layer.
 */
class ReaderLinkHandler {
    fun classify(rawUrl: String): ReaderLinkDestination {
        val url = rawUrl.trim()
        if (url.isEmpty()) return ReaderLinkDestination.Unhandled

        if (url.isAo3Url()) {
            WorkTags.ao3WorkIdFromUrl(url)?.let { return ReaderLinkDestination.WorkDetail(it) }
            tagFromUrl(url)?.let { return ReaderLinkDestination.TagSearch(it) }
        }

        return if (url.startsWith("http://", true) || url.startsWith("https://", true)) {
            ReaderLinkDestination.External(url)
        } else {
            ReaderLinkDestination.Unhandled
        }
    }

    private fun tagFromUrl(url: String): String? {
        val marker = "/tags/"
        val index = url.indexOf(marker)
        if (index < 0) return null
        val raw = url.substring(index + marker.length).substringBefore('/').substringBefore('?')
        if (raw.isBlank()) return null
        val decoded = runCatching { URLDecoder.decode(raw, "UTF-8") }.getOrDefault(raw)
        return decoded.takeIf { it.isNotBlank() }
    }

    private fun String.isAo3Url(): Boolean {
        val host = runCatching { URI(this).host }.getOrNull() ?: return false
        return host.equals(AO3_HOST, ignoreCase = true) ||
            host.endsWith(".$AO3_HOST", ignoreCase = true)
    }

    private companion object {
        const val AO3_HOST = "archiveofourown.org"
    }
}
