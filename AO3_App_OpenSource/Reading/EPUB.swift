import Foundation
import Compression

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

// MARK: - Minimal ZIP reader

/// A single entry in a ZIP archive's central directory.
private struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

/// A tiny, dependency-free ZIP reader good enough for EPUB files
/// (stored or DEFLATE-compressed entries, no ZIP64).
struct MiniZip {
    private let data: Data
    private let entries: [ZipEntry]

    init?(data: Data) {
        self.data = data
        guard let eocd = MiniZip.findEOCD(in: data) else { return nil }
        let count = Int(data.u16(eocd + 10))
        var offset = Int(data.u32(eocd + 16))
        var parsed: [ZipEntry] = []
        for _ in 0..<count {
            guard offset + 46 <= data.count, data.u32(offset) == 0x0201_4b50 else { break }
            let method = data.u16(offset + 10)
            let compressedSize = Int(data.u32(offset + 20))
            let uncompressedSize = Int(data.u32(offset + 24))
            let nameLen = Int(data.u16(offset + 28))
            let extraLen = Int(data.u16(offset + 30))
            let commentLen = Int(data.u16(offset + 32))
            let localOffset = Int(data.u32(offset + 42))
            let nameStart = offset + 46
            let name = String(
                data: data.subdata(in: nameStart..<(nameStart + nameLen)),
                encoding: .utf8
            ) ?? ""
            parsed.append(ZipEntry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
            offset = nameStart + nameLen + extraLen + commentLen
        }
        self.entries = parsed
        if parsed.isEmpty { return nil }
    }

    /// All entry names in the archive.
    var names: [String] { entries.map(\.name) }

    /// Extracts a single entry's bytes by exact name.
    func data(named name: String) -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else { return nil }
        return extract(entry)
    }

    /// Unzips every file entry into `directory`, preserving relative paths.
    func unzip(to directory: URL) throws {
        let fm = FileManager.default
        for entry in entries where !entry.name.hasSuffix("/") {
            guard let bytes = extract(entry) else { continue }
            let dest = directory.appendingPathComponent(entry.name)
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try bytes.write(to: dest)
        }
    }

    private func extract(_ entry: ZipEntry) -> Data? {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count, data.u32(base) == 0x0403_4b50 else { return nil }
        let nameLen = Int(data.u16(base + 26))
        let extraLen = Int(data.u16(base + 28))
        let start = base + 30 + nameLen + extraLen
        let end = start + entry.compressedSize
        guard end <= data.count else { return nil }
        let payload = data.subdata(in: start..<end)
        if entry.method == 0 { return payload }            // stored
        return MiniZip.inflate(payload, expectedSize: entry.uncompressedSize)
    }

    /// Raw DEFLATE inflation via the Compression framework.
    private static func inflate(_ input: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            input.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        if written != expectedSize { output.removeSubrange(written..<output.count) }
        return output
    }

    /// Locates the End Of Central Directory record by scanning backwards.
    private static func findEOCD(in data: Data) -> Int? {
        let sig: UInt32 = 0x0605_4b50
        guard data.count >= 22 else { return nil }
        var i = data.count - 22
        let lowerBound = max(0, data.count - 22 - 65_536)
        while i >= lowerBound {
            if data.u32(i) == sig { return i }
            i -= 1
        }
        return nil
    }
}

private extension Data {
    /// Little-endian unsigned 16-bit read at an absolute index.
    func u16(_ index: Int) -> UInt16 {
        UInt16(self[index]) | (UInt16(self[index + 1]) << 8)
    }

    /// Little-endian unsigned 32-bit read at an absolute index.
    func u32(_ index: Int) -> UInt32 {
        UInt32(self[index]) | (UInt32(self[index + 1]) << 8)
            | (UInt32(self[index + 2]) << 16) | (UInt32(self[index + 3]) << 24)
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

/// Parses an OPF package document: Dublin Core metadata + manifest + spine.
private final class OPFParser: NSObject, XMLParserDelegate {
    var title = ""
    var author = ""
    var summary = ""
    var subjects: [String] = []
    var language = ""
    var seriesTitle = ""
    var seriesIndex: Int?
    var manifest: [String: String] = [:]        // item id -> href
    var manifestMedia: [String: String] = [:]   // item id -> media-type
    var manifestProps: [String: String] = [:]   // item id -> properties
    var spine: [String] = []                     // itemref idref order
    var tocID: String?                           // <spine toc="..."> (NCX id)

    private var currentElement = ""
    private var buffer = ""

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        let name = elementName.contains(":")
            ? String(elementName.split(separator: ":").last!)
            : elementName
        currentElement = name
        buffer = ""

        switch name {
        case "item":
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = href
                manifestMedia[id] = attributes["media-type"]
                manifestProps[id] = attributes["properties"]
            }
        case "itemref":
            if let idref = attributes["idref"] { spine.append(idref) }
        case "spine":
            if let toc = attributes["toc"] { tocID = toc }
        case "meta":
            // calibre encodes series via <meta name="calibre:series" content="…">.
            switch attributes["name"] {
            case "calibre:series": seriesTitle = attributes["content"] ?? ""
            case "calibre:series_index":
                if let content = attributes["content"], let value = Double(content) {
                    seriesIndex = Int(value)   // calibre writes "1" or "1.0"
                }
            default: break
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.contains(":")
            ? String(elementName.split(separator: ":").last!)
            : elementName
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "title" where title.isEmpty:
            title = value
        case "creator" where author.isEmpty:
            author = value
        case "description" where summary.isEmpty:
            summary = value
        case "subject":
            if !value.isEmpty { subjects.append(value) }
        case "language" where language.isEmpty:
            language = value
        default:
            break
        }
        buffer = ""
    }
}

/// Local name of an element, ignoring any namespace prefix.
private func localName(_ name: String) -> String {
    name.contains(":") ? String(name.split(separator: ":").last!) : name
}

extension String {
    /// Resolves HTML/XML character references (named and numeric) one level.
    /// Used to undo double-encoding left behind after XML parsing.
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&nbsp;": "\u{00a0}",
        ]
        var result = ""
        var rest = Substring(self)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[rest.startIndex..<amp]
            let tail = rest[amp...]
            guard let semi = tail.firstIndex(of: ";"),
                  tail.distance(from: tail.startIndex, to: semi) <= 10 else {
                result.append("&")
                rest = rest[tail.index(after: tail.startIndex)...]
                continue
            }
            let entity = String(tail[tail.startIndex...semi])
            if let replacement = named[entity] {
                result += replacement
            } else if entity.hasPrefix("&#x") || entity.hasPrefix("&#X"),
                      let code = UInt32(entity.dropFirst(3).dropLast(), radix: 16),
                      let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else if entity.hasPrefix("&#"),
                      let code = UInt32(entity.dropFirst(2).dropLast()),
                      let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else {
                result += entity   // unknown entity: leave as-is
            }
            rest = rest[tail.index(after: semi)...]
        }
        result += rest
        return result
    }
}

/// Parses an EPUB2 NCX document into (title, src) pairs in document order.
private final class NCXParser: NSObject, XMLParserDelegate {
    var entries: [(title: String, src: String)] = []

    private var inText = false
    private var buffer = ""
    private var pendingTitle = ""

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        switch localName(elementName) {
        case "text":
            inText = true
            buffer = ""
        case "content":
            if let src = attributes["src"] {
                entries.append((pendingTitle.trimmingCharacters(in: .whitespacesAndNewlines), src))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { buffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if localName(elementName) == "text" {
            inText = false
            pendingTitle = buffer
        }
    }
}

/// Parses an EPUB3 navigation document's `toc` nav into (title, src) pairs.
private final class NavTOCParser: NSObject, XMLParserDelegate {
    var entries: [(title: String, src: String)] = []

    private var inToc = false
    private var inAnchor = false
    private var href = ""
    private var buffer = ""

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        switch localName(elementName) {
        case "nav":
            let type = attributes["epub:type"] ?? attributes["type"] ?? ""
            let navID = attributes["id"] ?? ""
            if type.contains("toc") || navID == "toc" { inToc = true }
        case "a" where inToc:
            inAnchor = true
            href = attributes["href"] ?? ""
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inAnchor { buffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localName(elementName) {
        case "a" where inAnchor:
            if !href.isEmpty {
                entries.append((buffer.trimmingCharacters(in: .whitespacesAndNewlines), href))
            }
            inAnchor = false
        case "nav" where inToc:
            inToc = false
        default:
            break
        }
    }
}
