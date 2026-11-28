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
        try sanitizedFragment(rawHTML: markingAuthorNotes(in: element).html())
    }

    /// Selectors AO3 uses for author's notes. Where markup exists there is nothing to
    /// guess — a `div.notes` *is* a note, whatever it says — so these are handled
    /// structurally and never reach `AuthorNoteDetector`'s text heuristics.
    ///
    /// `.summary` is deliberately absent: a work summary is metadata the importer
    /// already reads into `SavedWork.summary`, not apparatus inside the prose.
    private static let authorNoteSelectors = [
        "div.notes", "div.end.notes", ".preface .notes", ".chapter .notes", "#notes"
    ]

    /// Rewrites AO3's note containers into the same `<aside class="author-note">` the
    /// text-based detector produces, so a reader has one thing to style regardless of
    /// which door the work came in through.
    ///
    /// Works on a copy: the caller's element belongs to the document the converter is
    /// still reading metadata from, and mutating it in place would change what later
    /// selectors see.
    private static func markingAuthorNotes(in element: Element) throws -> Element {
        guard let copy = element.copy() as? Element else { return element }
        for selector in authorNoteSelectors {
            for note in try copy.select(selector).array() {
                // `aside` is not in the allowlist, so the class is what survives the
                // clean; `sanitizedFragment` re-wraps it below.
                try note.tagName("aside")
                try note.attr("class", "author-note")
            }
        }
        return copy
    }

    /// Serializes several sibling elements as one sanitized XHTML fragment.
    static func fragment(ofAll elements: [Element]) throws -> String {
        let raw = try elements.map { try $0.outerHtml() }.joined(separator: "\n")
        return try sanitizedFragment(rawHTML: raw)
    }

    /// Wraps plain text (already XML-escaped by the caller's paragraph builder)
    /// so plain-text conversion and HTML conversion share one output path.
    ///
    /// Blocks that `AuthorNoteDetector` recognises as author's notes are wrapped in
    /// `<aside epub:type="note" class="author-note">` instead of `<p>`, which is what
    /// lets a reader style, dim, or hide them without re-parsing the prose. Adjacent
    /// notes share one `<aside>`, since a three-paragraph preamble is one note.
    static func paragraphs(from blocks: [String]) -> String {
        let noteIndices = AuthorNoteDetector.noteIndices(in: blocks)
        var lines: [String] = []
        var index = 0
        while index < blocks.count {
            guard noteIndices.contains(index) else {
                lines.append("    <p>\(EPUBBuilder.escaped(blocks[index]))</p>")
                index += 1
                continue
            }
            var run: [String] = []
            while index < blocks.count, noteIndices.contains(index) {
                run.append(blocks[index])
                index += 1
            }
            lines.append("    <aside epub:type=\"note\" class=\"author-note\">")
            lines.append(contentsOf: run.map { "      <p>\(EPUBBuilder.escaped($0))</p>" })
            lines.append("    </aside>")
        }
        return lines.joined(separator: "\n")
    }

    /// Same paragraph and author's-note wrapping as `paragraphs(from:)`, while emitting
    /// `<em>` and `<strong>` for inline ranges on PDF blocks (headings and scene breaks
    /// stay plain).
    static func styledParagraphs(from blocks: [PDFStyledBlock]) -> String {
        let noteIndices = AuthorNoteDetector.noteIndices(in: blocks.map(\.text))
        var lines: [String] = []
        var index = 0
        while index < blocks.count {
            guard noteIndices.contains(index) else {
                lines.append("    <p>\(inlineXHTML(for: blocks[index]))</p>")
                index += 1
                continue
            }
            var run: [PDFStyledBlock] = []
            while index < blocks.count, noteIndices.contains(index) {
                run.append(blocks[index])
                index += 1
            }
            lines.append("    <aside epub:type=\"note\" class=\"author-note\">")
            lines.append(contentsOf: run.map { "      <p>\(inlineXHTML(for: $0))</p>" })
            lines.append("    </aside>")
        }
        return lines.joined(separator: "\n")
    }

    /// Renders one styled block's inline XHTML: escapes each text slice first, then wraps
    /// italic/bold runs with canonical nesting (`<strong><em>…</em></strong>` when both apply).
    static func inlineXHTML(for block: PDFStyledBlock) -> String {
        let text = block.text
        guard !block.italicRanges.isEmpty || !block.boldRanges.isEmpty,
              !PDFParagraphRepair.isSeparator(text),
              !PlainTextWorkConverter.isChapterHeading(text)
        else {
            return EPUBBuilder.escaped(text)
        }

        let units = Array(text.utf16)
        let total = units.count
        let italic = clampedRanges(block.italicRanges, limit: total)
        let bold = clampedRanges(block.boldRanges, limit: total)
        guard !italic.isEmpty || !bold.isEmpty else {
            return EPUBBuilder.escaped(text)
        }

        let boundaries = styleBoundaries(italic: italic, bold: bold, total: total)
        var output = ""
        output.reserveCapacity(text.count + (italic.count + bold.count) * 16)
        var boldOpen = false
        var italicOpen = false

        for (start, end) in zip(boundaries, boundaries.dropFirst()) where start < end {
            let wantBold = bold.contains { $0.location <= start && $0.location + $0.length >= end }
            let wantItalic = italic.contains { $0.location <= start && $0.location + $0.length >= end }
            transitionInlineTags(
                into: &output,
                boldOpen: &boldOpen,
                italicOpen: &italicOpen,
                wantBold: wantBold,
                wantItalic: wantItalic
            )
            let slice = String(decoding: units[start..<end], as: UTF16.self)
            output += EPUBBuilder.escaped(slice)
        }

        if italicOpen { output += "</em>" }
        if boldOpen { output += "</strong>" }
        return output
    }

    private static func clampedRanges(_ ranges: [NSRange], limit: Int) -> [NSRange] {
        ranges.compactMap { range in
            guard range.length > 0, range.location < limit else { return nil }
            let start = max(0, range.location)
            let end = min(limit, range.location + range.length)
            return end > start ? NSRange(location: start, length: end - start) : nil
        }
    }

    private static func styleBoundaries(italic: [NSRange], bold: [NSRange], total: Int) -> [Int] {
        var points: Set<Int> = [0, total]
        for range in italic {
            points.insert(range.location)
            points.insert(range.location + range.length)
        }
        for range in bold {
            points.insert(range.location)
            points.insert(range.location + range.length)
        }
        return points.sorted()
    }

    private static func transitionInlineTags(
        into output: inout String,
        boldOpen: inout Bool,
        italicOpen: inout Bool,
        wantBold: Bool,
        wantItalic: Bool
    ) {
        if boldOpen != wantBold {
            if italicOpen {
                output += "</em>"
                italicOpen = false
            }
            if boldOpen {
                output += "</strong>"
                boldOpen = false
            }
            if wantBold {
                output += "<strong>"
                boldOpen = true
            }
        }
        if italicOpen != wantItalic {
            if italicOpen {
                output += "</em>"
                italicOpen = false
            }
            if wantItalic {
                output += "<em>"
                italicOpen = true
            }
        }
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
            // `aside` is how both note paths mark apparatus; without it here the
            // Cleaner unwraps the element and the note becomes indistinguishable
            // from prose.
            .addTags("aside")
            .addAttributes("aside", "class")
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
