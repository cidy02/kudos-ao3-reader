import Foundation

// MARK: - Beta reading models (T-576f)

/// Board-aligned copy constants and formatters for `BetaReadingSheet` (`Editor-Beta.dc.html`).
nonisolated enum BetaReadingCopy {
    static let screenTitle = "Beta Reading"
    static let sendSectionTitle = "Send a copy"
    static let sendSectionFooter = "Each beta gets their own copy, so their notes don’t sway each other."
    static let withYourBetasSectionTitle = "With your betas"
    static let footerPromise =
        "Kudos saves a version of the chapter before anything comes in. Nothing changes until you accept it."

    /// Subtitle beneath the Large Title (e.g. `"Chapter 4 · Slack Water"`).
    static func chapterSubtitle(chapterNumber: Int?, chapterTitle: String) -> String {
        let trimmedTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
        if let chapterNumber, chapterNumber > 0 {
            return "Chapter \(chapterNumber) · \(displayTitle)"
        }
        return displayTitle
    }

    /// Meta line on a row in `"With your betas"` (e.g. `"Word or Google Docs · sent Nov 20"`).
    static func sentCopyDetail(format: BetaCopyFormat, dateText: String) -> String {
        "\(format.sentDetailLabel) · sent \(dateText)"
    }

    /// Primary CTA button title below the review list (`"Review All 10"`).
    static func reviewAllButtonTitle(remainingCount: Int) -> String {
        "Review All \(max(0, remainingCount).formatted())"
    }

    /// Empty-state message when a returned copy has zero diffs and zero comments.
    static func emptyComparisonMessage(betaName: String) -> String {
        "\(betaName)’s copy matched what you sent, with no suggestions or comments."
    }
}

/// Export format offered when sending a chapter to a beta reader.
nonisolated enum BetaCopyFormat: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case docx
    case pdf

    var id: String { rawValue }

    var rowTitle: String {
        switch self {
        case .docx: "Word or Google Docs"
        case .pdf: "PDF"
        }
    }

    var rowDetail: String {
        switch self {
        case .docx: "Open it in Word, or upload it to Google Docs"
        case .pdf: "To read, not to edit"
        }
    }

    var sentDetailLabel: String {
        switch self {
        case .docx: "Word or Google Docs"
        case .pdf: "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .docx: "docx"
        case .pdf: "pdf"
        }
    }

    var systemImage: String {
        switch self {
        case .docx: "doc.text"
        case .pdf: "doc.richtext"
        }
    }

    /// Only `.docx` round-trips edits and comments back into Kudos.
    var supportsReturnImport: Bool {
        self == .docx
    }

    /// On macOS offer only `.docx`; iOS offers `.docx` and `.pdf`.
    static var availableSendFormats: [BetaCopyFormat] {
        #if os(iOS)
        [.docx, .pdf]
        #else
        [.docx]
        #endif
    }
}

/// Lifecycle state shown on the chip for each beta copy in "With your betas".
nonisolated enum BetaCopyStatus: String, Codable, Hashable, Sendable {
    case waiting
    case cameBack
    case reviewed

    var chipTitle: String {
        switch self {
        case .waiting: "Waiting"
        case .cameBack: "Came back"
        case .reviewed: "Reviewed"
        }
    }
}

/// Handling state for one suggested edit in a returned beta copy.
nonisolated enum BetaSuggestionState: String, Codable, Hashable, Sendable {
    case pending
    case accepted
    case rejected
    case unplaceable
    case dismissed

    var isHandled: Bool {
        switch self {
        case .accepted, .rejected, .dismissed: true
        case .pending, .unplaceable: false
        }
    }
}

/// One suggested edit extracted from a beta's returned `.docx` (either tracked or untracked).
nonisolated struct BetaSuggestionItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var author: String
    var date: Date?
    var isTracked: Bool
    var paragraphIndex: Int
    /// Sent paragraph plain text (empty when `isWholeParagraphAddition` is true).
    var paragraphText: String
    /// Up to 32 characters before `paragraphText` in the sent document plain text.
    var paragraphPrefix: String
    /// Up to 32 characters after `paragraphText` in the sent document plain text.
    var paragraphSuffix: String
    /// UTF-16 offset of `paragraphText` in the sent document plain text.
    var paragraphUTF16Offset: Int
    /// UTF-16 start offset of `deletedText` within `paragraphText`.
    var editStartUTF16: Int
    /// UTF-16 end offset of `deletedText` within `paragraphText`.
    var editEndUTF16: Int
    var deletedText: String
    var insertedText: String
    /// Up to 32 characters of `paragraphText` immediately before `editStartUTF16`.
    var localPrefix: String
    /// Up to 32 characters of `paragraphText` immediately after `editEndUTF16`.
    var localSuffix: String
    /// True when the beta added a brand-new paragraph not present in the sent copy.
    var isWholeParagraphAddition: Bool
    var state: BetaSuggestionState

    init(
        id: UUID = UUID(),
        author: String,
        date: Date? = nil,
        isTracked: Bool,
        paragraphIndex: Int,
        paragraphText: String,
        paragraphPrefix: String,
        paragraphSuffix: String,
        paragraphUTF16Offset: Int,
        editStartUTF16: Int,
        editEndUTF16: Int,
        deletedText: String,
        insertedText: String,
        localPrefix: String,
        localSuffix: String,
        isWholeParagraphAddition: Bool = false,
        state: BetaSuggestionState = .pending
    ) {
        self.id = id
        self.author = author
        self.date = date
        self.isTracked = isTracked
        self.paragraphIndex = paragraphIndex
        self.paragraphText = paragraphText
        self.paragraphPrefix = paragraphPrefix
        self.paragraphSuffix = paragraphSuffix
        self.paragraphUTF16Offset = paragraphUTF16Offset
        self.editStartUTF16 = editStartUTF16
        self.editEndUTF16 = editEndUTF16
        self.deletedText = deletedText
        self.insertedText = insertedText
        self.localPrefix = localPrefix
        self.localSuffix = localSuffix
        self.isWholeParagraphAddition = isWholeParagraphAddition
        self.state = state
    }

    /// Plain text offered when the writer taps Copy on an unplaceable suggestion.
    var copyableText: String {
        insertedText.isEmpty ? deletedText : insertedText
    }

    /// Anchor for locating the sent paragraph inside the current plain text.
    var paragraphAnchor: WritingAnnotationAnchor {
        WritingAnnotationAnchor(
            quote: paragraphText,
            prefix: paragraphPrefix,
            suffix: paragraphSuffix,
            utf16Offset: paragraphUTF16Offset
        )
    }
}

/// One comment extracted from a beta's returned `.docx` and linked to a 576d chapter note.
nonisolated struct BetaCommentItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var sourceCommentID: String?
    var author: String
    var date: Date?
    var quote: String
    var text: String
    var paragraphIndex: Int
    var characterOffsetUTF16: Int
    /// Linked 576d `WritingAnnotation.id` created when the copy came back.
    var annotationID: UUID?
    var isDone: Bool

    init(
        id: UUID = UUID(),
        sourceCommentID: String? = nil,
        author: String,
        date: Date? = nil,
        quote: String,
        text: String,
        paragraphIndex: Int,
        characterOffsetUTF16: Int,
        annotationID: UUID? = nil,
        isDone: Bool = false
    ) {
        self.id = id
        self.sourceCommentID = sourceCommentID
        self.author = author
        self.date = date
        self.quote = quote
        self.text = text
        self.paragraphIndex = paragraphIndex
        self.characterOffsetUTF16 = characterOffsetUTF16
        self.annotationID = annotationID
        self.isDone = isDone
    }

    /// Text saved on the 576d `.note` annotation (prefixed with the beta's name).
    var annotationNoteText: String {
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthor.isEmpty else { return trimmedText }
        if trimmedText.hasPrefix("\(trimmedAuthor):") {
            return trimmedText
        }
        return "\(trimmedAuthor): \(trimmedText)"
    }
}

/// Persisted record of one beta copy sent from a chapter, stored in `betas.json`.
nonisolated struct BetaCopyRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var betaName: String
    var format: BetaCopyFormat
    var sentAt: Date
    var sentHTML: String
    var returnedAt: Date?
    var status: BetaCopyStatus
    var hasSnapshottedBeforeAccept: Bool
    var suggestions: [BetaSuggestionItem]
    var comments: [BetaCommentItem]
    var updatedAt: Date
    var updatedBy: String

    var pendingSuggestions: [BetaSuggestionItem] {
        suggestions.filter { $0.state == .pending }
    }

    /// Pending suggestions that can be placed automatically into an existing text run.
    var acceptablePendingSuggestions: [BetaSuggestionItem] {
        suggestions.filter { $0.state == .pending && !$0.isWholeParagraphAddition }
    }

    /// Pending whole-paragraph additions that the writer copies and pastes by hand.
    var pasteOnlyPendingSuggestions: [BetaSuggestionItem] {
        suggestions.filter { $0.state == .pending && $0.isWholeParagraphAddition }
    }

    var openComments: [BetaCommentItem] {
        comments.filter { !$0.isDone }
    }

    var remainingCount: Int {
        suggestions.filter { !$0.state.isHandled }.count + openComments.count
    }

    var isFullyHandled: Bool {
        remainingCount == 0
    }

    /// Cards interleaved in chapter order (paragraph index, then offset within the paragraph).
    var orderedReviewCards: [BetaReviewCard] {
        let indexed: [(order: Int, card: BetaReviewCard)] =
            suggestions.enumerated().map { ($0.offset, .suggestion($0.element)) }
            + comments.enumerated().map { ($0.offset, .comment($0.element)) }
        return indexed.sorted { lhs, rhs in
            if lhs.card.paragraphIndex != rhs.card.paragraphIndex {
                return lhs.card.paragraphIndex < rhs.card.paragraphIndex
            }
            if lhs.card.offsetUTF16 != rhs.card.offsetUTF16 {
                return lhs.card.offsetUTF16 < rhs.card.offsetUTF16
            }
            if lhs.card.kindOrder != rhs.card.kindOrder {
                return lhs.card.kindOrder < rhs.card.kindOrder
            }
            return lhs.order < rhs.order
        }.map(\.card)
    }

    /// Section title matching `Editor-Beta.dc.html` (e.g. `"Lark’s edits · 6 suggestions, 4 comments"`).
    var reviewSectionTitle: String {
        let titlePrefix = "\(betaName)’s edits"
        let suggestionCount = suggestions.count
        let commentCount = comments.count
        var parts: [String] = []
        if suggestionCount > 0 {
            parts.append("\(suggestionCount.formatted()) \(suggestionCount == 1 ? "suggestion" : "suggestions")")
        }
        if commentCount > 0 {
            parts.append("\(commentCount.formatted()) \(commentCount == 1 ? "comment" : "comments")")
        }
        if parts.isEmpty {
            return "\(titlePrefix) · No changes found"
        }
        return "\(titlePrefix) · \(parts.joined(separator: ", "))"
    }

    /// Updates `status` to `.reviewed` when all returned cards are handled.
    mutating func refreshStatusFromItems() {
        guard returnedAt != nil else { return }
        status = isFullyHandled ? .reviewed : .cameBack
    }
}

/// On-disk envelope for a chapter's beta records (`chapters/<chapterID>/betas.json`).
nonisolated struct WritingChapterBetasFile: Codable, Equatable, Sendable {
    var copies: [BetaCopyRecord]
}

/// Chapter-order review item rendered in the beta review list.
nonisolated enum BetaReviewCard: Identifiable, Equatable, Sendable {
    case suggestion(BetaSuggestionItem)
    case comment(BetaCommentItem)

    var id: String {
        switch self {
        case let .suggestion(item): "s-\(item.id.uuidString)"
        case let .comment(item): "c-\(item.id.uuidString)"
        }
    }

    var paragraphIndex: Int {
        switch self {
        case let .suggestion(item): item.paragraphIndex
        case let .comment(item): item.paragraphIndex
        }
    }

    var offsetUTF16: Int {
        switch self {
        case let .suggestion(item): item.editStartUTF16
        case let .comment(item): item.characterOffsetUTF16
        }
    }

    var kindOrder: Int {
        switch self {
        case .suggestion: 0
        case .comment: 1
        }
    }
}

/// Typed errors for `.docx` reading, writing, and file import.
nonisolated enum BetaReadingError: LocalizedError, Equatable, Sendable {
    case invalidDOCX(String)
    case missingDocumentXML
    case xmlParseFailed(String)
    case fileReadFailed(String)
    case fileTooLarge(maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidDOCX(detail):
            "Couldn’t open that Word document: \(detail)"
        case .missingDocumentXML:
            "That file doesn’t look like a Word document (missing document body)."
        case let .xmlParseFailed(detail):
            "Couldn’t read the document’s contents: \(detail)"
        case let .fileReadFailed(detail):
            "Couldn’t read the selected file: \(detail)"
        case let .fileTooLarge(maxBytes):
            "That file is too large to import (limit is \(maxBytes / (1024 * 1024)) MB)."
        }
    }
}

/// Builds clean, filesystem-safe export names such as `"Chapter 4 – for Lark.docx"`.
nonisolated enum BetaExportFileName {
    static func make(
        chapterNumber: Int?,
        chapterTitle: String,
        betaName: String,
        format: BetaCopyFormat
    ) -> String {
        let baseLabel: String
        if let chapterNumber, chapterNumber > 0 {
            baseLabel = "Chapter \(chapterNumber)"
        } else {
            let cleanedTitle = sanitize(chapterTitle)
            baseLabel = cleanedTitle.isEmpty ? "Chapter" : cleanedTitle
        }
        let cleanedBeta = sanitize(betaName)
        let suffix = cleanedBeta.isEmpty ? "" : " – for \(cleanedBeta)"
        return "\(baseLabel)\(suffix).\(format.fileExtension)"
    }

    static func sanitize(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|\0")
            .union(.controlCharacters)
            .union(.newlines)
        let mapped = raw.unicodeScalars.map { scalar in
            forbidden.contains(scalar) ? " " : String(scalar)
        }.joined()
        let collapsed = mapped
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(collapsed.drop(while: { $0 == "." })).trimmingCharacters(in: .whitespaces)
    }
}

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
