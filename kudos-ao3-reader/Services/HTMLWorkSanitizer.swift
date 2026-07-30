import Foundation
import SwiftSoup

/// Strips stranger-authored HTML down to an allowlist and re-serializes it as
/// XHTML, ready to embed in a synthesized EPUB.
///
/// Why this is not optional: an imported community copy is markup written by
/// someone the user has never met, and it ends up rendered by WKWebView (the
/// macOS reader) and by Readium's WebView-backed navigator on iOS. So the file
/// is treated as hostile input — allowlist, not denylist, because a denylist is
/// a list of the attacks you happened to think of.
///
/// Two deliberate omissions:
///
/// - **Images are dropped entirely.** Remote `src` values would make the reader
///   phone a stranger's server on every page turn, which is both a privacy leak
///   and against `docs/AO3_NETWORKING_POLICY.md`. Inlining them is a T-153
///   question (data: URIs and `_files` sidecar folders), not a silent default.
/// - **No `style` attributes or stylesheets.** The reader owns typography; a
///   community copy's fixed colors and fonts would fight every app theme and
///   ignore Dynamic Type.
nonisolated enum HTMLWorkSanitizer {
    /// Serializes one element's *children* as a sanitized XHTML fragment.
    static func fragment(of element: Element) throws -> String {
        try sanitizedFragment(rawHTML: element.html())
    }

    /// Serializes several sibling elements as one sanitized XHTML fragment.
    static func fragment(ofAll elements: [Element]) throws -> String {
        let raw = try elements.map { try $0.outerHtml() }.joined(separator: "\n")
        return try sanitizedFragment(rawHTML: raw)
    }

    /// Wraps plain text (already XML-escaped by the caller's paragraph builder)
    /// so plain-text conversion and HTML conversion share one output path.
    static func paragraphs(from blocks: [String]) -> String {
        blocks
            .map { "    <p>\(EPUBBuilder.escaped($0))</p>" }
            .joined(separator: "\n")
    }

    // MARK: - Internals

    private static func sanitizedFragment(rawHTML: String) throws -> String {
        let dirty = try SwiftSoup.parseBodyFragment(rawHTML)
        let clean = try Cleaner(headWhitelist: nil, bodyWhitelist: allowlist()).clean(dirty)

        // `.xml` syntax is what makes the output XHTML rather than HTML: void
        // elements come out as `<br />`, so the chapter file stays well-formed for
        // strict EPUB parsers.
        clean.outputSettings()
            .syntax(syntax: .xml)
            .escapeMode(.base)
            .prettyPrint(pretty: false)

        guard let body = clean.body() else { return "" }
        let fragment = try body.html().trimmingCharacters(in: .whitespacesAndNewlines)
        // A page whose entire content was disallowed markup (a JS-rendered
        // single-page app, say) sanitizes to nothing; the caller treats that as
        // "no readable text" rather than importing a blank chapter.
        return textLength(of: body) == 0 ? "" : fragment
    }

    /// SwiftSoup's `relaxed()` minus images, plus the class attribute on the few
    /// containers AO3's metadata block uses.
    ///
    /// `class` is kept because the importer's existing `AO3EPUBMetadataScanner`
    /// reads AO3's `dd.tags` / `a.tag` structure to recover fandoms, warnings and
    /// the rating. Losing it would not break the import — the scanner falls back
    /// to walking `dt`/`dd` label pairs — but it would silently downgrade the
    /// metadata of exactly the files this feature exists for. Class names carry no
    /// script, so this costs nothing.
    private static func allowlist() throws -> Whitelist {
        try Whitelist.relaxed()
            .removeTags("img")
            .addAttributes("dd", "class")
            .addAttributes("dl", "class")
            .addAttributes("dt", "class")
            .addAttributes("div", "class")
            .addAttributes("p", "class")
            .addAttributes("span", "class")
            .addAttributes("a", "class", "rel")
            .addAttributes("blockquote", "class")
            .addAttributes("h1", "class")
            .addAttributes("h2", "class")
            .addAttributes("h3", "class")
    }

    private static func textLength(of body: Element) -> Int {
        let text = (try? body.text()) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
}
