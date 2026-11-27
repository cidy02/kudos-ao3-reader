import Foundation

// MARK: - OOXML (.docx) reader for Word and Google Docs

/// Reads paragraphs, runs, tracked insertions (`w:ins` / `w:moveTo`), tracked deletions
/// (`w:del` / `w:delText` / `w:moveFrom`), and comments (`word/comments.xml` +
/// `word/commentsExtended.xml` + `commentRangeStart`/`End`) from a Word or Google Docs `.docx`.
nonisolated enum BetaDOCXReader {
    static func parse(
        documentXML: Data,
        commentsXML: Data? = nil,
        commentsExtendedXML: Data? = nil
    ) throws -> BetaDOCXDocument {
        let parsedCommentsByID = try commentsXML.map(parseCommentsXML) ?? [:]
        let parentParaByPara = try commentsExtendedXML.map(parseCommentsExtendedXML) ?? [:]

        let delegate = DocumentXMLDelegate()
        try runXMLParser(data: documentXML, delegate: delegate, fallbackError: "Malformed document.xml")

        let comments = resolveComments(
            ranges: delegate.commentRanges,
            metadataByID: parsedCommentsByID,
            parentParaIDByParaID: parentParaByPara
        )
        return BetaDOCXDocument(paragraphs: delegate.paragraphs, comments: comments)
    }

    private static func runXMLParser(
        data: Data,
        delegate: BetaXMLParserDelegate,
        fallbackError: String
    ) throws {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate

        guard parser.parse() else {
            if let betaError = delegate.parseError as? BetaReadingError {
                throw betaError
            }
            let reason = delegate.parseError?.localizedDescription
                ?? parser.parserError?.localizedDescription
                ?? fallbackError
            throw BetaReadingError.xmlParseFailed(reason)
        }
    }

    private static func parseCommentsXML(_ data: Data) throws -> [String: ParsedCommentMeta] {
        let delegate = CommentsXMLDelegate()
        try runXMLParser(data: data, delegate: delegate, fallbackError: "Malformed comments.xml")
        return delegate.commentsByID
    }

    private static func parseCommentsExtendedXML(_ data: Data) throws -> [String: String] {
        let delegate = CommentsExtendedXMLDelegate()
        try runXMLParser(data: data, delegate: delegate, fallbackError: "Malformed commentsExtended.xml")
        return delegate.parentParaIDByParaID
    }

    private static func resolveComments(
        ranges: [CommentRangeTracker],
        metadataByID: [String: ParsedCommentMeta],
        parentParaIDByParaID: [String: String]
    ) -> [BetaDOCXComment] {
        var rangeByID: [String: CommentRangeTracker] = [:]
        for range in ranges where rangeByID[range.id] == nil {
            rangeByID[range.id] = range
        }
        let parentCommentIDByID = buildParentCommentMap(
            metadataByID: metadataByID,
            parentParaIDByParaID: parentParaIDByParaID
        )

        var resolved: [(comment: BetaDOCXComment, depth: Int, order: Int)] = []
        for meta in metadataByID.values {
            let trimmedBody = meta.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBody.isEmpty else { continue }

            let bodyText = formattedCommentBody(
                trimmedBody,
                parentID: parentCommentIDByID[meta.id],
                metadataByID: metadataByID
            )
            let anchor = resolvedCommentAnchor(
                for: meta.id,
                rangeByID: rangeByID,
                parentCommentIDByID: parentCommentIDByID
            )
            resolved.append((
                comment: BetaDOCXComment(
                    id: meta.id,
                    author: meta.author,
                    date: meta.date,
                    initials: meta.initials,
                    text: bodyText,
                    paragraphIndex: anchor.range?.startParagraphIndex ?? 0,
                    baselineStartUTF16: anchor.range?.baselineStartUTF16 ?? 0,
                    baselineEndUTF16: anchor.range?.baselineEndUTF16 ?? 0,
                    quote: anchor.quote
                ),
                depth: anchor.depth,
                order: meta.orderIndex
            ))
        }

        return resolved.sorted { lhs, rhs in
            let lKey = (
                lhs.comment.paragraphIndex, lhs.comment.baselineStartUTF16, lhs.depth, lhs.order, lhs.comment.id
            )
            let rKey = (
                rhs.comment.paragraphIndex, rhs.comment.baselineStartUTF16, rhs.depth, rhs.order, rhs.comment.id
            )
            return lKey < rKey
        }.map(\.comment)
    }

    private static func buildParentCommentMap(
        metadataByID: [String: ParsedCommentMeta],
        parentParaIDByParaID: [String: String]
    ) -> [String: String] {
        guard !parentParaIDByParaID.isEmpty else { return [:] }
        var commentIDByParaID: [String: String] = [:]
        for meta in metadataByID.values {
            for paraID in meta.paraIDs {
                commentIDByParaID[paraID] = meta.id
            }
        }
        var parentByID: [String: String] = [:]
        for meta in metadataByID.values {
            for paraID in meta.paraIDs.reversed() {
                if let parentPara = parentParaIDByParaID[paraID],
                   let parentID = commentIDByParaID[parentPara],
                   parentID != meta.id {
                    parentByID[meta.id] = parentID
                    break
                }
            }
        }
        return parentByID
    }

    private static func resolvedCommentAnchor(
        for id: String,
        rangeByID: [String: CommentRangeTracker],
        parentCommentIDByID: [String: String]
    ) -> (range: CommentRangeTracker?, quote: String, depth: Int) {
        var cursor: String? = id
        var visited: Set<String> = []
        var depth = 0
        while let current = cursor, visited.insert(current).inserted {
            if let found = rangeByID[current] {
                let raw = found.quotedBaselineText.isEmpty ? found.quotedInsertedText : found.quotedBaselineText
                return (found, raw.trimmingCharacters(in: .newlines), depth)
            }
            cursor = parentCommentIDByID[current]
            depth += 1
        }
        return (nil, "", depth)
    }

    private static func formattedCommentBody(
        _ body: String,
        parentID: String?,
        metadataByID: [String: ParsedCommentMeta]
    ) -> String {
        guard let parentID, let parent = metadataByID[parentID] else { return body }
        let parentOneLine = parent.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !parentOneLine.isEmpty else { return body }
        let preview = parentOneLine.count > 80
            ? String(parentOneLine.prefix(80)) + "…"
            : parentOneLine
        if let parentAuthor = parent.author, !parentAuthor.isEmpty {
            return "Reply to \(parentAuthor) (“\(preview)”): \(body)"
        }
        return "Reply to “\(preview)”: \(body)"
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
    let paraIDs: [String]
    let orderIndex: Int
}

private nonisolated struct CommentRangeTracker {
    let id: String
    var startParagraphIndex: Int
    var baselineStartUTF16: Int
    var baselineEndUTF16: Int
    var quotedBaselineText: String
    var quotedInsertedText: String
    var lastBaselineParagraphIndex: Int?
    var lastInsertedParagraphIndex: Int?
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

private nonisolated class BetaXMLParserDelegate: NSObject, XMLParserDelegate {
    var parseError: Error?

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        parseError = BetaReadingError.xmlParseFailed("XML entity declarations are not supported.")
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if self.parseError == nil { self.parseError = parseError }
    }
}

private nonisolated final class CommentsExtendedXMLDelegate: BetaXMLParserDelegate {
    var parentParaIDByParaID: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "commentEx" else { return }
        guard let paraID = BetaDOCXReader.attributeValue("paraId", in: attributeDict)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let parentParaID = BetaDOCXReader.attributeValue("paraIdParent", in: attributeDict)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !paraID.isEmpty,
              !parentParaID.isEmpty
        else { return }
        parentParaIDByParaID[paraID.uppercased()] = parentParaID.uppercased()
    }
}

private nonisolated final class CommentsXMLDelegate: BetaXMLParserDelegate {
    private static let ignoredElements: Set<String> = [
        "pPr", "rPr", "instrText", "drawing", "pict", "Fallback", "delInstrText",
    ]

    var commentsByID: [String: ParsedCommentMeta] = [:]

    private var currentID: String?
    private var currentAuthor: String?
    private var currentDate: Date?
    private var currentInitials: String?
    private var currentParaIDs: [String] = []
    private var nextOrderIndex = 0
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
        handleStartElement(elementName, attributes: attributeDict)
    }

    private func handleStartElement(_ name: String, attributes: [String: String]) {
        switch name {
        case "comment":
            startComment(attributes: attributes)
        case "p":
            guard currentID != nil else { return }
            inParagraph = true
            currentParagraph = ""
            recordParaID(from: attributes)
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

    private func startComment(attributes: [String: String]) {
        currentID = BetaDOCXReader.attributeValue("id", in: attributes)
        currentAuthor = BetaDOCXReader.normalizedAuthor(BetaDOCXReader.attributeValue("author", in: attributes))
        currentDate = BetaDOCXReader.parseOOXMLDate(BetaDOCXReader.attributeValue("date", in: attributes))
        currentInitials = BetaDOCXReader.normalizedAuthor(BetaDOCXReader.attributeValue("initials", in: attributes))
        currentParaIDs = []
        paragraphTexts = []
        currentParagraph = ""
    }

    private func recordParaID(from attributes: [String: String]) {
        guard let paraID = BetaDOCXReader.attributeValue("paraId", in: attributes)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !paraID.isEmpty
        else { return }
        currentParaIDs.append(paraID.uppercased())
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingText, ignoredDepth == 0 { textBuffer.append(string) }
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
        case "r": inRun = false
        case "p":
            if inParagraph {
                paragraphTexts.append(currentParagraph)
                currentParagraph = ""
                inParagraph = false
            }
        case "comment": finishComment()
        default: break
        }
    }

    private func finishComment() {
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
                text: joined,
                paraIDs: currentParaIDs,
                orderIndex: nextOrderIndex
            )
            nextOrderIndex += 1
        }
        currentID = nil
        currentAuthor = nil
        currentDate = nil
        currentInitials = nil
        currentParaIDs = []
        paragraphTexts = []
    }
}

private nonisolated final class DocumentXMLDelegate: BetaXMLParserDelegate {
    private static let ignoredElements: Set<String> = [
        "pPr", "rPr", "instrText", "drawing", "pict", "Fallback", "delInstrText",
    ]

    var paragraphs: [BetaDOCXParagraph] = []
    var commentRanges: [CommentRangeTracker] = []

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

    // MARK: - Element handlers

    private func handleStartElement(_ name: String, attributes: [String: String]) {
        switch name {
        case "p": startParagraph()
        case "ins", "moveTo": revisionStack.append(makeRevision(kind: .insertion, attributes: attributes))
        case "del", "moveFrom": revisionStack.append(makeRevision(kind: .deletion, attributes: attributes))
        case "r": if inParagraph { inRun = true }
        case "t", "delText":
            if inRun {
                collectingText = true
                textBuffer = ""
            }
        case "br", "cr": if inRun { emitText("\n") }
        case "tab": if inRun { emitText("\t") }
        case "noBreakHyphen": if inRun { emitText("-") }
        case "commentRangeStart", "commentRangeEnd", "commentReference":
            handleCommentMarkerElement(name, attributes: attributes)
        default: break
        }
    }

    private func handleCommentMarkerElement(_ name: String, attributes: [String: String]) {
        guard let commentID = BetaDOCXReader.attributeValue("id", in: attributes) else { return }
        switch name {
        case "commentRangeStart": openCommentRange(id: commentID)
        case "commentRangeEnd": closeCommentRange(id: commentID)
        case "commentReference": registerPointCommentIfNeeded(id: commentID)
        default: break
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
        case "r": inRun = false
        case "ins", "del", "moveTo", "moveFrom":
            if !revisionStack.isEmpty { revisionStack.removeLast() }
        case "p": finishParagraph()
        default: break
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

    private func makeRevision(kind: ActiveRevisionKind, attributes: [String: String]) -> ActiveRevision {
        ActiveRevision(
            kind: kind,
            author: BetaDOCXReader.normalizedAuthor(BetaDOCXReader.attributeValue("author", in: attributes)),
            date: BetaDOCXReader.parseOOXMLDate(BetaDOCXReader.attributeValue("date", in: attributes)),
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
            return .deletion(author: deletion.author, date: deletion.date, revisionID: deletion.revisionID)
        }
        if let insertion = revisionStack.last(where: { $0.kind == .insertion }) {
            return .insertion(author: insertion.author, date: insertion.date, revisionID: insertion.revisionID)
        }
        return .unchanged
    }

    private func emitText(_ text: String) {
        guard inParagraph, !text.isEmpty, let kind = resolvedSegmentKind() else { return }

        if let lastIndex = currentSegments.indices.last, canMerge(currentSegments[lastIndex].kind, with: kind) {
            currentSegments[lastIndex].text.append(text)
        } else {
            currentSegments.append(BetaDOCXSegment(kind: kind, text: text))
        }

        let currentParagraphIndex = paragraphs.count
        switch kind {
        case .unchanged, .deletion:
            let segmentStartUTF16 = currentBaselineUTF16
            currentBaselineUTF16 += text.utf16.count
            appendBaselineCommentQuotes(
                text: text,
                paragraphIndex: currentParagraphIndex,
                segmentStartUTF16: segmentStartUTF16
            )
        case .insertion:
            appendInsertedCommentQuotes(text: text, paragraphIndex: currentParagraphIndex)
        }
    }

    private func appendBaselineCommentQuotes(text: String, paragraphIndex: Int, segmentStartUTF16: Int) {
        for idx in commentRanges.indices where commentRanges[idx].isOpen {
            if let lastPara = commentRanges[idx].lastBaselineParagraphIndex {
                if lastPara != paragraphIndex {
                    commentRanges[idx].quotedBaselineText.append("\n")
                }
            } else if commentRanges[idx].startParagraphIndex != paragraphIndex {
                // Range started at the end of a prior paragraph; anchor where quoted text begins.
                commentRanges[idx].startParagraphIndex = paragraphIndex
                commentRanges[idx].baselineStartUTF16 = segmentStartUTF16
            }
            commentRanges[idx].quotedBaselineText.append(text)
            commentRanges[idx].lastBaselineParagraphIndex = paragraphIndex
            if commentRanges[idx].startParagraphIndex == paragraphIndex {
                commentRanges[idx].baselineEndUTF16 = currentBaselineUTF16
            }
        }
    }

    private func appendInsertedCommentQuotes(text: String, paragraphIndex: Int) {
        for idx in commentRanges.indices where commentRanges[idx].isOpen {
            if let lastPara = commentRanges[idx].lastInsertedParagraphIndex {
                if lastPara != paragraphIndex {
                    commentRanges[idx].quotedInsertedText.append("\n")
                }
            } else if commentRanges[idx].lastBaselineParagraphIndex == nil,
                      commentRanges[idx].startParagraphIndex != paragraphIndex {
                commentRanges[idx].startParagraphIndex = paragraphIndex
                commentRanges[idx].baselineStartUTF16 = currentBaselineUTF16
            }
            commentRanges[idx].quotedInsertedText.append(text)
            commentRanges[idx].lastInsertedParagraphIndex = paragraphIndex
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

    private func addCommentTracker(id: String, paragraphIndex: Int, baselineStart: Int, isOpen: Bool) {
        commentIndexByID[id] = commentRanges.count
        commentRanges.append(
            CommentRangeTracker(
                id: id,
                startParagraphIndex: paragraphIndex,
                baselineStartUTF16: baselineStart,
                baselineEndUTF16: baselineStart,
                quotedBaselineText: "",
                quotedInsertedText: "",
                lastBaselineParagraphIndex: nil,
                lastInsertedParagraphIndex: nil,
                isOpen: isOpen
            )
        )
    }
}
