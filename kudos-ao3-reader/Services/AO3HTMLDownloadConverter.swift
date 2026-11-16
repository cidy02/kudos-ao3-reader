import Foundation
import SwiftSoup

/// AO3's own "Download → HTML" file, rebuilt as the EPUB AO3 would have served.
///
/// AO3 makes its EPUB by running calibre over this very HTML, so the two carry the
/// same content; what calibre adds is the split into sections, the OPF metadata and
/// the embedded images, and those are what this reproduces. It is what lets a
/// download keep working, unchanged for everything past `AO3Client.downloadEPUB`,
/// while AO3 offers HTML only (as it did after the November 2026 outage).
///
/// Ground truth is otwarchive at 452391b648f2 (2026-11-01):
/// `app/views/downloads/{show,_download_preface,_download_chapter,_download_afterword}.html.erb`
/// for the markup, `config/locales/views/en.yml` for the labels, and
/// `DownloadWriter#get_calibre_command` for the split (its `--chapter` XPaths) and
/// the metadata it passes.
nonisolated enum AO3HTMLDownloadConverter {
    private static let maxImages = 60
    private static let maxImageBytes = 8 * 1024 * 1024
    private static let maxTotalImageBytes = 40 * 1024 * 1024
    private static let baseURI = "https://archiveofourown.org/"

    /// AO3's `barebones` layout rules that are about structure rather than typography.
    private static let stylesheet = """
    p.message, .meta h1, .meta h2, .meta .byline { text-align: center; }
    .meta dl.tags { border: 1px solid; padding: 1em; }
    .meta .endnote-link { font-size: 0.8em; }
    img { max-width: 100%; height: auto; }
    """

    // MARK: - Reading

    /// The work in `document`, split the way calibre splits it: a Preface, one
    /// section per chapter heading, an Afterword. Nil when the document is not an
    /// AO3 HTML download — AO3 answers a download it cannot serve with an ordinary
    /// page, and that must not become a book.
    ///
    /// `imagePaths` maps an image's absolute URL to its path inside the EPUB; an
    /// image with no entry is left out, so nothing is ever left pointing at its host.
    /// Changes `document`.
    static func read(_ document: Document, imagePaths: [String: String] = [:]) throws -> HTMLWorkConverter.Result? {
        guard let preface = try document.select("body > div#preface").first(),
              let chapters = try document.select("body > div#chapters").first()
        else { return nil }
        let metadata = try readMetadata(document, preface: preface)

        // A single-chapter work has no chapter heading: its one section is named
        // for the work.
        var sections: [(title: String, elements: [Element])] = [("Preface", [preface])]
        for child in chapters.children().array() {
            let heading = child.hasClass("meta") && child.hasClass("group")
                ? child.children().array().first { $0.tagName() == "h2" && $0.hasClass("heading") }
                : nil
            if heading != nil || sections.count == 1 {
                let title = try trimmed(heading?.text())
                sections.append((title.isEmpty ? metadata.title : title, []))
            }
            sections[sections.count - 1].elements.append(child)
        }
        guard sections.count > 1 else { return nil }
        if let afterword = try document.select("body > div#afterword").first() {
            sections.append(("Afterword", [afterword]))
        }

        // Hidden in AO3's file; they exist only to give calibre its section names.
        try document.select(".toc-heading").remove()
        try relink(sections.map(\.elements), imagePaths: imagePaths)
        return try HTMLWorkConverter.Result(
            metadata: metadata,
            chapters: sections.map {
                try EPUBBuilder.Chapter(
                    title: $0.title,
                    bodyXHTML: HTMLWorkSanitizer.ao3DownloadFragment(ofAll: $0.elements),
                    hasOwnHeading: true
                )
            }
        )
    }

    private static func readMetadata(_ document: Document, preface: Element) throws -> EPUBBuilder.Metadata {
        let meta = try preface.select("div.meta").first()?.children().array() ?? []
        let byline = meta.first { $0.tagName() == "div" && $0.hasClass("byline") }
        func labelled(_ label: String) throws -> Element? {
            try preface.select("dl.tags > dt").array()
                .first { try trimmed($0.text()).lowercased().hasPrefix(label) }?
                .nextElementSibling()
        }
        let stats = try labelled("stats")?.text() ?? ""
        func date(_ labels: String) -> String? {
            stats.range(of: "(?:\(labels)): \\d{4}-\\d{2}-\\d{2}", options: .regularExpression)
                .map { String(stats[$0].suffix(10)) }
        }
        let series = try labelled("series")
        let seriesText = try series?.text() ?? ""
        let languageName = try trimmed(labelled("language")?.text())
        let authors = try byline?.select("a[rel=author]").array().map { try $0.text() } ?? []
        let bylineText = try trimmed(byline?.text())
        let title = try trimmed(meta.first { $0.tagName() == "h1" }?.text())
        let sourceURL = try EPUBMetadata.canonicalAO3WorkURL(in: preface.select("p.message").outerHtml()) ?? ""
        var seen = Set<String>()

        return try EPUBBuilder.Metadata(
            title: title.isEmpty ? document.title() : title,
            author: authors.isEmpty
                ? (bylineText.hasPrefix("by ") ? String(bylineText.dropFirst(3)) : bylineText)
                : authors.joined(separator: ", "),
            summary: trimmed(
                meta.first { $0.tagName() == "p" && (try? $0.text()) == "Summary" }?
                    .nextElementSibling().flatMap { $0.tagName() == "blockquote" ? $0 : nil }?
                    .text()
            ),
            // The page's own `lang` is the site's locale, not the work's language.
            language: AO3SearchFilters.Language.allCases
                .first { $0.title.caseInsensitiveCompare(languageName) == .orderedSame }?.id ?? "en",
            sourceURL: sourceURL,
            // Tag links only: the same list also links the work's series and collections.
            subjects: preface.select("dl.tags dd a[href*=/tags/]").array()
                .map { try trimmed($0.text()) }
                .filter { !$0.isEmpty && seen.insert($0).inserted },
            // The same download always makes the same file, so two devices agree on its digest.
            identifier: sourceURL.isEmpty ? UUID().uuidString : sourceURL,
            // calibre is given the date the work was last revised.
            date: date("Updated|Completed") ?? date("Published") ?? "",
            seriesTitle: trimmed(series?.select("a[href*=/series/]").first()?.text()),
            seriesIndex: seriesText.range(of: "Part \\d+ of", options: .regularExpression)
                .flatMap { Int(seriesText[$0].filter(\.isNumber)) }
        )
    }

    /// "See the end of the work for notes" is a link to `#endnotes`, which lands in a
    /// different file once the work is split, so it has to name that file
    /// (`EPUBBuilder` calls them `chapter-<n>.xhtml`). Every other link is made
    /// absolute, as it would be in a browser.
    private static func relink(_ sections: [[Element]], imagePaths: [String: String]) throws {
        var sectionOfID: [String: Int] = [:]
        for (index, elements) in sections.enumerated() {
            for element in elements {
                for tagged in try element.select("[id]").array() where sectionOfID[tagged.id()] == nil {
                    sectionOfID[tagged.id()] = index
                }
            }
        }
        for element in sections.joined() {
            for link in try element.select("a[href]").array() {
                let href = try link.attr("href")
                if href.hasPrefix("#") {
                    if let index = sectionOfID[String(href.dropFirst())] {
                        try link.attr("href", "chapter-\(index + 1).xhtml\(href)")
                    }
                } else if let absolute = try? link.absUrl("href"), !absolute.isEmpty {
                    try link.attr("href", absolute)
                }
            }
            for image in try element.select("img").array() {
                if let path = try imagePaths[image.absUrl("src")] {
                    try image.attr("src", path)
                } else {
                    try image.remove()
                }
            }
        }
    }

    private static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Building

    /// The EPUB for an AO3 HTML download, or nil when `html` is not one.
    ///
    /// AO3's EPUB carries the work's images inside it, so this one does too:
    /// `fetchImage` returns an image's bytes or nil, and an image that cannot be
    /// fetched is left out.
    static func epub(
        fromHTML html: String,
        fetchImage: @Sendable (URL) async -> Data? = fetchRemoteImage
    ) async throws -> Data? {
        var images: [(path: String, data: Data)] = []
        var paths: [String: String] = [:]
        var total = 0
        for source in try imageSources(in: html) where images.count < maxImages && total < maxTotalImageBytes {
            guard let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased()),
                  let data = await fetchImage(url), let type = imageExtension(of: data)
            else { continue }
            let path = "images/image-\(images.count + 1).\(type)"
            images.append((path, data))
            paths[source] = path
            total += data.count
        }

        guard let result = try read(SwiftSoup.parse(html, baseURI), imagePaths: paths) else { return nil }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return try EPUBBuilder.archive(
            metadata: result.metadata,
            chapters: result.chapters,
            modified: day.date(from: result.metadata.date) ?? Date(timeIntervalSince1970: 0),
            images: images,
            extraCSS: stylesheet
        )
    }

    /// Rebuilds the HTML download at `file` as an EPUB in the downloads cache,
    /// consuming `file`. Throws `AO3Error.parse` when it is not an AO3 download.
    static func epubFile(fromHTMLFile file: URL, named name: String) async throws -> URL {
        defer { try? FileManager.default.removeItem(at: file) }
        // AO3 writes the file as UTF-8 (`DownloadWriter#generate_html_download`).
        guard let html = try String(bytes: Data(contentsOf: file), encoding: .utf8),
              let data = try await epub(fromHTML: html)
        else { throw AO3Error.parse }
        let destination = Storage.tempDownloadURL(suggestedName: name)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func imageSources(in html: String) throws -> [String] {
        var seen = Set<String>()
        return try SwiftSoup.parse(html, baseURI).select("#preface img, #chapters img, #afterword img").array()
            .compactMap { try? $0.absUrl("src") }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// By content, never by what the host says it is: only real images go in the book.
    private static func imageExtension(of data: Data) -> String? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count > 12,
           data.subdata(in: data.startIndex + 8 ..< data.startIndex + 12) == Data("WEBP".utf8) {
            return "webp"
        }
        return nil
    }

    /// Its own session: an image host is not AO3, and gets none of AO3's cookies.
    private static let imageSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    @Sendable static func fetchRemoteImage(_ url: URL) async -> Data? {
        guard let (file, response) = try? await imageSession.download(from: url) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxImageBytes
        else { return nil }
        return try? Data(contentsOf: file)
    }
}
