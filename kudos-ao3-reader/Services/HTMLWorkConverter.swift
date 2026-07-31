import Foundation
import OSLog
import SwiftSoup

/// Turns a saved HTML page into EPUB chapters.
///
/// This is the format that matters most for community-redistributed works: it is
/// what AO3's own "Download → HTML" produces, what a browser "Save Page As"
/// produces, and what Wayback snapshots and SingleFile captures look like.
///
/// Everything here is defensive. The input is a file a stranger posted to a
/// forum, so it is parsed with SwiftSoup, stripped to an allowlist, and
/// re-serialized as XHTML — never interpolated into the EPUB as-is.
nonisolated enum HTMLWorkConverter {
    struct Result {
        var metadata: EPUBBuilder.Metadata
        var chapters: [EPUBBuilder.Chapter]
    }

    /// Converts `html` into metadata plus chapters.
    ///
    /// `fallbackTitle` is used when the document carries no usable title — the
    /// caller passes the file name, which for community copies is often the only
    /// title information that exists.
    static func convert(html: String, fallbackTitle: String) throws -> Result {
        let document = try SwiftSoup.parse(html)
        let metadata = try readMetadata(document, fallbackTitle: fallbackTitle)
        let chapters = try readChapters(document, workTitle: metadata.title)
        guard !chapters.isEmpty else { throw EPUBBuilder.BuildError.noChapters }
        return Result(metadata: metadata, chapters: chapters)
    }

    // MARK: - Metadata

    /// Reads what the page states about itself. Selectors mirror the ones
    /// `AO3EPUBMetadataScanner` already uses on EPUB-internal HTML, so an AO3
    /// download is understood the same way whichever door it comes in through.
    private static func readMetadata(
        _ document: Document,
        fallbackTitle: String
    ) throws -> EPUBBuilder.Metadata {
        let title = firstText(document, ["h1.title", "h2.title", ".preface .title", "title", "h1"])
        let author = firstText(document, [
            "h3.byline a[rel=author]", "h3.byline a", ".byline a[rel=author]", ".byline"
        ])
        let summary = firstText(document, [
            ".summary blockquote", "blockquote.userstuff", "div.summary", "section.summary"
        ])
        // AO3 stamps the canonical work URL into its own downloads; recovering it
        // is what lets a converted file still resolve to an AO3 work id and get
        // its tags refreshed from the live page later.
        let sourceURL = EPUBMetadata.canonicalAO3WorkURL(in: html(of: document)) ?? ""

        return EPUBBuilder.Metadata(
            title: cleanedTitle(title, fallback: fallbackTitle),
            author: author,
            summary: summary,
            language: language(of: document),
            sourceURL: sourceURL,
            subjects: subjects(in: document)
        )
    }

    /// AO3 and FanFicFare both title their pages "<work> - <author> - <fandom>
    /// [Archive of Our Own]"-ish. Strip the archive suffix but keep the rest,
    /// since guessing where the author's name starts is how you lose half a title.
    private static func cleanedTitle(_ raw: String, fallback: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" [Archive of Our Own]", " | Archive of Our Own", " | FanFiction"] {
            if title.hasSuffix(suffix) { title = String(title.dropLast(suffix.count)) }
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallback : title
    }

    private static func language(of document: Document) -> String {
        if let lang = try? document.select("html").first()?.attr("lang"),
           !lang.isEmpty {
            return lang
        }
        return "en"
    }

    /// Tag names from AO3's metadata block, as flat `dc:subject` entries. The
    /// importer's existing scanner re-splits them into fandoms/relationships/etc.
    /// where it can, and an AO3 refresh replaces them outright when the work has
    /// a resolvable id — so best-effort here is the right level of effort.
    private static func subjects(in document: Document) -> [String] {
        guard let tags = try? document.select("dd.tags a, dd a.tag, .tags a.tag").array() else {
            return []
        }
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let text = ((try? tag.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 100, seen.insert(text.lowercased()).inserted else { continue }
            result.append(text)
        }
        return result
    }

    // MARK: - Chapters

    /// Picks a chapter strategy, most specific first. Each returns nil when the
    /// page is not that shape, so the chain degrades to "one chapter" rather than
    /// to a failure — a single-chapter work is still a readable import.
    private static func readChapters(_ document: Document, workTitle: String) throws -> [EPUBBuilder.Chapter] {
        if let chapters = try ao3Chapters(document) { return chapters }
        if let chapters = try fanfictionNetChapter(document, workTitle: workTitle) { return chapters }
        if let chapters = try headingChapters(document, workTitle: workTitle) { return chapters }
        return try wholeBodyChapter(document, workTitle: workTitle)
    }

    /// AO3's HTML download: `#chapters > div.chapter`, each with its own heading.
    private static func ao3Chapters(_ document: Document) throws -> [EPUBBuilder.Chapter]? {
        let divisions = try document.select("#chapters div.chapter").array()
        guard let first = divisions.first else { return nil }
        let firstIsEmpty = ((try? first.text()) ?? "").isEmpty
        guard divisions.count > 1 || !firstIsEmpty else { return nil }
        var chapters: [EPUBBuilder.Chapter] = []
        for (index, division) in divisions.enumerated() {
            let heading = firstText(division, ["h2.heading", "h2", "h3.title", "h3"])
            let body = try HTMLWorkSanitizer.fragment(of: division)
            guard !body.isEmpty else { continue }
            chapters.append(.init(
                title: heading.isEmpty ? "Chapter \(index + 1)" : heading,
                bodyXHTML: body
            ))
        }
        return chapters.isEmpty ? nil : chapters
    }

    /// A saved fanfiction.net page: the story text lives in `#storytext`, one
    /// chapter per saved page, so this yields exactly one chapter.
    private static func fanfictionNetChapter(
        _ document: Document,
        workTitle: String
    ) throws -> [EPUBBuilder.Chapter]? {
        guard let storyText = try document.select("#storytext, #storycontent").first() else { return nil }
        let body = try HTMLWorkSanitizer.fragment(of: storyText)
        guard !body.isEmpty else { return nil }
        // FFN's chapter picker is a <select>; its selected option names the chapter.
        let selected = firstText(document, ["#chap_select option[selected]"])
        return [.init(title: selected.isEmpty ? workTitle : selected, bodyXHTML: body)]
    }

    /// Generic split for pages that are one long document with headings — a
    /// pasted-together Google Doc, a manual "all chapters" save. Only used when
    /// there are at least two headings, since one heading is just a title.
    private static func headingChapters(
        _ document: Document,
        workTitle: String
    ) throws -> [EPUBBuilder.Chapter]? {
        guard let body = document.body() else { return nil }
        let headings = try body.select("h1, h2").array()
        guard headings.count >= 2 else { return nil }

        var chapters: [EPUBBuilder.Chapter] = []
        for (index, heading) in headings.enumerated() {
            let title = ((try? heading.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var siblings: [Element] = []
            var cursor = try heading.nextElementSibling()
            while let element = cursor, !headings.contains(element) {
                siblings.append(element)
                cursor = try element.nextElementSibling()
            }
            let fragment = try HTMLWorkSanitizer.fragment(ofAll: siblings)
            guard !fragment.isEmpty else { continue }
            chapters.append(.init(
                title: title.isEmpty ? "Chapter \(index + 1)" : title,
                bodyXHTML: fragment
            ))
        }
        return chapters.count >= 2 ? chapters : nil
    }

    private static func wholeBodyChapter(
        _ document: Document,
        workTitle: String
    ) throws -> [EPUBBuilder.Chapter] {
        guard let body = document.body() else { throw EPUBBuilder.BuildError.noChapters }
        let fragment = try HTMLWorkSanitizer.fragment(of: body)
        guard !fragment.isEmpty else { throw EPUBBuilder.BuildError.noChapters }
        return [.init(title: workTitle.isEmpty ? "Chapter 1" : workTitle, bodyXHTML: fragment)]
    }

    // MARK: - Helpers

    private static func firstText(_ element: Element, _ selectors: [String]) -> String {
        for selector in selectors {
            if let value = try? element.select(selector).first()?.text()
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty {
                return value
            }
        }
        return ""
    }

    /// The document's own markup, for regex-style scans that want the raw text
    /// (the AO3 URL sniff). Falls back to the visible text so a serialization
    /// failure cannot lose the source URL.
    private static func html(of document: Document) -> String {
        if let markup = try? document.html() { return markup }
        return (try? document.text()) ?? ""
    }
}
