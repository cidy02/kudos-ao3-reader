import Foundation

// MARK: - Word (.docx) → AO3 chapter HTML for Studio's Import a Document

/// Turns a `.docx` into the same plain AO3 HTML a pasted document becomes: `<p>`, `<h1>`–`<h6>`,
/// `<em>`, `<strong>`, `<u>`, `<s>`, `<a>` and `<br>`. The document as it reads now: tracked
/// deletions are dropped, tracked insertions kept, comments never read.
///
/// The zip, size limits and errors are `BetaDOCXReader`'s (`maxFileBytes`, `docxLimits`,
/// `BetaReadingError`). Its parser keeps only text and revision kinds, not run formatting,
/// headings or links, so this walks `word/document.xml` itself for those.
///
/// shortcut: formatting comes from direct run properties only (not character or paragraph
/// styles), and lists import as plain paragraphs; upgrade by reading `styles.xml` and `numbering.xml`.
nonisolated enum StudioDocxImport {
    static func convertToHTML(
        docxData: Data,
        fallbackTitle: String
    ) throws -> (title: String, bodyHTML: String) {
        guard docxData.count <= BetaDOCXReader.maxFileBytes else {
            throw BetaReadingError.fileTooLarge(maxBytes: BetaDOCXReader.maxFileBytes)
        }
        let zip: MiniZip
        do {
            zip = try MiniZip(data: docxData, limits: BetaDOCXReader.docxLimits)
        } catch {
            throw BetaReadingError.invalidDOCX(error.localizedDescription)
        }
        guard let documentXML = entryData(named: "word/document.xml", in: zip) else {
            throw BetaReadingError.missingDocumentXML
        }

        var linkTargets: [String: String] = [:]
        if let relsXML = entryData(named: "word/_rels/document.xml.rels", in: zip) {
            let rels = StudioDocxRelationshipsDelegate()
            try run(rels, on: relsXML)
            linkTargets = rels.targets
        }
        let body = StudioDocxBodyDelegate(linkTargets: linkTargets)
        try run(body, on: documentXML)

        guard let first = body.blocks.first else { throw StudioDocumentImportError.emptyDocument }
        // Same rule as Markdown: a leading level-1 heading names the document.
        let headingTitle = first.headingLevel == 1
            ? first.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return (
            headingTitle.isEmpty ? fallbackTitle : headingTitle,
            body.blocks.map(\.html).joined(separator: "\n")
        )
    }

    private static func entryData(named target: String, in zip: MiniZip) -> Data? {
        if let direct = zip.data(named: target) { return direct }
        let lower = target.lowercased()
        guard let matched = zip.names.first(where: { $0.lowercased() == lower }) else { return nil }
        return zip.data(named: matched)
    }

    private static func run(_ delegate: StudioDocxXMLDelegate, on data: Data) throws {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            // The parser's own NSError is not one of ours; callers see one error type.
            if let failure = delegate.failure as? BetaReadingError { throw failure }
            throw BetaReadingError.xmlParseFailed(
                delegate.failure?.localizedDescription
                    ?? parser.parserError?.localizedDescription
                    ?? "Malformed document"
            )
        }
    }
}

// MARK: - XML delegates

private nonisolated class StudioDocxXMLDelegate: NSObject, XMLParserDelegate {
    var failure: Error?

    /// Prefixed (`w:val`, `r:id`) or plain, whichever the parser reports.
    func attribute(_ name: String, in attributes: [String: String]) -> String? {
        attributes.first { $0.key == name || $0.key.hasSuffix(":\(name)") }?.value
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        failure = BetaReadingError.xmlParseFailed("XML entity declarations are not supported.")
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil { failure = parseError }
    }
}

/// `word/_rels/document.xml.rels`: relationship id → external link target.
private nonisolated final class StudioDocxRelationshipsDelegate: StudioDocxXMLDelegate {
    var targets: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "Relationship", attributeDict["TargetMode"] == "External",
              let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        targets[id] = target
    }
}

/// `word/document.xml`: one block per non-empty paragraph.
private nonisolated final class StudioDocxBodyDelegate: StudioDocxXMLDelegate {
    struct Block {
        let html: String
        let headingLevel: Int?
        let plainText: String
    }

    private struct Format: Equatable {
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        var href: String?
    }

    private enum Piece {
        case text(String, Format)
        case lineBreak
    }

    /// Revision and drawing subtrees that never reach the page: tracked deletions
    /// (`w:del`, `w:moveFrom`), field code, pictures and text boxes, and the *previous*
    /// properties kept inside `w:rPrChange` / `w:pPrChange`.
    private static let skipped: Set<String> = [
        "del", "moveFrom", "instrText", "delInstrText", "drawing", "pict", "Fallback",
        "rPrChange", "pPrChange",
    ]

    var blocks: [Block] = []

    private let linkTargets: [String: String]
    private var skipDepth = 0
    private var inParagraph = false
    private var inParagraphProperties = false
    private var inRun = false
    private var inRunProperties = false
    private var headingLevel: Int?
    private var pieces: [Piece] = []
    private var runFormat = Format()
    private var linkHref: String?
    private var textBuffer: String?

    init(linkTargets: [String: String]) {
        self.linkTargets = linkTargets
        super.init()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if skipDepth > 0 {
            skipDepth += 1
            return
        }
        if Self.skipped.contains(elementName) {
            skipDepth = 1
            return
        }
        switch elementName {
        case "p":
            inParagraph = true
            headingLevel = nil
            pieces = []
        case "pPr": inParagraphProperties = inParagraph
        case "pStyle":
            if inParagraphProperties, let style = attribute("val", in: attributeDict) {
                headingLevel = Self.headingLevel(forStyle: style)
            }
        case "hyperlink":
            linkHref = attribute("id", in: attributeDict)
                .flatMap { linkTargets[$0] }
                .flatMap(Self.safeURL)
        case "r":
            if inParagraph {
                inRun = true
                runFormat = Format()
                runFormat.href = linkHref
            }
        case "rPr": inRunProperties = inRun
        case "b": if inRunProperties { runFormat.bold = isOn(attributeDict) }
        case "i": if inRunProperties { runFormat.italic = isOn(attributeDict) }
        case "u": if inRunProperties { runFormat.underline = isOn(attributeDict) }
        case "strike", "dstrike": if inRunProperties { runFormat.strike = isOn(attributeDict) }
        case "t": if inRun { textBuffer = "" }
        case "br", "cr":
            // A page or column break is layout, not a line break.
            let breakType = attribute("type", in: attributeDict)
            if inRun, breakType != "page", breakType != "column" { pieces.append(.lineBreak) }
        case "tab": if inRun { appendText(" ") }
        case "noBreakHyphen": if inRun { appendText("-") }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if skipDepth == 0 { textBuffer?.append(string) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if skipDepth > 0 {
            skipDepth -= 1
            return
        }
        switch elementName {
        case "t":
            if let text = textBuffer { appendText(text) }
            textBuffer = nil
        case "rPr": inRunProperties = false
        case "r":
            inRun = false
            inRunProperties = false
        case "pPr": inParagraphProperties = false
        case "hyperlink": linkHref = nil
        case "p": finishParagraph()
        default: break
        }
    }

    // MARK: - Paragraphs

    private func appendText(_ text: String) {
        guard inParagraph, !text.isEmpty else { return }
        // Word splits one styled phrase into many runs; merge them back into one element.
        if case let .text(existing, format)? = pieces.last, format == runFormat {
            pieces[pieces.count - 1] = .text(existing + text, format)
        } else {
            pieces.append(.text(text, runFormat))
        }
    }

    private func finishParagraph() {
        defer {
            inParagraph = false
            inParagraphProperties = false
            inRun = false
            inRunProperties = false
            textBuffer = nil
            pieces = []
        }
        guard inParagraph else { return }

        var trimmed = pieces
        if case let .text(text, format)? = trimmed.first {
            trimmed[0] = .text(String(text.drop(while: \.isWhitespace)), format)
        }
        if case let .text(text, format)? = trimmed.last {
            var tail = Substring(text)
            while let last = tail.last, last.isWhitespace { tail.removeLast() }
            trimmed[trimmed.count - 1] = .text(String(tail), format)
        }
        trimmed = trimmed.filter {
            if case let .text(text, _) = $0 { return !text.isEmpty }
            return true
        }
        let plainText = trimmed.compactMap { piece -> String? in
            if case let .text(text, _) = piece { return text }
            return nil
        }.joined()
        // Word's empty paragraphs are spacing, not content.
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let inner = trimmed.map { piece -> String in
            switch piece {
            case .lineBreak: "<br>"
            case let .text(text, format): Self.markup(text, format)
            }
        }.joined()
        let tag = headingLevel.map { "h\($0)" } ?? "p"
        blocks.append(Block(html: "<\(tag)>\(inner)</\(tag)>", headingLevel: headingLevel, plainText: plainText))
    }

    // MARK: - Helpers

    /// `<w:b/>` is on; `<w:b w:val="0"/>` (also false/off/none) turns it off again.
    private func isOn(_ attributes: [String: String]) -> Bool {
        guard let value = attribute("val", in: attributes)?.lowercased() else { return true }
        return !["0", "false", "off", "none"].contains(value)
    }

    private static func markup(_ text: String, _ format: Format) -> String {
        var html = StudioDocumentImporter.escapeHTML(text)
        if format.strike { html = "<s>\(html)</s>" }
        if format.underline { html = "<u>\(html)</u>" }
        if format.italic { html = "<em>\(html)</em>" }
        if format.bold { html = "<strong>\(html)</strong>" }
        if let href = format.href {
            html = "<a href=\"\(StudioDocumentImporter.escapeHTML(href))\">\(html)</a>"
        }
        return html
    }

    /// Word's built-in style ids are `Heading1`…`Heading9` and `Title`; AO3 has `<h1>`–`<h6>`.
    private static func headingLevel(forStyle style: String) -> Int? {
        let id = style.lowercased().replacingOccurrences(of: " ", with: "")
        if id == "title" { return 1 }
        guard id.hasPrefix("heading"), let level = Int(id.dropFirst("heading".count)) else { return nil }
        return min(max(level, 1), 6)
    }

    /// Only web and mail links come across; `javascript:` and friends stay plain text.
    private static func safeURL(_ raw: String) -> String? {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = url.lowercased()
        let allowed = ["http://", "https://", "mailto:"].contains { lower.hasPrefix($0) }
        return allowed ? url : nil
    }
}
