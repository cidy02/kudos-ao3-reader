package io.github.cidy02.kudos.reader

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
            // From the path alone: a query or fragment ("?next=/works/123", "#top") named a
            // different page or became part of a tag (A49 F5).
            val path = runCatching { URI(url).rawPath }.getOrNull().orEmpty()
                .split('/').filter { it.isNotEmpty() }.map(::decode)
            when (path.firstOrNull()) {
                "users" -> path.getOrNull(1)?.takeIf { it.isNotBlank() }?.let { return ReaderLinkDestination.Author(it) }
                "tags" -> path.getOrNull(1)?.let(::unmunge)?.takeIf { it.isNotBlank() }
                    ?.let { return ReaderLinkDestination.TagSearch(it) }
            }
            // A work anywhere in the path ("/collections/x/works/123", "/works/1/chapters/2").
            path.indexOf("works").takeIf { it >= 0 }?.let { path.getOrNull(it + 1)?.toLongOrNull() }
                ?.let { return ReaderLinkDestination.WorkDetail(it) }
        }

        return if (url.startsWith("http://", true) || url.startsWith("https://", true)) {
            ReaderLinkDestination.External(url)
        } else {
            ReaderLinkDestination.Unhandled
        }
    }

    // A "+" in a path is itself, not a space.
    private fun decode(segment: String): String =
        runCatching { URLDecoder.decode(segment.replace("+", "%2B"), "UTF-8") }.getOrDefault(segment)

    /** AO3 writes "/" "&" "." "?" "#" in a tag's address as *s* *a* *d* *q* *h*. */
    private fun unmunge(tag: String): String = MUNGED.fold(tag) { text, (munged, plain) -> text.replace(munged, plain) }

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
