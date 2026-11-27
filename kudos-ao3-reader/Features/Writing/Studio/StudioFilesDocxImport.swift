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
        let trimmedFallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = headingTitle.isEmpty
            ? (trimmedFallback.isEmpty ? "Untitled" : trimmedFallback)
            : headingTitle
        return (title, body.blocks.map(\.html).joined(separator: "\n"))
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
        rejectEntities(parser)
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        rejectEntities(parser)
    }

    func parser(
        _ parser: XMLParser,
        foundUnparsedEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?,
        notationName: String?
    ) {
        rejectEntities(parser)
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        rejectEntities(parser)
        return nil
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil { failure = parseError }
    }

    private func rejectEntities(_ parser: XMLParser) {
        failure = BetaReadingError.xmlParseFailed("XML entity declarations are not supported.")
        parser.abortParsing()
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

        /// Grows this text piece when `format` matches. Drop the stored buffer first:
        /// appending while this case still holds it copies the whole paragraph.
        mutating func absorb(_ text: String, format: Format) -> Bool {
            guard case .text(var existing, let current) = self, current == format else { return false }
            self = .lineBreak
            existing.append(text)
            self = .text(existing, current)
            return true
        }
    }

    /// Revision and drawing subtrees that never reach the page: tracked deletions
    /// (`w:del`, `w:moveFrom`), deleted field code, pictures and text boxes, and the
    /// *previous* properties kept inside `w:rPrChange` / `w:pPrChange`. Live field
    /// instructions (`w:instrText`) are read, not skipped, so a HYPERLINK field can
    /// become a link; they are never copied into the chapter.
    private static let skipped: Set<String> = [
        "del", "moveFrom", "delInstrText", "drawing", "pict", "Fallback",
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
    /// Href from a `HYPERLINK` field (`w:fldSimple` or a complex field). `w:hyperlink` wins.
    private var fieldHref: String?
    private var savedFieldHref: String?
    private var simpleField = false
    private var complexFieldDepth = 0
    /// Non-nil between `fldCharType="begin"` and `"separate"`: instruction text only.
    private var fieldInstruction: String?
    private var instructionBuffer: String?
    /// Set when `w:pPr` holds an empty `w:del` / `w:moveFrom`: the paragraph mark is gone.
    private var paragraphMarkDeleted = false
    /// Pieces of a paragraph whose mark was deleted, waiting to join the next one.
    private var carried: (pieces: [Piece], heading: Int?)?
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
            // Content deletions are skipped whole. An empty `w:del` / `w:moveFrom`
            // inside `w:pPr` is the paragraph mark itself: the next paragraph joins this one.
            if inParagraphProperties, !inRun,
               (elementName == "del" || elementName == "moveFrom") {
                paragraphMarkDeleted = true
            }
            skipDepth = 1
            return
        }
        switch elementName {
        case "p":
            inParagraph = true
            headingLevel = nil
            paragraphMarkDeleted = false
            pieces = []
        case "pPr": inParagraphProperties = inParagraph
        case "pStyle":
            if inParagraphProperties, let style = attribute("val", in: attributeDict),
               let level = Self.headingLevel(forStyle: style) {
                headingLevel = level
            }
        case "outlineLvl":
            // 0 is heading 1. 9 is body text. A real heading style already won.
            if inParagraphProperties, headingLevel == nil,
               let raw = attribute("val", in: attributeDict),
               let level = Int(raw), (0...8).contains(level) {
                headingLevel = min(level + 1, 6)
            }
        case "tbl":
            flushCarried()
        case "hyperlink":
            linkHref = attribute("id", in: attributeDict)
                .flatMap { linkTargets[$0] }
                .flatMap(Self.safeURL)
        case "fldSimple":
            if !simpleField {
                savedFieldHref = fieldHref
                simpleField = true
                fieldHref = Self.hyperlinkURL(in: attribute("instr", in: attributeDict) ?? "")
            }
        case "fldChar":
            switch attribute("fldCharType", in: attributeDict) {
            case "begin":
                complexFieldDepth += 1
                if complexFieldDepth == 1 {
                    fieldInstruction = ""
                    fieldHref = nil
                }
            case "separate":
                if complexFieldDepth == 1 {
                    fieldHref = fieldInstruction.flatMap(Self.hyperlinkURL(in:))
                    fieldInstruction = nil
                    if inRun { runFormat.href = linkHref ?? fieldHref }
                }
            case "end":
                if complexFieldDepth == 1 {
                    fieldInstruction = nil
                    fieldHref = nil
                }
                complexFieldDepth = max(0, complexFieldDepth - 1)
            default:
                break
            }
        case "r":
            if inParagraph {
                inRun = true
                runFormat = Format()
                runFormat.href = linkHref ?? fieldHref
            }
        case "rPr": inRunProperties = inRun
        case "b": if inRunProperties { runFormat.bold = isOn(attributeDict) }
        case "i": if inRunProperties { runFormat.italic = isOn(attributeDict) }
        case "u": if inRunProperties { runFormat.underline = isOn(attributeDict) }
        case "strike", "dstrike": if inRunProperties { runFormat.strike = isOn(attributeDict) }
        case "t": if inRun { textBuffer = "" }
        case "instrText":
            if fieldInstruction != nil { instructionBuffer = "" }
        case "br", "cr":
            guard inRun else { break }
            let breakType = attribute("type", in: attributeDict)?.lowercased()
            if breakType == "page" || breakType == "column" {
                // Not a chapter line break. A space stops the two sides gluing;
                // trim still drops a break parked at the paragraph's edge.
                appendText(" ")
            } else {
                pieces.append(.lineBreak)
            }
        case "tab": if inRun { appendText(" ") }
        case "noBreakHyphen": if inRun { appendText("-") }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipDepth == 0 else { return }
        textBuffer?.append(string)
        instructionBuffer?.append(string)
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
        case "instrText":
            if let chunk = instructionBuffer {
                fieldInstruction?.append(chunk)
                instructionBuffer = nil
            }
        case "rPr": inRunProperties = false
        case "r":
            inRun = false
            inRunProperties = false
        case "pPr": inParagraphProperties = false
        case "hyperlink": linkHref = nil
        case "fldSimple":
            if simpleField {
                simpleField = false
                fieldHref = savedFieldHref
                savedFieldHref = nil
            }
        case "tc", "tr", "tbl":
            flushCarried()
        case "p": finishParagraph()
        default: break
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        flushCarried()
    }

    // MARK: - Paragraphs

    private func appendText(_ text: String) {
        guard inParagraph, !text.isEmpty else { return }
        // Word splits one styled phrase into many runs; merge them back into one element.
        if let last = pieces.indices.last, pieces[last].absorb(text, format: runFormat) {
            return
        }
        pieces.append(.text(text, runFormat))
    }

    private func finishParagraph() {
        let markDeleted = paragraphMarkDeleted
        let currentPieces = pieces
        let currentHeading = headingLevel
        defer {
            inParagraph = false
            inParagraphProperties = false
            inRun = false
            inRunProperties = false
            paragraphMarkDeleted = false
            textBuffer = nil
            pieces = []
        }
        guard inParagraph else { return }

        let previous = carried
        carried = nil
        var combined = currentPieces
        var heading = currentHeading
        if let previous {
            combined = previous.pieces + currentPieces
            // The deleted mark belonged to the first paragraph, so its style wins.
            heading = previous.heading
        }
        if markDeleted {
            carried = (combined, heading)
            return
        }
        emit(combined, heading: heading)
    }

    /// A table, cell, or row is a hard boundary: a deleted paragraph mark must not
    /// pull the next cell's text into this one.
    private func flushCarried() {
        guard let carried else { return }
        self.carried = nil
        emit(carried.pieces, heading: carried.heading)
    }

    private func emit(_ pieces: [Piece], heading: Int?) {
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
        let plainText = trimmed.map { piece -> String in
            switch piece {
            case let .text(text, _): text
            case .lineBreak: " "
            }
        }.joined()
        // Word's empty paragraphs are spacing, not content.
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let inner = trimmed.map { piece -> String in
            switch piece {
            case .lineBreak: "<br>"
            case let .text(text, format): Self.markup(text, format)
            }
        }.joined()
        let tag = heading.map { "h\($0)" } ?? "p"
        blocks.append(Block(html: "<\(tag)>\(inner)</\(tag)>", headingLevel: heading, plainText: plainText))
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
    /// A raw control character or newline is rejected so the URL cannot break out of the href.
    private static func safeURL(_ raw: String) -> String? {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        let scalarsAreSafe = url.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 32 && scalar.value != 127 && !scalar.properties.isWhitespace
        }
        guard scalarsAreSafe else { return nil }
        let lower = url.lowercased()
        let allowed = ["http://", "https://", "mailto:"].contains { lower.hasPrefix($0) }
        return allowed ? url : nil
    }

    /// Destination of a `HYPERLINK` field instruction, or nil for an internal bookmark
    /// (`\l`), a tooltip (`\o`), or a scheme this importer will not write.
    private static func hyperlinkURL(in instruction: String) -> String? {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 9, trimmed.prefix(9).lowercased() == "hyperlink" else { return nil }
        let rest = trimmed.dropFirst(9)
        if let first = rest.first, !first.isWhitespace, first != "\\", first != "\"", first != "'" {
            return nil
        }
        var pendingSwitch: Character?
        var index = rest.startIndex
        while index < rest.endIndex {
            let character = rest[index]
            if character.isWhitespace {
                index = rest.index(after: index)
                continue
            }
            if character == "\\" {
                let next = rest.index(after: index)
                guard next < rest.endIndex else { return nil }
                pendingSwitch = rest[next]
                index = rest.index(after: next)
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                let start = rest.index(after: index)
                guard let end = rest[start...].firstIndex(of: quote) else { return nil }
                let value = String(rest[start..<end])
                let isDestination = pendingSwitch == nil
                pendingSwitch = nil
                index = rest.index(after: end)
                if isDestination { return safeURL(value) }
                continue
            }
            pendingSwitch = nil
            while index < rest.endIndex, !rest[index].isWhitespace, rest[index] != "\\" {
                index = rest.index(after: index)
            }
        }
        return nil
    }
}
