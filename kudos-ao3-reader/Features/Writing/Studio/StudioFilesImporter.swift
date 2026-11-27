import Foundation
import SwiftSoup
import UniformTypeIdentifiers

/// Supported document formats for Writing Studio local import (`Studio-Files`).
/// Word (`.docx`) is read by `StudioDocxImport`; the older binary `.doc` is not.
nonisolated enum StudioImportableFormat: String, Equatable, Sendable {
    case plainText
    case markdown
    case html
    case docx
}

/// Typed failures for local document import.
nonisolated enum StudioDocumentImportError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedFormat(String)
    case unreadableText
    case emptyDocument
    case fileTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            if ext.caseInsensitiveCompare("doc") == .orderedSame {
                return "Older .doc files aren't supported. Save it as .docx in Word, then import that."
            }
            return "Kudos can import Word (.docx), plain text, Markdown, or HTML documents here."
        case .unreadableText:
            return "This file couldn't be read as text."
        case .emptyDocument:
            return "This document has no text to import."
        case .fileTooLarge:
            return "This file is too large to import as a single chapter."
        }
    }
}

/// Result of importing a file into `WritingDocumentStore`.
nonisolated struct StudioImportedDocument: Equatable, Sendable {
    let work: WritingWork
    let chapter: WritingChapter
    let format: StudioImportableFormat
}

/// Imports Word (`.docx`), plain text, Markdown, or HTML files from Files into a new
/// local manuscript in `WritingDocumentStore`. Every other format is rejected.
nonisolated enum StudioDocumentImporter {
    static let maxFileBytes = 20 * 1024 * 1024

    static let plainTextExtensions: Set<String> = ["txt", "text"]
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    static let htmlExtensions: Set<String> = ["html", "htm", "xhtml"]
    static let docxExtensions: Set<String> = ["docx"]

    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .html]
        // Not `BetaDOCXContentType.docx`: its `.data` fallback would let every file through.
        if let docx = UTType("org.openxmlformats.wordprocessingml.document") { types.append(docx) }
        if let markdown = UTType(filenameExtension: "md"), !types.contains(markdown) {
            types.append(markdown)
        } else if let markdown = UTType("net.daringfireball.markdown"), !types.contains(markdown) {
            types.append(markdown)
        }
        return types
    }

    static func importFile(
        at url: URL,
        into store: WritingDocumentStore
    ) async throws -> StudioImportedDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        // `readFileData` refuses an over-limit Word file before reading it into memory.
        let data = docxExtensions.contains(url.pathExtension.lowercased())
            ? try BetaDOCXReader.readFileData(at: url, maxBytes: maxFileBytes)
            : try Data(contentsOf: url)
        let format = try detectFormat(url: url, data: data)
        let fallbackTitle = defaultTitle(for: url)
        let converted = if format == .docx {
            try StudioDocxImport.convertToHTML(docxData: data, fallbackTitle: fallbackTitle)
        } else {
            try convertToHTML(text: try decodeText(data), format: format, fallbackTitle: fallbackTitle)
        }

        let work = try await store.createWork(title: converted.title, ao3WorkID: nil)
        let chapter = try await store.addChapter(workID: work.id, title: "")
        let saved = try await store.saveChapter(
            workID: work.id,
            chapter: chapter,
            bodyHTML: converted.bodyHTML
        )
        return StudioImportedDocument(work: work, chapter: saved.chapter, format: format)
    }

    static func detectFormat(url: URL, data: Data) throws -> StudioImportableFormat {
        guard !data.isEmpty else { throw StudioDocumentImportError.emptyDocument }
        guard data.count <= maxFileBytes else {
            throw StudioDocumentImportError.fileTooLarge(data.count)
        }

        let ext = url.pathExtension.lowercased()
        // A .docx is a zip, so it skips the binary sniff; a broken one fails with its own message.
        if docxExtensions.contains(ext) { return .docx }
        if let rejectedBinary = detectBinarySignature(in: data) {
            throw StudioDocumentImportError.unsupportedFormat(ext.isEmpty ? rejectedBinary : ext)
        }

        if plainTextExtensions.contains(ext) { return .plainText }
        if markdownExtensions.contains(ext) { return .markdown }
        if htmlExtensions.contains(ext) { return .html }
        throw StudioDocumentImportError.unsupportedFormat(ext.isEmpty ? "unknown" : ext)
    }

    static func decodeText(_ data: Data) throws -> String {
        guard !data.isEmpty else { throw StudioDocumentImportError.emptyDocument }
        let bytes = Array(data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            if let text = String(bytes: bytes.dropFirst(3), encoding: .utf8) {
                return text
            }
            throw StudioDocumentImportError.unreadableText
        }
        if bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0xFF, 0xFE]) {
            if let text = String(data: data, encoding: .utf16) {
                return text
            }
            throw StudioDocumentImportError.unreadableText
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        // Windows-1252 before Latin-1: bytes 0x91–0x94 are curly quotes, which
        // Latin-1 would keep as C1 controls. UTF-16 is only accepted with a BOM above.
        if isLikelySingleByteText(bytes) {
            if let text = String(data: data, encoding: .windowsCP1252), !text.isEmpty {
                return text
            }
            if let text = String(data: data, encoding: .isoLatin1), !text.isEmpty {
                return text
            }
        }
        throw StudioDocumentImportError.unreadableText
    }

    static func convertToHTML(
        text: String,
        format: StudioImportableFormat,
        fallbackTitle: String
    ) throws -> (title: String, bodyHTML: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let cleanFallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFallback = cleanFallback.isEmpty ? "Untitled" : cleanFallback

        switch format {
        case .plainText:
            let bodyHTML = plainTextToHTML(normalized)
            guard !bodyHTML.isEmpty else { throw StudioDocumentImportError.emptyDocument }
            return (safeFallback, bodyHTML)
        case .markdown:
            let result = markdownToHTML(normalized, fallbackTitle: safeFallback)
            guard !result.bodyHTML.isEmpty else { throw StudioDocumentImportError.emptyDocument }
            return result
        case .html:
            return try sanitizeHTML(normalized, fallbackTitle: safeFallback)
        case .docx:
            // Binary: `importFile` routes it to `StudioDocxImport`, never through text.
            throw StudioDocumentImportError.unsupportedFormat("docx")
        }
    }

    // MARK: - Sniffing

    private static func detectBinarySignature(in data: Data) -> String? {
        let head = Array(data.prefix(68))
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return "zip" }
        if head.starts(with: Array("%PDF".utf8)) { return "pdf" }
        if head.starts(with: Array("{\\rtf".utf8)) { return "rtf" }
        if head.starts(with: [0x52, 0x61, 0x72, 0x21]) { return "rar" }
        if head.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return "7z" }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if head.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if head.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) { return "doc" }

        let hasUTF16BOM = head.starts(with: [0xFE, 0xFF]) || head.starts(with: [0xFF, 0xFE])
        if !hasUTF16BOM, data.prefix(4096).contains(0x00) {
            return "binary"
        }
        return nil
    }

    private static func isLikelySingleByteText(_ bytes: [UInt8]) -> Bool {
        let sample = bytes.prefix(4096)
        var controlCount = 0
        for byte in sample {
            if byte < 0x09 || (byte > 0x0D && byte < 0x20) {
                controlCount += 1
            }
        }
        return controlCount == 0
    }

    private static func defaultTitle(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled" : name
    }

    // MARK: - Converters

    private static func plainTextToHTML(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var blocks: [[String]] = []
        var current: [String] = []
        for line in trimmed.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    blocks.append(current)
                    current = []
                }
            } else {
                current.append(escapeHTML(line))
            }
        }
        if !current.isEmpty { blocks.append(current) }

        return blocks
            .map { "<p>\($0.joined(separator: "<br>"))</p>" }
            .joined(separator: "\n")
    }

    private static func markdownToHTML(
        _ text: String,
        fallbackTitle: String
    ) -> (title: String, bodyHTML: String) {
        let lines = text.components(separatedBy: "\n")
        var extractedTitle: String?
        var htmlBlocks: [String] = []
        var paragraphLines: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let rendered = paragraphLines.map(renderMarkdownInline).joined(separator: "<br>")
            htmlBlocks.append("<p>\(rendered)</p>")
            paragraphLines = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
            } else if trimmed.hasPrefix("```") {
                flushParagraph()
                htmlBlocks.append(consumeCodeFence(lines: lines, index: &index))
            } else if isHorizontalRule(trimmed) {
                flushParagraph()
                htmlBlocks.append("<hr>")
                index += 1
            } else if let heading = parseMarkdownHeading(trimmed) {
                flushParagraph()
                if heading.level == 1, extractedTitle == nil, htmlBlocks.isEmpty {
                    extractedTitle = heading.text
                }
                htmlBlocks.append("<h\(heading.level)>\(renderMarkdownInline(heading.text))</h\(heading.level)>")
                index += 1
            } else if let block = consumeSpecialBlock(trimmed: trimmed, lines: lines, index: &index) {
                flushParagraph()
                if !block.isEmpty { htmlBlocks.append(block) }
            } else {
                paragraphLines.append(line)
                index += 1
            }
        }
        flushParagraph()

        let trimmedTitle = extractedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle
        return (resolvedTitle, htmlBlocks.joined(separator: "\n"))
    }

    private static func consumeCodeFence(lines: [String], index: inout Int) -> String {
        index += 1
        var codeLines: [String] = []
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            codeLines.append(escapeHTML(lines[index]))
            index += 1
        }
        if index < lines.count { index += 1 }
        return "<pre><code>\(codeLines.joined(separator: "\n"))</code></pre>"
    }

    private static func consumeSpecialBlock(
        trimmed: String,
        lines: [String],
        index: inout Int
    ) -> String? {
        if trimmed.hasPrefix(">") {
            var quoteLines: [String] = []
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                guard candidate.hasPrefix(">") else { break }
                let stripped = candidate.dropFirst().trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty { quoteLines.append(renderMarkdownInline(stripped)) }
                index += 1
            }
            return quoteLines.isEmpty
                ? ""
                : "<blockquote><p>\(quoteLines.joined(separator: "<br>"))</p></blockquote>"
        }
        if isUnorderedListItem(trimmed) {
            var items: [String] = []
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                guard isUnorderedListItem(candidate) else { break }
                let content = String(candidate.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                items.append("<li>\(renderMarkdownInline(content))</li>")
                index += 1
            }
            return "<ul>\(items.joined())</ul>"
        }
        if let firstItem = orderedListItemText(trimmed) {
            var items = ["<li>\(renderMarkdownInline(firstItem))</li>"]
            index += 1
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                guard let nextItem = orderedListItemText(candidate) else { break }
                items.append("<li>\(renderMarkdownInline(nextItem))</li>")
                index += 1
            }
            return "<ol>\(items.joined())</ol>"
        }
        return nil
    }

    private static func sanitizeHTML(
        _ rawHTML: String,
        fallbackTitle: String
    ) throws -> (title: String, bodyHTML: String) {
        let parsed = try SwiftSoup.parse(rawHTML)
        let docTitle = (try? parsed.title())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let h1Title = (try? parsed.select("h1").first()?.text())?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = if !docTitle.isEmpty {
            docTitle
        } else if !h1Title.isEmpty {
            h1Title
        } else {
            fallbackTitle
        }

        let allowlist = try Whitelist.relaxed()
            .removeTags("img")
            .addTags("hr", "s", "del", "ins", "details", "summary")
        let clean = try Cleaner(headWhitelist: nil, bodyWhitelist: allowlist).clean(parsed)
        clean.outputSettings().prettyPrint(pretty: false)
        let fragment = try clean.body()?.html().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plainText = fragment.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else { throw StudioDocumentImportError.emptyDocument }
        return (resolvedTitle, fragment)
    }

    private static func parseMarkdownHeading(_ line: String) -> (level: Int, text: String)? {
        var hashes = 0
        for character in line {
            if character == "#" { hashes += 1 } else { break }
        }
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let headingText = rest.trimmingCharacters(in: .whitespaces)
        return headingText.isEmpty ? nil : (hashes, headingText)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" }
            || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func orderedListItemText(_ line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dotIndex)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func renderMarkdownInline(_ raw: String) -> String {
        var result = escapeHTML(stripRemoteMarkdownImages(raw))
        result = replaceMarkdownLinks(in: result)
        result = replacingRegex(#"`([^`]+)`"#, in: result, with: "<code>$1</code>")
        result = replacingRegex(#"\*\*(.+?)\*\*"#, in: result, with: "<strong>$1</strong>")
        result = replacingRegex(#"__(.+?)__"#, in: result, with: "<strong>$1</strong>")
        result = replacingRegex(#"~~(.+?)~~"#, in: result, with: "<s>$1</s>")
        result = replacingRegex(#"(?<!\*)\*([^*]+?)\*(?!\*)"#, in: result, with: "<em>$1</em>")
        result = replacingRegex(#"(?<![\w])_([^_]+?)_(?![\w])"#, in: result, with: "<em>$1</em>")
        return result
    }

    /// Remote Markdown images become their alt text so the chapter does not keep the URL.
    private static func stripRemoteMarkdownImages(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"!\[([^\]]*)\]\((?:https?:)?//[^)\s]+(?:\s+"[^"]*")?\)"#
        ) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    private static func replaceMarkdownLinks(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "<a href=\"$2\">$1</a>")
    }

    private static func replacingRegex(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// On-device storage summary shown in the footer of `Studio-Files`.
nonisolated struct StudioStorageSummary: Equatable, Sendable {
    let documentCount: Int
    let byteCount: Int64

    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    func summaryText(deviceName: String) -> String {
        let noun = documentCount == 1 ? "document" : "documents"
        return "\(documentCount.formatted()) \(noun) · \(formattedBytes) on this \(deviceName)."
    }

    static func measure(root: URL, documentCount: Int) -> StudioStorageSummary {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path),
              let enumerator = manager.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return StudioStorageSummary(documentCount: documentCount, byteCount: 0)
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return StudioStorageSummary(documentCount: documentCount, byteCount: total)
    }
}

/// 30-day retention math and labels for `WritingDocumentStore` Recently Deleted items.
nonisolated enum StudioRecentlyDeletedHelper {
    static let urgentThresholdDays = 7

    static func daysRemaining(deletedAt: Date, now: Date = Date()) -> Int? {
        guard deletedAt != .distantFuture else { return nil }
        let expiresAt = deletedAt.addingTimeInterval(WritingDocumentStore.retention)
        let remaining = expiresAt.timeIntervalSince(now)
        if remaining <= 0 { return 0 }
        return Int(ceil(remaining / 86_400))
    }

    static func countdownText(deletedAt: Date, now: Date = Date()) -> String {
        guard let days = daysRemaining(deletedAt: deletedAt, now: now) else {
            return "Kept until restored or deleted"
        }
        switch days {
        case ...0: return "Expires today"
        case 1: return "1 day left"
        default: return "\(days) days left"
        }
    }

    static func isUrgent(deletedAt: Date, now: Date = Date()) -> Bool {
        guard let days = daysRemaining(deletedAt: deletedAt, now: now) else { return false }
        return days <= urgentThresholdDays
    }
}
