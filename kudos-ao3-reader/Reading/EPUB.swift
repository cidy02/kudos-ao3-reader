import Foundation

// Public API / orchestrator for reading EPUBs. The pieces it coordinates live in
// sibling files: `MiniZip` (ZIP), `OPFParser` (package), `NCXParser` /
// `NavTOCParser` (table of contents), and `EPUBUtilities` (shared helpers).

// MARK: - Errors

/// A typed failure from reading an EPUB, with a user-facing description. Replaces
/// the parser's old silent `nil` returns so callers can tell the user *why* a
/// file wouldn't open.
enum EPUBError: LocalizedError {
    /// The file's bytes couldn't be read from disk.
    case unreadableFile
    /// Not a valid ZIP container (so not an EPUB).
    case notAnEPUB
    /// `META-INF/container.xml` is missing or doesn't point at a package document.
    case missingContainer
    /// The OPF package document referenced by the container is missing.
    case missingPackage
    /// The OPF package document couldn't be parsed.
    case malformedPackage
    /// The package has no spine items — nothing readable.
    case noReadableContent
    /// The archive couldn't be unpacked to disk.
    case extractionFailed

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "This file couldn't be read."
        case .notAnEPUB: "This file isn't a valid EPUB."
        case .missingContainer: "The EPUB is missing its container file (META-INF/container.xml)."
        case .missingPackage: "The EPUB's package file (OPF) is missing."
        case .malformedPackage: "The EPUB's package file (OPF) couldn't be read."
        case .noReadableContent: "The EPUB has no readable chapters."
        case .extractionFailed: "The EPUB couldn't be unpacked."
        }
    }
}

// MARK: - EPUB parsing

/// Metadata pulled from an EPUB's OPF package document.
struct EPUBMetadata {
    var title: String
    var author: String
    var summary: String
    var subjects: [String]
    /// calibre series metadata (AO3 EPUBs set these when a work is in a series).
    var seriesTitle: String
    var seriesIndex: Int?
    /// AO3 rating, recovered from the subject list (e.g. "Mature").
    var rating: String
    /// `dc:language` code (e.g. "en"); empty when absent.
    var language: String

    /// The AO3 ratings, in the exact spelling AO3 writes into EPUB subjects.
    private static let ratings: Set<String> = [
        "General Audiences", "Teen And Up Audiences", "Mature", "Explicit", "Not Rated"
    ]

    /// Picks the rating out of an EPUB's subject list, if present.
    static func rating(in subjects: [String]) -> String {
        subjects.first { ratings.contains($0) } ?? ""
    }
}

/// A table-of-contents entry pointing at a spine index.
struct TOCEntry: Identifiable {
    let id = UUID()
    let title: String
    let spineIndex: Int
}

/// Reads structure and metadata out of an EPUB (a ZIP with an OPF manifest).
struct EPUBDocument {
    /// OPF spine in reading order, as absolute file URLs after unzipping.
    let spineURLs: [URL]
    let metadata: EPUBMetadata
    /// Table of contents, each entry mapped to a spine index.
    let chapters: [TOCEntry]

    /// Parses an already-unzipped EPUB rooted at `directory`.
    init(unzippedAt directory: URL) throws {
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerURL) else { throw EPUBError.missingContainer }
        guard let opfPath = EPUBDocument.rootfilePath(from: containerData) else { throw EPUBError.missingContainer }

        let opfURL = directory.appendingPathComponent(opfPath)
        guard let opfData = try? Data(contentsOf: opfURL) else { throw EPUBError.missingPackage }

        let parser = OPFParser()
        guard parser.parse(opfData) else { throw EPUBError.malformedPackage }

        let opfDir = opfURL.deletingLastPathComponent()
        let spineURLs = parser.spine.compactMap { id in
            parser.manifest[id].map { href in
                opfDir.appendingPathComponent(href)
            }
        }
        guard !spineURLs.isEmpty else { throw EPUBError.noReadableContent }
        self.spineURLs = spineURLs
        self.metadata = EPUBMetadata(
            title: parser.title,
            author: parser.author,
            summary: parser.summary,
            subjects: parser.subjects,
            seriesTitle: parser.seriesTitle,
            seriesIndex: parser.seriesIndex,
            rating: EPUBMetadata.rating(in: parser.subjects),
            language: parser.language
        )
        self.chapters = EPUBDocument.tableOfContents(parser: parser, opfDir: opfDir, spineCount: spineURLs.count)
    }

    /// Builds the chapter list from the EPUB3 nav document or the NCX, falling
    /// back to one generic entry per spine item.
    private static func tableOfContents(parser: OPFParser, opfDir: URL, spineCount: Int) -> [TOCEntry] {
        // Map each spine item's file name to its index.
        var keyToIndex: [String: Int] = [:]
        for (index, idref) in parser.spine.enumerated() {
            let href = parser.manifest[idref] ?? ""
            let key = fileKey(href)
            if keyToIndex[key] == nil { keyToIndex[key] = index }
        }

        // Locate the TOC source: prefer the EPUB3 nav document, else the NCX.
        var tocHref: String?
        var isNav = false
        if let navID = parser.manifestProps.first(where: { ($0.value).contains("nav") })?.key {
            tocHref = parser.manifest[navID]
            isNav = true
        } else if let ncxID = parser.tocID
            ?? parser.manifestMedia.first(where: { $0.value == "application/x-dtbncx+xml" })?.key {
            tocHref = parser.manifest[ncxID]
        }

        var pairs: [(title: String, src: String)] = []
        if let tocHref, let data = try? Data(contentsOf: opfDir.appendingPathComponent(tocHref)) {
            if isNav {
                let navParser = NavTOCParser()
                navParser.parse(data)
                pairs = navParser.entries
            } else {
                let ncxParser = NCXParser()
                ncxParser.parse(data)
                pairs = ncxParser.entries
            }
        }

        // Nav parsing can fail silently (bad XHTML, namespace issues); try NCX as fallback.
        if isNav && pairs.isEmpty {
            let ncxID = parser.tocID
                ?? parser.manifestMedia.first(where: { $0.value == "application/x-dtbncx+xml" })?.key
            if let ncxID,
               let ncxHref = parser.manifest[ncxID],
               let data = try? Data(contentsOf: opfDir.appendingPathComponent(ncxHref)) {
                let ncxParser = NCXParser()
                ncxParser.parse(data)
                pairs = ncxParser.entries
            }
        }

        var chapters: [TOCEntry] = []
        var seen = Set<Int>()
        for pair in pairs {
            guard let index = keyToIndex[fileKey(pair.src)], !seen.contains(index) else { continue }
            seen.insert(index)
            // Some EPUBs (e.g. calibre exports of AO3 works) double-encode the
            // title in the NCX, so XMLParser leaves a literal "&amp;". Decode
            // once more so "Rayanne &amp; Lizzy" renders as "Rayanne & Lizzy".
            let decoded = pair.title.decodingHTMLEntities()
            let title = decoded.isEmpty ? "Section \(index + 1)" : decoded
            chapters.append(TOCEntry(title: title, spineIndex: index))
        }

        if chapters.isEmpty {
            chapters = (0..<spineCount).map { TOCEntry(title: "Section \($0 + 1)", spineIndex: $0) }
        }
        return chapters
    }

    /// Lower-cased, fragment-stripped file name used to match TOC hrefs to spine items.
    private static func fileKey(_ href: String) -> String {
        let noFragment = href.split(separator: "#").first.map(String.init) ?? href
        let last = (noFragment as NSString).lastPathComponent
        return (last.removingPercentEncoding ?? last).lowercased()
    }

    /// Convenience: unzip an EPUB file then parse it. Throws `EPUBError` on failure.
    static func open(epubURL: URL, into directory: URL) throws -> EPUBDocument {
        guard let data = try? Data(contentsOf: epubURL) else { throw EPUBError.unreadableFile }
        guard let zip = MiniZip(data: data) else { throw EPUBError.notAnEPUB }
        do { try zip.unzip(to: directory) } catch { throw EPUBError.extractionFailed }
        return try EPUBDocument(unzippedAt: directory)
    }

    /// Reads just the metadata from an EPUB file without unzipping to disk.
    /// Throws `EPUBError` on failure.
    static func metadata(ofEPUBAt url: URL) throws -> EPUBMetadata {
        guard let data = try? Data(contentsOf: url) else { throw EPUBError.unreadableFile }
        guard let zip = MiniZip(data: data) else { throw EPUBError.notAnEPUB }
        guard let containerData = zip.data(named: "META-INF/container.xml") else { throw EPUBError.missingContainer }
        guard let opfPath = rootfilePath(from: containerData) else { throw EPUBError.missingContainer }
        guard let opfData = zip.data(named: opfPath) else { throw EPUBError.missingPackage }
        let parser = OPFParser()
        guard parser.parse(opfData) else { throw EPUBError.malformedPackage }
        return EPUBMetadata(
            title: parser.title,
            author: parser.author,
            summary: parser.summary,
            subjects: parser.subjects,
            seriesTitle: parser.seriesTitle,
            seriesIndex: parser.seriesIndex,
            rating: EPUBMetadata.rating(in: parser.subjects),
            language: parser.language
        )
    }

    /// Pulls the OPF path out of META-INF/container.xml.
    private static func rootfilePath(from containerData: Data) -> String? {
        final class ContainerDelegate: NSObject, XMLParserDelegate {
            var path: String?
            func parser(
                _ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes: [String: String]
            ) {
                if elementName == "rootfile", path == nil {
                    path = attributes["full-path"]
                }
            }
        }
        let delegate = ContainerDelegate()
        let parser = XMLParser(data: containerData)
        parser.delegate = delegate
        parser.parse()
        return delegate.path
    }
}
