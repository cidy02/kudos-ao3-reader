import Foundation
import OSLog

/// Converts a user-supplied document of any supported format into EPUB bytes.
///
/// The single entry point for the "community redistributed the last known copy as
/// whatever file they had" case. Callers hand over a local file and get back
/// either an EPUB to import or a typed error naming the format, so the whole
/// import path downstream stays EPUB-only.
nonisolated enum ImportedDocumentConverter {
    enum ConversionError: LocalizedError, Equatable {
        /// A format a later task in this series will handle.
        case notYetSupported(ImportedFileFormat)
        /// Detected as text/HTML but the bytes could not be decoded at all.
        case unreadableText
        /// A zip with nothing importable inside.
        case archiveHasNoReadableFiles
        case noReadableText

        var errorDescription: String? {
            switch self {
            case let .notYetSupported(format):
                switch format {
                case .docx, .odt, .pdf, .rtf:
                    "\(format.displayName) import is coming in a later update. For now, convert it "
                        + "to EPUB (calibre, or Word's \"Save as\") and import that."
                case .mobi:
                    "Kindle files aren't supported yet. Convert it to EPUB with calibre and import that."
                case .rar, .sevenZip:
                    "\(format.displayName)s aren't supported yet. Unpack it first, then import the "
                        + "files inside."
                default:
                    "This file isn't a format Kudos can read. Try an EPUB, HTML, or text file."
                }
            case .unreadableText:
                "This file's text couldn't be decoded. It may be corrupt or in an unusual encoding."
            case .archiveHasNoReadableFiles:
                "This archive has no EPUB, HTML, or text files inside it."
            case .noReadableText:
                "This file has no readable text to import."
            }
        }
    }

    /// What conversion produced.
    enum Outcome {
        /// The file already was an EPUB — import it unchanged, no conversion.
        case alreadyEPUB
        /// Freshly built EPUB bytes, plus the format they were converted from.
        case converted(Data, from: ImportedFileFormat)
    }

    /// Reads `url` and returns EPUB bytes, or throws a message worth showing.
    ///
    /// Not `@MainActor`: unzipping, parsing and re-serializing a whole work is
    /// heavy enough that the caller must keep it off the main actor, the same way
    /// `importEPUB` already detaches its metadata read.
    static func convert(fileAt url: URL) throws -> Outcome {
        let format = ImportedFileFormat.detect(at: url)
        Log.library.info("Import sniffed \(format.rawValue, privacy: .public) for \(url.lastPathComponent, privacy: .public)")

        switch format {
        case .epub:
            return .alreadyEPUB
        case .html:
            return .converted(try convertHTML(at: url), from: .html)
        case .plainText:
            return .converted(try convertPlainText(at: url), from: .plainText)
        case .zip:
            return try convertArchive(at: url)
        case .docx, .odt, .pdf, .rtf, .mobi, .rar, .sevenZip, .unknown:
            throw ConversionError.notYetSupported(format)
        }
    }

    // MARK: - Single documents

    private static func convertHTML(at url: URL) throws -> Data {
        let html = try text(at: url)
        let result = try HTMLWorkConverter.convert(html: html, fallbackTitle: fallbackTitle(for: url))
        return try EPUBBuilder.archive(metadata: result.metadata, chapters: result.chapters)
    }

    private static func convertPlainText(at url: URL) throws -> Data {
        let raw = try text(at: url)
        let result = try PlainTextWorkConverter.convert(text: raw, fallbackTitle: fallbackTitle(for: url))
        return try EPUBBuilder.archive(metadata: result.metadata, chapters: result.chapters)
    }

    // MARK: - Archives

    /// Three shapes of zip show up in practice, in this order of preference:
    /// an EPUB nested inside (extract and import it as-is, no conversion loss);
    /// a pile of per-chapter HTML/text files (one chapter each, natural-sorted);
    /// anything else is a failure that says so.
    ///
    /// A zip that *is* an EPUB never reaches here — `ImportedFileFormat.detect`
    /// already resolves that to `.epub`.
    private static func convertArchive(at url: URL) throws -> Outcome {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let zip = try MiniZip(data: data)

        if let nested = nestedEPUB(in: zip) {
            return .converted(nested, from: .epub)
        }

        let members = readableMembers(of: zip)
        guard !members.isEmpty else { throw ConversionError.archiveHasNoReadableFiles }

        var chapters: [EPUBBuilder.Chapter] = []
        var metadata = EPUBBuilder.Metadata(title: fallbackTitle(for: url))
        for member in members {
            guard let converted = try? chaptersFromMember(member) else { continue }
            // The first member that knows the work's title and author wins; later
            // ones only fill gaps, so a stray "readme.txt" cannot rename the work.
            if metadata.author.isEmpty { metadata.author = converted.metadata.author }
            if metadata.summary.isEmpty { metadata.summary = converted.metadata.summary }
            if metadata.sourceURL.isEmpty { metadata.sourceURL = converted.metadata.sourceURL }
            if metadata.subjects.isEmpty { metadata.subjects = converted.metadata.subjects }
            chapters.append(contentsOf: converted.chapters)
        }
        guard !chapters.isEmpty else { throw ConversionError.noReadableText }
        return .converted(
            try EPUBBuilder.archive(metadata: metadata, chapters: chapters),
            from: .zip
        )
    }

    /// An EPUB packaged inside a zip — the most common shape, because forums and
    /// chat apps refuse `.epub` attachments and people zip them to get around it.
    private static func nestedEPUB(in zip: MiniZip) -> Data? {
        let candidates = zip.names
            .filter { $0.lowercased().hasSuffix(".epub") && !localName($0).hasPrefix(".") }
            .sorted(by: naturalOrder)
        for name in candidates {
            guard let payload = zip.data(named: name),
                  // Verify it really is one before handing it to the importer,
                  // rather than trusting the extension inside an untrusted zip.
                  let inner = try? MiniZip(data: payload),
                  inner.names.contains("mimetype") || inner.names.contains("META-INF/container.xml")
            else { continue }
            return payload
        }
        return nil
    }

    private struct ArchiveMember {
        let name: String
        let data: Data
        let format: ImportedFileFormat
    }

    /// Entries worth reading, in natural order so `chapter-2` precedes
    /// `chapter-10`. macOS resource forks (`__MACOSX`) and dotfiles are skipped —
    /// they are present in most zips made on a Mac and contain no story text.
    private static func readableMembers(of zip: MiniZip) -> [ArchiveMember] {
        zip.names
            .filter { name in
                let leaf = localName(name)
                return !name.hasPrefix("__MACOSX")
                    && !leaf.hasPrefix(".")
                    && !name.hasSuffix("/")
                    && ["html", "htm", "xhtml", "txt", "text", "md", "markdown"]
                        .contains((name as NSString).pathExtension.lowercased())
            }
            .sorted(by: naturalOrder)
            .compactMap { name in
                guard let data = zip.data(named: name) else { return nil }
                let format: ImportedFileFormat = ["html", "htm", "xhtml"]
                    .contains((name as NSString).pathExtension.lowercased()) ? .html : .plainText
                return ArchiveMember(name: name, data: data, format: format)
            }
    }

    private static func chaptersFromMember(_ member: ArchiveMember) throws -> HTMLWorkConverter.Result {
        guard let text = decode(member.data) else { throw ConversionError.unreadableText }
        let title = (localName(member.name) as NSString).deletingPathExtension
        switch member.format {
        case .html:
            return try HTMLWorkConverter.convert(html: text, fallbackTitle: title)
        default:
            return try PlainTextWorkConverter.convert(text: text, fallbackTitle: title)
        }
    }

    // MARK: - Helpers

    /// Sorts `chapter-2` before `chapter-10`, which plain string ordering does not.
    /// Community chapter dumps are numbered without zero padding almost every time.
    static func naturalOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    /// The file name, minus its extension, as a last-resort title. Community files
    /// are named things like `Fic Name - Author (complete).txt`, so this is often
    /// the *only* title information in the file — T-155 adds the parser that
    /// splits author and cruft out of it.
    private static func fallbackTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private static func text(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let text = decode(data) else { throw ConversionError.unreadableText }
        return text
    }

    /// UTF-8, then UTF-16 (Windows "Save As" default), then Latin-1 as the
    /// never-fails fallback. Rescued fanfic has been through a lot of editors.
    private static func decode(_ data: Data) -> String? {
        for encoding: String.Encoding in [.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
