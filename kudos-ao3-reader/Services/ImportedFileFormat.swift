import Foundation

/// What kind of document the user handed us, decided by **content** rather than
/// by file extension.
///
/// Extensions are unreliable for this feature specifically: works redistributed
/// through Reddit, Discord and forum attachments arrive renamed (`fic.epub.zip`,
/// `story.txt` that is really HTML, `chapter1` with no extension at all), and
/// Discord in particular rewrites names it does not like. Sniffing the bytes is
/// what makes "just hand me the file" work.
nonisolated enum ImportedFileFormat: String, CaseIterable, Sendable {
    /// A real EPUB — imports directly, no conversion.
    case epub
    /// HTML or XHTML: AO3's own "Download → HTML", a browser "Save Page As",
    /// a Wayback snapshot, a SingleFile capture, an FFN chapter save.
    case html
    /// Plain text or Markdown.
    case plainText
    /// A ZIP that is not an EPUB: chapter files, or an EPUB nested inside.
    case zip
    /// Formats a later task in this series handles (T-153: docx, pdf;
    /// T-154: mobi/azw3, rar, 7z). Detected now so the failure message can name
    /// the format and say what to do, instead of "unsupported file".
    case docx
    case odt
    case pdf
    case rtf
    case mobi
    case rar
    case sevenZip
    case unknown

    /// Human-readable name for error messages and the provenance record.
    var displayName: String {
        switch self {
        case .epub: "EPUB"
        case .html: "HTML"
        case .plainText: "plain text"
        case .zip: "ZIP archive"
        case .docx: "Word document"
        case .odt: "OpenDocument text"
        case .pdf: "PDF"
        case .rtf: "RTF"
        case .mobi: "Kindle book"
        case .rar: "RAR archive"
        case .sevenZip: "7-Zip archive"
        case .unknown: "unrecognized file"
        }
    }

    /// True for formats this task can turn into an EPUB today.
    var isConvertible: Bool {
        switch self {
        case .epub, .html, .plainText, .zip: true
        case .docx, .odt, .pdf, .rtf, .mobi, .rar, .sevenZip, .unknown: false
        }
    }

    // MARK: - Detection

    /// How many bytes the sniffer reads before deciding. Enough for every magic
    /// number below (the furthest is MOBI's, at offset 60) plus a generous window
    /// for HTML that opens with comments, a BOM, or a long `<!DOCTYPE>`.
    private static let sniffLength = 4096

    /// Identifies the file at `url`. Never throws: an unreadable or empty file is
    /// `.unknown`, which the caller reports as a normal import failure.
    static func detect(at url: URL) -> Self {
        guard let prefix = readPrefix(of: url), !prefix.isEmpty else { return .unknown }

        if prefix.starts(with: [0x50, 0x4B, 0x03, 0x04]) { // "PK\u{03}\u{04}"
            return detectZipFamily(at: url)
        }
        if prefix.starts(with: Array("%PDF".utf8)) { return .pdf }
        if prefix.starts(with: Array("{\\rtf".utf8)) { return .rtf }
        if prefix.starts(with: [0x52, 0x61, 0x72, 0x21]) { return .rar } // "Rar!"
        if prefix.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .sevenZip } // "7z"
        // Palm database header: the 8-byte type+creator pair sits at offset 60.
        // Covers .mobi/.azw/.azw3/.prc, which all wear the same coat.
        if prefix.count >= 68 {
            let palmType = String(bytes: prefix[60..<68], encoding: .ascii)
            if palmType == "BOOKMOBI" || palmType == "TEXtREAd" { return .mobi }
        }

        return detectTextFamily(prefix: prefix, url: url)
    }

    /// Splits the `PK` family apart by looking at what is actually inside, since
    /// EPUB, DOCX, ODT and a plain chapter zip share one magic number.
    private static func detectZipFamily(at url: URL) -> Self {
        // A zip has to be read via its central directory, so this needs the whole
        // file. Bounded by `MiniZip.Limits.epub`, which rejects hostile archives
        // before allocating anything.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let zip = try? MiniZip(data: data)
        else { return .zip }

        let names = Set(zip.names)
        if names.contains("mimetype"),
           let mimetype = zip.data(named: "mimetype"),
           let text = String(bytes: mimetype, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "application/epub+zip" { return .epub }
            if trimmed.hasPrefix("application/vnd.oasis.opendocument") { return .odt }
        }
        // No mimetype entry, but an OPF plus a container means EPUB anyway — some
        // repackaged files lose the mimetype entry and still read fine.
        if names.contains("META-INF/container.xml") { return .epub }
        if names.contains("word/document.xml") { return .docx }
        return .zip
    }

    /// Decides between HTML and plain text. Extension is the tiebreaker here
    /// (not the decider): a `.txt` that opens with `<html>` is still HTML, but a
    /// `.md` full of angle brackets is not.
    private static func detectTextFamily(prefix: [UInt8], url: URL) -> Self {
        guard let text = decodeText(prefix) else { return .unknown }
        let head = text.prefix(2048).lowercased()
        let markers = ["<!doctype html", "<html", "<body", "<head", "<?xml", "<div", "<p>"]
        if markers.contains(where: head.contains) { return .html }

        switch url.pathExtension.lowercased() {
        case "html", "htm", "xhtml": return .html
        case "txt", "text", "md", "markdown": return .plainText
        default:
            // Unlabelled but decodable as text: treat as plain text rather than
            // refusing. A wrong guess here still produces a readable work.
            return .plainText
        }
    }

    // MARK: - Bytes

    private static func readPrefix(of url: URL) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: sniffLength) else { return nil }
        return Array(data)
    }

    /// UTF-8 first, then Latin-1 — the same two-step the AO3 EPUB metadata
    /// scanner uses, because scraped and re-saved fanfic is full of files that
    /// are almost, but not quite, UTF-8. A truncated multi-byte character at the
    /// sniff boundary must not make a valid file undecodable, so the last few
    /// bytes are retried away before giving up.
    private static func decodeText(_ bytes: [UInt8]) -> String? {
        for dropped in 0..<min(4, bytes.count) {
            let slice = bytes.dropLast(dropped)
            if let text = String(bytes: slice, encoding: .utf8) { return text }
        }
        return String(bytes: bytes, encoding: .isoLatin1)
    }
}
