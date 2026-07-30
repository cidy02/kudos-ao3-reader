import Foundation

/// Writes a minimal, valid EPUB 3 from chapter XHTML and work metadata.
///
/// This exists so the app can accept the formats fanfic actually circulates in —
/// a saved HTML page, a `.txt`, a zip of chapter files — without teaching any
/// downstream system a second format. Everything past the import door
/// (`Storage.safeEPUBAssetIdentifier`, both readers, preservation, folder sync,
/// `.kudosbackup`) is EPUB-only *by contract*, so conversion happens here and
/// the rest of the app never learns the difference.
///
/// No new dependency: `MiniZip.ArchiveWriter` already emits **stored**
/// (uncompressed) entries, which is exactly what EPUB requires of its `mimetype`
/// entry and legal for every other one.
nonisolated struct EPUBBuilder {
    /// One spine item. `bodyXHTML` is an XHTML *fragment* (no `<html>`/`<body>`
    /// wrapper) and must already be sanitized — see `HTMLWorkSanitizer`. It is
    /// interpolated verbatim, so anything unsafe or non-well-formed that reaches
    /// here ends up in the file.
    struct Chapter {
        let title: String
        let bodyXHTML: String
    }

    struct Metadata {
        var title: String
        var author: String
        var summary: String
        var language: String
        /// Becomes `dc:source`. The AO3/FFN story URL when known, else empty —
        /// `AO3EPUBMetadataScanner` and `WorkTags.ao3WorkID(from:)` both read it
        /// back out on import, which is how a converted file can still resolve to
        /// an AO3 identity.
        var sourceURL: String
        /// `dc:subject` entries. Round-trip as `SavedWork.workTags`.
        var subjects: [String]
        /// `dc:identifier`. Injectable so tests can pin it and so a re-conversion
        /// of the same source file produces a byte-identical archive.
        var identifier: String

        init(
            title: String,
            author: String = "",
            summary: String = "",
            language: String = "en",
            sourceURL: String = "",
            subjects: [String] = [],
            identifier: String = UUID().uuidString
        ) {
            self.title = title
            self.author = author
            self.summary = summary
            self.language = language
            self.sourceURL = sourceURL
            self.subjects = subjects
            self.identifier = identifier
        }
    }

    enum BuildError: LocalizedError, Equatable {
        case noChapters

        var errorDescription: String? {
            switch self {
            case .noChapters:
                "This file has no readable text to import."
            }
        }
    }

    /// Path of the OPF inside the archive. `META-INF/container.xml` points here,
    /// and every manifest href is relative to its directory.
    private static let opfPath = "OEBPS/content.opf"
    private static let navPath = "OEBPS/nav.xhtml"
    private static let stylesheetPath = "OEBPS/style.css"

    /// Minimal stylesheet. Deliberately says nothing about fonts, sizes or colours
    /// for body text — the reader owns typography, and a converted work must not
    /// fight the app's themes or Dynamic Type.
    ///
    /// It exists only to make an author's note *look* like apparatus rather than
    /// prose. `currentColor` and `em` units keep it inside whatever the reader has
    /// chosen, and the class name is stable so a reader-injected rule can dim or hide
    /// notes later without the EPUB changing.
    private static let stylesheet = """
    .author-note {
      font-size: 0.9em;
      font-style: italic;
      border-inline-start: 3px solid currentColor;
      padding-inline-start: 0.75em;
      margin: 1em 0;
      opacity: 0.75;
    }
    .author-note p { margin: 0.4em 0; }
    """

    /// Builds the complete `.epub` archive bytes.
    ///
    /// `modified` becomes EPUB 3's required `dcterms:modified`; it is a parameter
    /// rather than `Date()` so callers that want reproducible output can pin it.
    static func archive(
        metadata: Metadata,
        chapters: [Chapter],
        modified: Date = Date()
    ) throws -> Data {
        guard !chapters.isEmpty else { throw BuildError.noChapters }

        let names = chapters.indices.map { "chapter-\($0 + 1).xhtml" }

        // Entry order matters: `mimetype` must come first. MiniZip stores every
        // entry, so it also satisfies EPUB's "uncompressed, unencrypted" rule for
        // that entry without a special case here.
        var entries: [(name: String, data: Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(containerXML().utf8)),
            (opfPath, Data(packageDocument(metadata, names: names, chapters: chapters, modified: modified).utf8)),
            (navPath, Data(navigationDocument(metadata, names: names, chapters: chapters).utf8)),
            (stylesheetPath, Data(stylesheet.utf8))
        ]
        for (index, chapter) in chapters.enumerated() {
            entries.append((
                "OEBPS/\(names[index])",
                Data(chapterDocument(chapter, language: metadata.language).utf8)
            ))
        }
        return try MiniZip.archiveData(entries)
    }

    // MARK: - Documents

    private static func containerXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
    }

    /// The OPF. Parsed strictly as XML by `OPFParser` (via `XMLParser`) and by
    /// Readium's `EPUBParser`, so every interpolated value is escaped.
    private static func packageDocument(
        _ metadata: Metadata,
        names: [String],
        chapters: [Chapter],
        modified: Date
    ) -> String {
        let manifestItems = names.enumerated().map { index, name in
            "    <item id=\"chapter-\(index + 1)\" href=\"\(name)\" media-type=\"application/xhtml+xml\"/>"
        }
        let spineItems = names.indices.map { "    <itemref idref=\"chapter-\($0 + 1)\"/>" }
        let subjects = metadata.subjects
            .map { "    <dc:subject>\(escaped($0))</dc:subject>" }

        var metadataLines = [
            "    <dc:identifier id=\"bookid\">\(escaped(metadata.identifier))</dc:identifier>",
            "    <dc:title>\(escaped(metadata.title))</dc:title>",
            "    <dc:language>\(escaped(metadata.language.isEmpty ? "en" : metadata.language))</dc:language>",
            "    <meta property=\"dcterms:modified\">\(Self.timestamp(modified))</meta>"
        ]
        if !metadata.author.isEmpty {
            metadataLines.append("    <dc:creator>\(escaped(metadata.author))</dc:creator>")
        }
        if !metadata.summary.isEmpty {
            metadataLines.append("    <dc:description>\(escaped(metadata.summary))</dc:description>")
        }
        if !metadata.sourceURL.isEmpty {
            metadataLines.append("    <dc:source>\(escaped(metadata.sourceURL))</dc:source>")
        }
        metadataLines.append(contentsOf: subjects)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        \(metadataLines.joined(separator: "\n"))
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="style" href="style.css" media-type="text/css"/>
        \(manifestItems.joined(separator: "\n"))
          </manifest>
          <spine>
        \(spineItems.joined(separator: "\n"))
          </spine>
        </package>
        """
    }

    /// EPUB 3 navigation document. `EPUBDocument.tableOfContents` prefers the nav
    /// over an NCX, and Readium reads the same file, so one TOC serves both
    /// readers and no NCX is emitted.
    private static func navigationDocument(
        _ metadata: Metadata,
        names: [String],
        chapters: [Chapter]
    ) -> String {
        let items = zip(names, chapters).map { name, chapter in
            "        <li><a href=\"\(name)\">\(escaped(chapter.title))</a></li>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"\
         xml:lang="\(escaped(metadata.language.isEmpty ? "en" : metadata.language))">
          <head>
            <meta charset="utf-8"/>
            <title>\(escaped(metadata.title))</title>
          </head>
          <body>
            <nav epub:type="toc" id="toc">
              <h1>Contents</h1>
              <ol>
        \(items.joined(separator: "\n"))
              </ol>
            </nav>
          </body>
        </html>
        """
    }

    private static func chapterDocument(_ chapter: Chapter, language: String) -> String {
        let lang = escaped(language.isEmpty ? "en" : language)
        // The `epub:` prefix must be declared here or a chapter carrying an
        // `epub:type="note"` aside is not well-formed XHTML and strict parsers reject
        // the whole file.
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"\
         xml:lang="\(lang)">
          <head>
            <meta charset="utf-8"/>
            <title>\(escaped(chapter.title))</title>
            <link rel="stylesheet" type="text/css" href="style.css"/>
          </head>
          <body>
            <h1>\(escaped(chapter.title))</h1>
        \(chapter.bodyXHTML)
          </body>
        </html>
        """
    }

    // MARK: - Helpers

    /// XML text escaping. Deliberately escapes quotes too, so the same helper is
    /// safe in attribute position (`href`, `xml:lang`) as well as element text.
    static func escaped(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }

    /// `dcterms:modified` must be a UTC timestamp of exactly this shape; EPUB 3
    /// rejects fractional seconds and offsets other than `Z`.
    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }
}
