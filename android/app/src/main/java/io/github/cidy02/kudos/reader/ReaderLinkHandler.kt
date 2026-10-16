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

    /**
     * Any other AO3 page (a tag's bookmarks, a listing with a query) -> the app's own web view,
     * which keeps the exact address and, in the demo, answers it locally. The phone's browser
     * would leave the app and, in the demo, reach AO3.
     */
    data class AO3Page(val url: String) : ReaderLinkDestination

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
            val uri = runCatching { URI(url) }.getOrNull() ?: return ReaderLinkDestination.Unhandled
            val path = uri.rawPath.orEmpty()
                .split('/').filter { it.isNotEmpty() }.map(::decode)
            when (path.firstOrNull()) {
                "users" -> io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute.fromUrl(url)
                    ?.let { return ReaderLinkDestination.Author(it.username) }
                "tags" -> {
                    val tag = path.getOrNull(1)?.let(::unmunge)?.takeIf { it.isNotBlank() }
                    if (tag != null) {
                        // The native tag screen has no query/sublisting contract. Keep these
                        // links intact rather than silently changing what AO3 serves.
                        if (path.size > 2 && (path.size != 3 || path[2] != "works"))
                            return ReaderLinkDestination.AO3Page(url)
                        if (uri.rawQuery != null) {
                            val listing = if (path.size == 2) url.substringBefore('?').trimEnd('/') + "/works?" +
                                url.substringAfter('?') else url
                            return ReaderLinkDestination.AO3Page(listing)
                        }
                        return ReaderLinkDestination.TagSearch(tag)
                    }
                }
            }
            // A work anywhere in the path ("/collections/x/works/123", "/works/1/chapters/2").
            path.indexOf("works").takeIf { it >= 0 }?.let { path.getOrNull(it + 1)?.toLongOrNull() }
                ?.let { return ReaderLinkDestination.WorkDetail(it) }
            return ReaderLinkDestination.AO3Page(url)
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
