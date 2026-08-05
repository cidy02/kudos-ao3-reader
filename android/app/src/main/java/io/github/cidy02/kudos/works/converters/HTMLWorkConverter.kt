package io.github.cidy02.kudos.works.converters

import io.github.cidy02.kudos.files.TextDecoding
import org.jsoup.Jsoup
import org.jsoup.safety.Safelist

/**
 * HTML → EPUB (iOS `HTMLWorkConverter` + `HTMLWorkSanitizer`).
 *
 * Sanitisation is a hard prerequisite, not a nicety: the reader renders this in
 * a WebView, so unsanitised imported HTML is a stored-XSS vector. Everything
 * goes through Jsoup's allowlist, with remote images stripped so opening a work
 * can't phone home.
 */
class HTMLWorkConverter {

    fun convert(title: String, bytes: ByteArray): ByteArray? {
        val raw = TextDecoding.decode(bytes) ?: return null
        val body = sanitizedBody(raw)
        return if (body.isBlank()) null else EpubBuilder.buildEpub(title, body)
    }

    /**
     * Extracts the readable region and sanitises it. AO3's own download markup
     * and fanfiction.net saved pages both wrap the prose in a known container;
     * anything else falls back to the whole body.
     */
    fun sanitizedBody(rawHtml: String): String {
        val document = Jsoup.parse(rawHtml)
        val region = CONTENT_SELECTORS.firstNotNullOfOrNull { selector ->
            document.selectFirst(selector)?.takeIf { it.text().isNotBlank() }
        } ?: document.body()
        // relaxed minus <img>: no remote fetches from imported content.
        return Jsoup.clean(region.html(), Safelist.relaxed().removeTags("img"))
    }

    /** Title from the document, for imports that don't carry a useful file name. */
    fun titleFrom(rawHtml: String): String? {
        val document = Jsoup.parse(rawHtml)
        return sequenceOf(
            document.selectFirst("#workskin .title"),
            document.selectFirst("h1.title"),
            document.selectFirst("title")
        ).firstNotNullOfOrNull { it?.text()?.trim()?.takeIf(String::isNotEmpty) }
    }

    private companion object {
        val CONTENT_SELECTORS = listOf(
            "#workskin",          // AO3 download markup
            "#chapters",          // AO3 multi-chapter
            "div.storytext",      // fanfiction.net saved page
            "article",
            "main"
        )
    }
}
