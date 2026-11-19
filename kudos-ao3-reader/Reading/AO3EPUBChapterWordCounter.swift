import Foundation
import SwiftData
import SwiftSoup

/// Computes per-chapter word (or character) counts from a local EPUB without
/// hitting the network, counting chapter prose only via `AO3WordCounter`.
nonisolated enum AO3EPUBChapterWordCounter {
    struct Analysis: Equatable, Sendable {
        let chapterWordCounts: [Int]
        let wordUnit: SavedWork.WordUnit

        var chapterWordCountsJSON: String {
            guard !chapterWordCounts.isEmpty,
                  let data = try? JSONEncoder().encode(chapterWordCounts),
                  let json = String(data: data, encoding: .utf8)
            else { return "" }
            return json
        }
    }

    /// Extracts chapter-only counts from the EPUB at `epubURL`.
    static func analyze(epubURL: URL, language: String = "") throws -> Analysis {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-word-counts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let document = try EPUBDocument.open(epubURL: epubURL, into: directory)
        let sections = ReaderSectionBuilder.build(
            tocEntries: document.chapters.map {
                ReaderSectionBuilder.RawTOCEntry(title: $0.title, spineIndex: $0.spineIndex)
            },
            spineHrefs: document.spineURLs.map(\.lastPathComponent)
        )

        var counts: [Int] = []
        var totalTokens = 0
        var totalScriptChars = 0

        for section in sections where section.kind == .chapter {
            let idx = section.spineIndex
            guard document.spineURLs.indices.contains(idx),
                  document.spineIsLinear[idx]
            else { continue }
            let url = document.spineURLs[idx]
            guard let data = try? Data(contentsOf: url) else { continue }
            let xhtml = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            let proseHTML = chapterProseHTML(from: xhtml)
            let breakdown = AO3WordCounter.measure(proseHTML)
            counts.append(breakdown.total)
            totalTokens += breakdown.total
            totalScriptChars += breakdown.scriptCharacters
        }

        let effectiveLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? document.metadata.language
            : language
        let unit: SavedWork.WordUnit
        if SavedWork.wordUnit(forLanguage: effectiveLanguage) == .characters {
            unit = .characters
        } else if totalTokens > 0 && totalScriptChars * 2 >= totalTokens {
            unit = .characters
        } else {
            unit = .words
        }

        return Analysis(chapterWordCounts: counts, wordUnit: unit)
    }

    @MainActor
    static func populate(for work: SavedWork, force: Bool = false) async {
        guard work.hasEPUB,
              work.modelContext != nil,
              force || work.chapterWordCountsJSON.isEmpty
        else { return }
        let fileURL = work.fileURL
        let language = work.language
        let analysis = await Task.detached(priority: .utility) {
            try? analyze(epubURL: fileURL, language: language)
        }.value
        guard let analysis,
              work.modelContext != nil,
              force || work.chapterWordCountsJSON.isEmpty
        else { return }
        work.applyChapterWordAnalysis(analysis)
    }

    /// Strips AO3 front/back matter, headings, bylines, chapter summaries,
    /// author/chapter/end notes, and Archive comment plugs from one chapter's
    /// XHTML, leaving only story prose.
    static func chapterProseHTML(from xhtml: String) -> String {
        guard !xhtml.isEmpty else { return "" }

        if let marked = extractAO3CommentContent(from: xhtml) {
            return cleanChapterFragment(marked)
        }
        return cleanChapterFragment(xhtml, stripLeadingHeading: true)
    }

    private static let startMarker = "<!--chapter content-->"
    private static let endMarker = "<!--/chapter content-->"

    private static func extractAO3CommentContent(from xhtml: String) -> String? {
        var searchStart = xhtml.startIndex
        var chunks: [String] = []
        while let openRange = xhtml.range(of: startMarker, range: searchStart..<xhtml.endIndex),
              let closeRange = xhtml.range(of: endMarker, range: openRange.upperBound..<xhtml.endIndex) {
            chunks.append(String(xhtml[openRange.upperBound..<closeRange.lowerBound]))
            searchStart = closeRange.upperBound
        }
        guard !chunks.isEmpty else { return nil }
        return chunks.joined(separator: "\n")
    }

    private static func cleanChapterFragment(
        _ html: String,
        stripLeadingHeading: Bool = false
    ) -> String {
        guard let doc = try? SwiftSoup.parse(html) else { return html }
        let root: Element = doc.body() ?? doc

        // Remove known AO3 & converter non-prose blocks.
        let nonProseSelector = [
            "#preface", "#afterword", "[id^=endnotes]", "[id=endnotes]",
            "div.preface", "div.afterword", "div.meta", "div.endnote-link",
            "aside", ".notes", "div.notes", "div.end.notes", "#notes", ".summary",
            "h2.heading", "h2.toc-heading", "p.byline", "h1.title",
            "nav", "style", "script"
        ].joined(separator: ", ")
        try? root.select(nonProseSelector).remove()

        if stripLeadingHeading {
            removeLeadingHeadingIfPresent(in: root)
        }

        removeCalibreFlattenedApparatus(in: root)

        return (try? root.html()) ?? ""
    }

    /// Removes a leading `<h1>`/`<h2>` (used by Calibre-flattened chapters and
    /// `EPUBBuilder`) and an optional immediate `"Chapter by ..."` byline `<p>`.
    private static func removeLeadingHeadingIfPresent(in container: Element) {
        var current: Element = container
        while let first = current.children().first(),
              first.tagName().lowercased() == "div",
              current.children().count == 1,
              first.ownText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current = first
        }
        guard let first = current.children().first() else { return }
        let tag = first.tagName().lowercased()
        guard tag == "h1" || tag == "h2" else { return }
        let next = try? first.nextElementSibling()
        try? first.remove()
        if let next, next.tagName().lowercased() == "p" {
            let text = ((try? next.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased().hasPrefix("chapter by ") {
                try? next.remove()
            }
        }
    }

    private static let exactApparatusLabels: Set<String> = [
        "chapter summary", "chapter notes", "chapter end notes",
        "summary", "notes", "end notes", "endnotes"
    ]

    private static let blockquoteRequiredLabels: Set<String> = [
        "chapter summary", "chapter notes", "chapter end notes"
    ]

    private static func removeCalibreFlattenedApparatus(in root: Element) {
        guard let paragraphs = try? root.select("p").array() else { return }
        for paragraph in paragraphs {
            guard paragraph.parent() != nil else { continue }
            let rawText = ((try? paragraph.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = rawText.lowercased()
            let strippedColon = normalized.hasSuffix(":")
                ? String(normalized.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                : normalized

            if exactApparatusLabels.contains(strippedColon) {
                if let next = try? paragraph.nextElementSibling(),
                   next.tagName().lowercased() == "blockquote" {
                    try? next.remove()
                    try? paragraph.remove()
                    continue
                }
                if blockquoteRequiredLabels.contains(normalized) {
                    try? paragraph.remove()
                    continue
                }
            }

            if isAO3BoilerplateParagraph(normalized) {
                try? paragraph.remove()
            }
        }
    }

    private static func isAO3BoilerplateParagraph(_ lower: String) -> Bool {
        if (lower.hasPrefix("see the end of the chapter for")
            || lower.hasPrefix("see the end of the work for"))
            && lower.contains("note") {
            return true
        }
        if lower == "please drop by the archive and comment to let the creator know if you enjoyed their work!" {
            return true
        }
        return false
    }
}
