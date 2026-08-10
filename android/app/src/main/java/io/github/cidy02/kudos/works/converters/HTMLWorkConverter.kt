package io.github.cidy02.kudos.works.converters

import io.github.cidy02.kudos.files.TextDecoding
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import org.jsoup.safety.Safelist

/**
 * HTML → EPUB (iOS `HTMLWorkConverter` + `HTMLWorkSanitizer`).
 *
 * Sanitisation is a hard prerequisite, not a nicety: the reader renders this in
 * a WebView, so unsanitised imported HTML is a stored-XSS vector. Everything
 * goes through Jsoup's allowlist, with remote images stripped so opening a work
 * can't phone home.
 *
 * Output uses XML syntax so void elements (`br`, `hr`, `col`) serialise as
 * self-closing tags (`<br />`) and the chapter stays well-formed XHTML for
 * strict EPUB parsers — same rationale as iOS `HTMLWorkSanitizer`.
 *
 * Author's notes: AO3 download markup labels notes as `div.notes` /
 * `div.end.notes` / etc. Those containers are rewritten to
 * `<aside class="author-note">` before cleaning (iOS
 * `HTMLWorkSanitizer.markingAuthorNotes`), so the EPUB ships the same class the
 * stylesheet and reader style. Structural only — no text heuristics here.
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
        markAuthorNotes(region)
        // relaxed minus <img>: no remote fetches from imported content.
        // `aside` + class preserved so author's notes survive the clean
        // (iOS HTMLWorkSanitizer allowlist).
        // XML syntax so void elements close properly inside application/xhtml+xml.
        // A fresh OutputSettings per call: it carries a lazily-prepared charset
        // encoder and is not thread-safe, so it is not worth sharing one instance
        // to save an allocation this size.
        return Jsoup.clean(
            region.html(),
            "",
            bodySafelist(),
            Document.OutputSettings().syntax(Document.OutputSettings.Syntax.xml)
        )
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

    /**
     * Rewrites AO3 note containers into `<aside class="author-note">` so the
     * reader has one class to style regardless of import path. Mutates [region]
     * in place; callers only read [region.html] afterwards.
     *
     * `.summary` is deliberately absent: a work summary is metadata, not
     * apparatus inside the prose (iOS same omission).
     */
    internal fun markAuthorNotes(region: Element) {
        val notes = AUTHOR_NOTE_SELECTORS
            .flatMap { region.select(it) }
            .distinct()
        for (note in notes) {
            note.tagName("aside")
            note.attr("class", "author-note")
        }
    }

    private companion object {
        val CONTENT_SELECTORS = listOf(
            "#workskin",          // AO3 download markup
            "#chapters",          // AO3 multi-chapter
            "div.storytext",      // fanfiction.net saved page
            "article",
            "main"
        )

        /** iOS `HTMLWorkSanitizer.authorNoteSelectors` — structural certainty only. */
        val AUTHOR_NOTE_SELECTORS = listOf(
            "div.notes",
            "div.end.notes",
            ".preface .notes",
            ".chapter .notes",
            "#notes"
        )

        fun bodySafelist(): Safelist = Safelist.relaxed()
            .removeTags("img")
            .addTags("aside")
            .addAttributes("aside", "class")
    }
}
