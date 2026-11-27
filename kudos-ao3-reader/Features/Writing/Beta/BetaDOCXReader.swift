import Foundation

// MARK: - Parsed .docx model

nonisolated struct BetaDOCXSegment: Equatable, Hashable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        case unchanged
        case insertion(author: String?, date: Date?, revisionID: String?)
        case deletion(author: String?, date: Date?, revisionID: String?)
    }

    var kind: Kind
    var text: String
}

nonisolated struct BetaDOCXParagraph: Equatable, Hashable, Sendable {
    var segments: [BetaDOCXSegment]

    /// Text with deletions kept and insertions dropped (what was sent before tracked edits).
    var baselineText: String {
        var result = ""
        for segment in segments {
            switch segment.kind {
            case .unchanged, .deletion:
                result.append(segment.text)
            case .insertion:
                break
            }
        }
        return result
    }

    /// Text with insertions kept and deletions dropped (the beta's proposed paragraph).
    var finalText: String {
        var result = ""
        for segment in segments {
            switch segment.kind {
            case .unchanged, .insertion:
                result.append(segment.text)
            case .deletion:
                break
            }
        }
        return result
    }

    var hasTrackedChanges: Bool {
        segments.contains { segment in
            switch segment.kind {
            case .unchanged: false
            case .insertion, .deletion: !segment.text.isEmpty
            }
        }
    }
}

nonisolated struct BetaDOCXComment: Equatable, Hashable, Sendable {
    var id: String
    var author: String?
    var date: Date?
    var initials: String?
    var text: String
    var paragraphIndex: Int
    var baselineStartUTF16: Int
    var baselineEndUTF16: Int
    var quote: String
}

nonisolated struct BetaDOCXDocument: Equatable, Sendable {
    var paragraphs: [BetaDOCXParagraph]
    var comments: [BetaDOCXComment]
}

// MARK: - OOXML (.docx) reader for Word and Google Docs

/// Reads paragraphs, runs, tracked insertions (`w:ins`), tracked deletions (`w:del` /
/// `w:delText`), and comments (`word/comments.xml` + `commentRangeStart`/`End`) from a
/// `.docx` archive produced by Microsoft Word or Google Docs.
nonisolated enum BetaDOCXReader {
    static func read(docxData: Data) throws -> BetaDOCXDocument {
        let zip: MiniZip
        do {
            zip = try MiniZip(data: docxData, limits: .epub)
        } catch {
            throw BetaReadingError.invalidDOCX(error.localizedDescription)
        }
        guard let documentXML = entryData(named: "word/document.xml", in: zip) else {
            throw BetaReadingError.missingDocumentXML
        }
        let commentsXML = entryData(named: "word/comments.xml", in: zip)
        return try parse(documentXML: documentXML, commentsXML: commentsXML)
    }

    static func parse(documentXML: Data, commentsXML: Data? = nil) throws -> BetaDOCXDocument {
        let parsedCommentsByID: [String: ParsedCommentMeta]
        if let commentsXML {
            parsedCommentsByID = try parseCommentsXML(commentsXML)
        } else {
            parsedCommentsByID = [:]
        }

        let delegate = DocumentXMLDelegate()
        let parser = XMLParser(data: documentXML)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate

        guard parser.parse() else {
            let reason = delegate.parseError?.localizedDescription
                ?? parser.parserError?.localizedDescription
                ?? "Malformed document.xml"
            throw BetaReadingError.xmlParseFailed(reason)
        }

        let comments = resolveComments(
            ranges: delegate.commentRanges,
            metadataByID: parsedCommentsByID
        )
        return BetaDOCXDocument(paragraphs: delegate.paragraphs, comments: comments)
    }

    private static func entryData(named target: String, in zip: MiniZip) -> Data? {
        if let direct = zip.data(named: target) {
            return direct
        }
        let lower = target.lowercased()
        guard let matched = zip.names.first(where: { $0.lowercased() == lower }) else {
            return nil
        }
        return zip.data(named: matched)
    }

    private static func parseCommentsXML(_ data: Data) throws -> [String: ParsedCommentMeta] {
        let delegate = CommentsXMLDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate

        guard parser.parse() else {
            let reason = delegate.parseError?.localizedDescription
                ?? parser.parserError?.localizedDescription
                ?? "Malformed comments.xml"
            throw BetaReadingError.xmlParseFailed(reason)
        }
        return delegate.commentsByID
    }

    private static func resolveComments(
        ranges: [CommentRangeTracker],
        metadataByID: [String: ParsedCommentMeta]
    ) -> [BetaDOCXComment] {
        var resolved: [BetaDOCXComment] = []
        var seenIDs: Set<String> = []
        for range in ranges {
            guard seenIDs.insert(range.id).inserted,
                  let meta = metadataByID[range.id]
            else { continue }
            let trimmedBody = meta.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBody.isEmpty else { continue }
            let quote = range.quotedBaselineText.isEmpty
                ? range.quotedInsertedText
                : range.quotedBaselineText
            resolved.append(
                BetaDOCXComment(
                    id: range.id,
                    author: meta.author,
                    date: meta.date,
                    initials: meta.initials,
                    text: trimmedBody,
                    paragraphIndex: range.startParagraphIndex,
                    baselineStartUTF16: range.baselineStartUTF16,
                    baselineEndUTF16: range.baselineEndUTF16,
                    quote: quote.trimmingCharacters(in: .newlines)
                )
            )
        }
        return resolved.sorted { lhs, rhs in
            if lhs.paragraphIndex != rhs.paragraphIndex {
                return lhs.paragraphIndex < rhs.paragraphIndex
            }
            if lhs.baselineStartUTF16 != rhs.baselineStartUTF16 {
                return lhs.baselineStartUTF16 < rhs.baselineStartUTF16
            }
            return lhs.id < rhs.id
        }
    }

    fileprivate static func attributeValue(
        _ localName: String,
        in attributes: [String: String]
    ) -> String? {
        if let prefixed = attributes["w:\(localName)"] { return prefixed }
        if let plain = attributes[localName] { return plain }
        let suffix = ":\(localName)"
        return attributes.first { $0.key.hasSuffix(suffix) }?.value
    }

    fileprivate static func parseOOXMLDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        if let date = whole.date(from: trimmed) { return date }

        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return dateOnly.date(from: trimmed)
    }

    fileprivate static func normalizedAuthor(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Internal XML parser delegates

private nonisolated struct ParsedCommentMeta {
    let id: String
    let author: String?
    let date: Date?
    let initials: String?
    let text: String
}

private nonisolated struct CommentRangeTracker {
    let id: String
    var startParagraphIndex: Int
    var baselineStartUTF16: Int
    var baselineEndUTF16: Int
    var quotedBaselineText: String
    var quotedInsertedText: String
    var isOpen: Bool
}

private nonisolated enum ActiveRevisionKind: Equatable {
    case insertion
    case deletion
}

private nonisolated struct ActiveRevision {
    let kind: ActiveRevisionKind
    let author: String?
    let date: Date?
    let revisionID: String?
}

private nonisolated final class CommentsXMLDelegate: NSObject, XMLParserDelegate {
    private static let ignoredElements: Set<String> = [
        "pPr", "rPr", "instrText", "drawing", "pict", "Fallback",
    ]

    var commentsByID: [String: ParsedCommentMeta] = [:]
    var parseError: Error?

    private var currentID: String?
    private var currentAuthor: String?
    private var currentDate: Date?
    private var currentInitials: String?
    private var paragraphTexts: [String] = []
    private var currentParagraph = ""
    private var inParagraph = false
    private var inRun = false
    private var collectingText = false
    private var textBuffer = ""
    private var ignoredDepth = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if ignoredDepth > 0 {
            ignoredDepth += 1
            return
        }
        if Self.ignoredElements.contains(elementName) {
            ignoredDepth = 1
            return
        }
        switch elementName {
        case "comment":
            currentID = BetaDOCXReader.attributeValue("id", in: attributeDict)
            currentAuthor = BetaDOCXReader.normalizedAuthor(
                BetaDOCXReader.attributeValue("author", in: attributeDict)
            )
            currentDate = BetaDOCXReader.parseOOXMLDate(
                BetaDOCXReader.attributeValue("date", in: attributeDict)
            )
            currentInitials = BetaDOCXReader.normalizedAuthor(
                BetaDOCXReader.attributeValue("initials", in: attributeDict)
            )
            paragraphTexts = []
            currentParagraph = ""
        case "p":
            if currentID != nil {
                inParagraph = true
                currentParagraph = ""
            }
        case "r":
            if inParagraph { inRun = true }
        case "t":
            if inRun {
                collectingText = true
                textBuffer = ""
            }
        case "br", "cr":
            if inRun { currentParagraph.append("\n") }
        case "tab":
            if inRun { currentParagraph.append("\t") }
        case "noBreakHyphen":
            if inRun { currentParagraph.append("-") }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingText, ignoredDepth == 0 {
            textBuffer.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if ignoredDepth > 0 {
            ignoredDepth -= 1
            return
        }
        switch elementName {
        case "t":
            if collectingText {
                currentParagraph.append(textBuffer)
                textBuffer = ""
                collectingText = false
            }
        case "r":
            inRun = false
        case "p":
            if inParagraph {
                paragraphTexts.append(currentParagraph)
                currentParagraph = ""
                inParagraph = false
            }
        case "comment":
            if let commentID = currentID {
                let joined = paragraphTexts
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                commentsByID[commentID] = ParsedCommentMeta(
                    id: commentID,
                    author: currentAuthor,
                    date: currentDate,
                    initials: currentInitials,
                    text: joined
                )
            }
            currentID = nil
            currentAuthor = nil
            currentDate = nil
            currentInitials = nil
            paragraphTexts = []
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

private nonisolated final class DocumentXMLDelegate: NSObject, XMLParserDelegate {
    private static let ignoredElements: Set<String> = [
        "pPr", "rPr", "instrText", "drawing", "pict", "Fallback", "fldSimple", "delInstrText",
    ]

    var paragraphs: [BetaDOCXParagraph] = []
    var commentRanges: [CommentRangeTracker] = []
    var parseError: Error?

    private var ignoredDepth = 0
    private var inParagraph = false
    private var inRun = false
    private var collectingText = false
    private var textBuffer = ""
    private var currentSegments: [BetaDOCXSegment] = []
    private var currentBaselineUTF16 = 0
    private var revisionStack: [ActiveRevision] = []
    private var pendingCommentStartIDs: [String] = []
    private var commentIndexByID: [String: Int] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if ignoredDepth > 0 {
            ignoredDepth += 1
            return
        }
        if Self.ignoredElements.contains(elementName) {
            ignoredDepth = 1
            return
        }
        handleStartElement(elementName, attributes: attributeDict)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingText, ignoredDepth == 0 {
            textBuffer.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if ignoredDepth > 0 {
            ignoredDepth -= 1
            return
        }
        handleEndElement(elementName)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: - Element handlers

    private func handleStartElement(_ name: String, attributes: [String: String]) {
        switch name {
        case "p":
            startParagraph()
        case "ins":
            revisionStack.append(makeRevision(kind: .insertion, attributes: attributes))
        case "del":
            revisionStack.append(makeRevision(kind: .deletion, attributes: attributes))
        case "r":
            if inParagraph { inRun = true }
        case "t", "delText":
            if inRun {
                collectingText = true
                textBuffer = ""
            }
        case "br", "cr":
            if inRun { emitText("\n") }
        case "tab":
            if inRun { emitText("\t") }
        case "noBreakHyphen":
            if inRun { emitText("-") }
        case "commentRangeStart", "commentRangeEnd", "commentReference":
            handleCommentMarkerElement(name, attributes: attributes)
        default:
            break
        }
    }

    private func handleCommentMarkerElement(_ name: String, attributes: [String: String]) {
        guard let commentID = BetaDOCXReader.attributeValue("id", in: attributes) else { return }
        switch name {
        case "commentRangeStart":
            openCommentRange(id: commentID)
        case "commentRangeEnd":
            closeCommentRange(id: commentID)
        case "commentReference":
            registerPointCommentIfNeeded(id: commentID)
        default:
            break
        }
    }

    private func handleEndElement(_ name: String) {
        switch name {
        case "t", "delText":
            if collectingText {
                emitText(textBuffer)
                textBuffer = ""
                collectingText = false
            }
        case "r":
            inRun = false
        case "ins", "del":
            if !revisionStack.isEmpty {
                revisionStack.removeLast()
            }
        case "p":
            finishParagraph()
        default:
            break
        }
    }

    private func startParagraph() {
        inParagraph = true
        currentSegments = []
        currentBaselineUTF16 = 0
        let paragraphIndex = paragraphs.count
        for commentID in pendingCommentStartIDs {
            addCommentTracker(id: commentID, paragraphIndex: paragraphIndex, baselineStart: 0, isOpen: true)
        }
        pendingCommentStartIDs.removeAll()
    }

    private func finishParagraph() {
        guard inParagraph else { return }
        paragraphs.append(BetaDOCXParagraph(segments: currentSegments))
        currentSegments = []
        currentBaselineUTF16 = 0
        inParagraph = false
        inRun = false
        collectingText = false
        textBuffer = ""
    }

    private func makeRevision(
        kind: ActiveRevisionKind,
        attributes: [String: String]
    ) -> ActiveRevision {
        ActiveRevision(
            kind: kind,
            author: BetaDOCXReader.normalizedAuthor(
                BetaDOCXReader.attributeValue("author", in: attributes)
            ),
            date: BetaDOCXReader.parseOOXMLDate(
                BetaDOCXReader.attributeValue("date", in: attributes)
            ),
            revisionID: BetaDOCXReader.attributeValue("id", in: attributes)
        )
    }

    private func resolvedSegmentKind() -> BetaDOCXSegment.Kind? {
        let hasInsertion = revisionStack.contains { $0.kind == .insertion }
        let hasDeletion = revisionStack.contains { $0.kind == .deletion }
        if hasInsertion, hasDeletion {
            // Inserted and then deleted inside the same document: neither sent nor final.
            return nil
        }
        if let deletion = revisionStack.last(where: { $0.kind == .deletion }) {
            return .deletion(
                author: deletion.author,
                date: deletion.date,
                revisionID: deletion.revisionID
            )
        }
        if let insertion = revisionStack.last(where: { $0.kind == .insertion }) {
            return .insertion(
                author: insertion.author,
                date: insertion.date,
                revisionID: insertion.revisionID
            )
        }
        return .unchanged
    }

    private func emitText(_ text: String) {
        guard inParagraph, !text.isEmpty, let kind = resolvedSegmentKind() else { return }

        if let lastIndex = currentSegments.indices.last,
           canMerge(currentSegments[lastIndex].kind, with: kind) {
            currentSegments[lastIndex].text.append(text)
        } else {
            currentSegments.append(BetaDOCXSegment(kind: kind, text: text))
        }

        let currentParagraphIndex = paragraphs.count
        switch kind {
        case .unchanged, .deletion:
            let utf16Length = text.utf16.count
            currentBaselineUTF16 += utf16Length
            for idx in commentRanges.indices where commentRanges[idx].isOpen
                && commentRanges[idx].startParagraphIndex == currentParagraphIndex {
                commentRanges[idx].quotedBaselineText.append(text)
                commentRanges[idx].baselineEndUTF16 = currentBaselineUTF16
            }
        case .insertion:
            for idx in commentRanges.indices where commentRanges[idx].isOpen
                && commentRanges[idx].startParagraphIndex == currentParagraphIndex {
                commentRanges[idx].quotedInsertedText.append(text)
            }
        }
    }

    private func canMerge(_ lhs: BetaDOCXSegment.Kind, with rhs: BetaDOCXSegment.Kind) -> Bool {
        switch (lhs, rhs) {
        case (.unchanged, .unchanged):
            true
        case let (.insertion(lAuthor, _, _), .insertion(rAuthor, _, _)):
            lAuthor == rAuthor
        case let (.deletion(lAuthor, _, _), .deletion(rAuthor, _, _)):
            lAuthor == rAuthor
        default:
            false
        }
    }

    private func openCommentRange(id: String) {
        guard commentIndexByID[id] == nil else { return }
        if inParagraph {
            addCommentTracker(
                id: id,
                paragraphIndex: paragraphs.count,
                baselineStart: currentBaselineUTF16,
                isOpen: true
            )
        } else {
            pendingCommentStartIDs.append(id)
        }
    }

    private func closeCommentRange(id: String) {
        if let pendingIdx = pendingCommentStartIDs.firstIndex(of: id) {
            pendingCommentStartIDs.remove(at: pendingIdx)
            addCommentTracker(id: id, paragraphIndex: paragraphs.count, baselineStart: 0, isOpen: false)
            return
        }
        guard let idx = commentIndexByID[id] else { return }
        commentRanges[idx].isOpen = false
    }

    private func registerPointCommentIfNeeded(id: String) {
        guard commentIndexByID[id] == nil, !pendingCommentStartIDs.contains(id) else { return }
        let paragraphIndex = inParagraph ? paragraphs.count : max(0, paragraphs.count - 1)
        let offset = inParagraph ? currentBaselineUTF16 : 0
        addCommentTracker(id: id, paragraphIndex: paragraphIndex, baselineStart: offset, isOpen: false)
    }

    private func addCommentTracker(
        id: String,
        paragraphIndex: Int,
        baselineStart: Int,
        isOpen: Bool
    ) {
        let index = commentRanges.count
        commentIndexByID[id] = index
        commentRanges.append(
            CommentRangeTracker(
                id: id,
                startParagraphIndex: paragraphIndex,
                baselineStartUTF16: baselineStart,
                baselineEndUTF16: baselineStart,
                quotedBaselineText: "",
                quotedInsertedText: "",
                isOpen: isOpen
            )
        )
    }
}
