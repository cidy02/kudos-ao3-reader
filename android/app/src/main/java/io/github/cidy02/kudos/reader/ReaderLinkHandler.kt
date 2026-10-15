package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.works.WorkTags
import java.net.URLDecoder
import java.net.URI

/** Where a link tapped inside the reader should be routed. */
sealed interface ReaderLinkDestination {
    /** An AO3 work link -> open native Work Detail. */
    data class WorkDetail(val workId: Long) : ReaderLinkDestination

    /** An AO3 tag link -> the tag's works page (iOS `TagWorksView`). */
    data class TagSearch(val tag: String) : ReaderLinkDestination

    /** An AO3 user or pseud link -> the author's page. */
    data class Author(val username: String) : ReaderLinkDestination

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
            authorFromUrl(url)?.let { return ReaderLinkDestination.Author(it) }
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
        // A "+" in a path is itself, not a space; AO3 writes "/" "&" "." "?" "#" as *s* *a* *d* *q* *h*.
        val decoded = runCatching { URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8") }.getOrDefault(raw)
        val name = MUNGED.fold(decoded) { text, (munged, plain) -> text.replace(munged, plain) }
        return name.takeIf { it.isNotBlank() }
    }

    /** iOS's `authorRoute(for:)`: /users/<name>, with or without a pseud after it. */
    private fun authorFromUrl(url: String): String? {
        val segments = runCatching { URI(url).path }.getOrNull()?.split('/')?.filter { it.isNotEmpty() } ?: return null
        return segments.getOrNull(1)?.takeIf { segments.first() == "users" }
    }

    private fun String.isAo3Url(): Boolean {
        val host = runCatching { URI(this).host }.getOrNull() ?: return false
        return host.equals(AO3_HOST, ignoreCase = true) ||
            host.endsWith(".$AO3_HOST", ignoreCase = true)
    }

    private companion object {
        val MUNGED = listOf("*s*" to "/", "*a*" to "&", "*d*" to ".", "*q*" to "?", "*h*" to "#")
        const val AO3_HOST = "archiveofourown.org"
    }
}
