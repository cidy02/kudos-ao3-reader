import Foundation

// MARK: - Story-note name suggestions (`Editor-Names.dc.html`)

/// Pure prefix matcher for story-note name chips in `WritingKeysBar`.
nonisolated enum ChapterEditorNameMatcher {
    static let maxSuggestions = 3
    static let minimumPrefixLength = 2
    private static let apostrophes: Set<Character> = ["'", "’"]

    /// Returns up to `limit` name suggestions for `wordAtCaret` in story-note order.
    ///
    /// Matches case-insensitively (and diacritic-insensitively so typing `"aodhan"`
    /// still offers `"Aodhán"`), excludes names already typed in full, and includes
    /// typographic possessives (`"Marta’s"`) when the typed prefix ends in an apostrophe.
    static func suggestions(
        for wordAtCaret: String?,
        names: [String],
        limit: Int = maxSuggestions
    ) -> [String] {
        guard limit > 0, !names.isEmpty, let rawPrefix = wordAtCaret else { return [] }
        let prefix = rawPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefix.count >= minimumPrefixLength else { return [] }

        let endsWithApostrophe = prefix.last.map { apostrophes.contains($0) } ?? false
        let normalizedPrefix = normalizeApostrophes(prefix)
        let normalizedStem = endsWithApostrophe ? String(normalizedPrefix.dropLast()) : normalizedPrefix

        var results: [String] = []
        var seen: Set<String> = []

        for rawName in names {
            if results.count >= limit { break }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            for candidate in candidates(
                for: name,
                normalizedPrefix: normalizedPrefix,
                normalizedStem: normalizedStem,
                endsWithApostrophe: endsWithApostrophe
            ) {
                if results.count >= limit { break }
                let key = candidate.lowercased()
                if seen.insert(key).inserted {
                    results.append(candidate)
                }
            }
        }

        return results
    }

    private static func candidates(
        for name: String,
        normalizedPrefix: String,
        normalizedStem: String,
        endsWithApostrophe: Bool
    ) -> [String] {
        let normalizedName = normalizeApostrophes(name)
        var matches: [String] = []

        if endsWithApostrophe,
           !normalizedStem.isEmpty,
           !alreadyEndsInPossessive(normalizedName),
           normalizedName.compare(
               normalizedStem,
               options: [.caseInsensitive, .diacriticInsensitive]
           ) == .orderedSame {
            matches.append("\(name)’s")
        }

        if isPrefixMatch(prefix: normalizedPrefix, of: normalizedName),
           !isExactWholeMatch(prefix: normalizedPrefix, of: normalizedName) {
            matches.append(name)
        }

        return matches
    }

    private static func normalizeApostrophes(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "’")
    }

    private static func isPrefixMatch(prefix: String, of candidate: String) -> Bool {
        candidate.range(
            of: prefix,
            options: [.anchored, .caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private static func isExactWholeMatch(prefix: String, of candidate: String) -> Bool {
        candidate.compare(prefix, options: .caseInsensitive) == .orderedSame
    }

    private static func alreadyEndsInPossessive(_ normalizedName: String) -> Bool {
        let lower = normalizedName.lowercased()
        return lower.hasSuffix("’s") || lower.hasSuffix("’")
    }
}

// MARK: - Anchor construction, TK lookup, bridge payload & paragraph numbering

/// Pure HTML-offset utilities for creating, drawing, and locating chapter annotations.
nonisolated enum ChapterEditorAnnotationAnchoring {
    /// Builds a `WritingAnnotationAnchor` for a Rich Text selection range in `html`.
    static func anchorForSelection(
        html: String,
        range: RichEditorTextRange
    ) -> WritingAnnotationAnchor? {
        guard range.from >= 0, range.to > range.from, range.to <= html.utf16.count else {
            return nil
        }
        return WritingAnnotationReanchor.capture(in: html, utf16Range: range.from..<range.to)
    }

    /// Builds a `WritingAnnotationAnchor` for a typed `"TK"` at `range` in `html`.
    ///
    /// Uses `html[range]` directly when it is still `"TK"`. If the writer edited or typed on
    /// before saving, falls back to the nearest `"TK"` outside HTML tags on either side of `range.from`, within
    /// `tkSearchReach` (preferring a word-bounded `"TK"`).
    static func anchorForTK(
        html: String,
        range: RichEditorTextRange
    ) -> WritingAnnotationAnchor? {
        let totalUTF16 = html.utf16.count
        guard totalUTF16 >= 2 else { return nil }

        if range.from >= 0,
           range.to > range.from,
           range.to <= totalUTF16,
           let direct = WritingAnnotationReanchor.capture(in: html, utf16Range: range.from..<range.to),
           direct.quote == "TK" {
            return direct
        }

        let startOffset = max(0, min(range.from, totalUTF16))
        guard let foundRange = nearestTKUTF16Range(in: html, fromUTF16Offset: startOffset) else {
            return nil
        }
        return WritingAnnotationReanchor.capture(in: html, utf16Range: foundRange)
    }

    /// Converts placed annotations into `RichEditorAnnotationItem`s for `DraftSession.setAnnotations`.
    /// Resolved annotations and empty quotes are omitted.
    static func bridgeItems(from annotations: [WritingAnnotation]) -> [RichEditorAnnotationItem] {
        annotations.compactMap { annotation in
            guard annotation.resolvedAt == nil else { return nil }
            let length = annotation.quote.utf16.count
            guard length > 0 else { return nil }
            let start = max(0, annotation.utf16Offset)
            return RichEditorAnnotationItem(
                id: annotation.id.uuidString,
                kind: annotation.kind == .tk ? "tk" : "note",
                from: start,
                to: start + length
            )
        }
    }

    /// Computes the 1-based paragraph number for a UTF-16 offset in chapter HTML.
    ///
    /// Counts leaf text blocks (`<p>`, `<h1>`–`<h6>`, `<li>`, `<dt>`, `<dd>`, `<pre>`,
    /// `<summary>`) and direct-text `<blockquote>`/`<div>` containers without double-counting
    /// `<blockquote><p>…</p></blockquote>` or counting `<hr>` and inline tags. Falls back to
    /// blank-line paragraph counting for plain text without block tags.
    static func paragraphNumber(atUTF16Offset offset: Int, in html: String) -> Int? {
        guard !html.isEmpty, offset >= 0 else { return nil }
        let utf16 = html.utf16
        let limit = min(offset, utf16.count)
        var scanner = HTMLParagraphScanner(units: Array(utf16), limit: limit)
        return scanner.scan()
    }

    /// Strips HTML tags and collapses whitespace for showing a note's quoted passage in UI chrome.
    static func plainQuotePreview(from htmlQuote: String) -> String {
        var result = ""
        result.reserveCapacity(htmlQuote.count)
        var insideTag = false
        var activeQuote: Character?

        for char in htmlQuote {
            if insideTag {
                updateTagState(char, insideTag: &insideTag, activeQuote: &activeQuote, result: &result)
            } else if char == "<" {
                insideTag = true
            } else {
                result.append(char)
            }
        }

        let decoded = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
            .replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
            .replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
            .replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
            .replacingOccurrences(of: "&mdash;", with: "\u{2014}")
            .replacingOccurrences(of: "&ndash;", with: "\u{2013}")
            .replacingOccurrences(of: "&hellip;", with: "\u{2026}")
            .replacingOccurrences(of: "&amp;", with: "&")

        return decoded
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func updateTagState(
        _ char: Character,
        insideTag: inout Bool,
        activeQuote: inout Character?,
        result: inout String
    ) {
        if let quote = activeQuote {
            if char == quote { activeQuote = nil }
        } else if char == "\"" || char == "'" {
            activeQuote = char
        } else if char == ">" {
            insideTag = false
            if let last = result.last, !last.isWhitespace {
                result.append(" ")
            }
        }
    }

    // MARK: TK search helpers

    static let tkSearchReach = 400

    private static func nearestTKUTF16Range(in html: String, fromUTF16Offset startOffset: Int) -> Range<Int>? {
        let units = Array(html.utf16)
        let count = units.count
        guard count >= 2 else { return nil }

        // The nearest "TK" on either side of the stale offset: text deleted before it since it was typed moves it
        // back, text added moves it on (wave 48 review). A word-bounded one wins over a loose one; on a tie, the later.
        var index = 0
        var nearestBounded: Range<Int>?
        var nearestLoose: Range<Int>?
        func closer(_ candidate: Range<Int>, than current: Range<Int>?) -> Bool {
            // a TK further away than a few lines of typing is some other TK, not this one moved
            guard abs(candidate.lowerBound - startOffset) <= tkSearchReach else { return false }
            guard let current else { return true }
            return abs(candidate.lowerBound - startOffset) <= abs(current.lowerBound - startOffset)
        }
        while index < count {
            if units[index] == 0x3C { // '<'
                index = skipTagOrComment(in: units, from: index)
                continue
            }
            if units[index] == 0x54, // 'T'
               index + 1 < count,
               units[index + 1] == 0x4B { // 'K'
                let candidate = index..<(index + 2)
                if isWordBoundedTK(at: index, in: html) {
                    if closer(candidate, than: nearestBounded) { nearestBounded = candidate }
                } else if closer(candidate, than: nearestLoose) {
                    nearestLoose = candidate
                }
            }
            index += 1
        }

        return nearestBounded ?? nearestLoose
    }

    private static func skipTagOrComment(in units: [UInt16], from start: Int) -> Int {
        let count = units.count
        if startsComment(in: units, at: start) {
            return endOfComment(in: units, from: start + 4)
        }
        var cursor = start + 1
        var quote: UInt16 = 0
        while cursor < count {
            let unit = units[cursor]
            if quote != 0 {
                if unit == quote { quote = 0 }
            } else if unit == 0x22 || unit == 0x27 {
                quote = unit
            } else if unit == 0x3E { // '>'
                return cursor + 1
            }
            cursor += 1
        }
        return count
    }

    static func startsComment(in units: [UInt16], at start: Int) -> Bool {
        start + 3 < units.count
            && units[start + 1] == 0x21
            && units[start + 2] == 0x2D
            && units[start + 3] == 0x2D
    }

    static func endOfComment(in units: [UInt16], from start: Int) -> Int {
        let count = units.count
        var cursor = start
        while cursor + 2 < count {
            if units[cursor] == 0x2D, units[cursor + 1] == 0x2D, units[cursor + 2] == 0x3E {
                return cursor + 3
            }
            cursor += 1
        }
        return count
    }

    private static func isWordBoundedTK(at utf16Start: Int, in html: String) -> Bool {
        let utf16 = html.utf16
        let lower = utf16.index(utf16.startIndex, offsetBy: utf16Start)
        let upper = utf16.index(lower, offsetBy: 2)
        guard let start = String.Index(lower, within: html),
              let end = String.Index(upper, within: html) else {
            return false
        }
        if start > html.startIndex {
            let before = html[html.index(before: start)]
            if before.isLetter || before.isNumber { return false }
        }
        if end < html.endIndex {
            let after = html[end]
            if after.isLetter || after.isNumber { return false }
        }
        return true
    }
}

// MARK: - Counts, list grouping, and event sequence trackers

/// Open note, open TK, and resolved counts for a chapter's annotations.
nonisolated struct ChapterEditorAnnotationCounts: Equatable, Hashable, Sendable {
    var openNoteCount: Int
    var openTKCount: Int
    var resolvedCount: Int

    var openTotal: Int { openNoteCount + openTKCount }

    static func count(_ annotations: [WritingAnnotation]) -> ChapterEditorAnnotationCounts {
        var openNotes = 0
        var openTKs = 0
        var resolved = 0
        for annotation in annotations {
            if annotation.resolvedAt != nil {
                resolved += 1
            } else if annotation.kind == .tk {
                openTKs += 1
            } else {
                openNotes += 1
            }
        }
        return ChapterEditorAnnotationCounts(
            openNoteCount: openNotes,
            openTKCount: openTKs,
            resolvedCount: resolved
        )
    }
}

/// Board-aligned copy constants and formatting helpers for Notes & Annotations
/// (`Editor-Notes.dc.html`, `Editor-Annotations.dc.html`).
nonisolated enum ChapterEditorAnnotationCopy {
    static let inThisChapterSectionTitle = "In this chapter"
    static let emptyChapterNotesTitle = "No Notes in This Chapter"
    static let newNoteButtonTitle = "New Note"

    /// Header line inside the annotation detail sheet (`Editor-Annotations.dc.html`:
    /// `"Your note · Nov 24"`, plus `"· Paragraph N"` when located).
    static func detailHeaderLabel(
        kind: WritingAnnotationKind,
        isResolved: Bool,
        dateText: String,
        paragraphNumber: Int?
    ) -> String {
        let prefix: String
        if isResolved {
            prefix = "Resolved"
        } else {
            prefix = kind == .tk ? "TK" : "Your note"
        }
        var parts = [prefix, dateText]
        if let paragraphNumber {
            parts.append("Paragraph \(paragraphNumber)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Ordered groups for the Notes sheet's `In Chapter` list (`Editor-Annotations.dc.html`).
nonisolated enum ChapterEditorAnnotationGroupKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case note
    case tk
    case resolved

    var id: String { rawValue }

    var sectionTitle: String {
        switch self {
        case .note: "Notes"
        case .tk: "TK Markers"
        case .resolved: "Resolved"
        }
    }

    var badgeTitle: String {
        switch self {
        case .note: "Note"
        case .tk: "TK"
        case .resolved: "Resolved"
        }
    }
}

/// Display model for one annotation row in the chapter annotations list.
nonisolated struct ChapterEditorAnnotationRow: Identifiable, Equatable, Sendable {
    let annotation: WritingAnnotation
    let group: ChapterEditorAnnotationGroupKind
    let paragraphNumber: Int?
    let isAnchorLost: Bool
    let resolvedDateText: String?

    var id: UUID { annotation.id }

    var displayText: String {
        let trimmed = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if annotation.kind == .tk { return "To come" }
        let quotePreview = ChapterEditorAnnotationAnchoring.plainQuotePreview(from: annotation.quote)
        return quotePreview.isEmpty ? "Note" : "“\(quotePreview)”"
    }

    /// Location line shown below the row text (e.g. `"Paragraph 2"` or `"Paragraph 1 · Nov 22"`).
    var locationText: String {
        var parts: [String] = []
        if let paragraphNumber {
            parts.append("Paragraph \(paragraphNumber)")
        } else if isAnchorLost {
            parts.append("Anchor not found")
        }
        if let resolvedDateText, !resolvedDateText.isEmpty {
            parts.append(resolvedDateText)
        }
        return parts.isEmpty ? "In this chapter" : parts.joined(separator: " · ")
    }

    var accessibilityLabel: String {
        "\(group.badgeTitle): \(displayText), \(locationText)"
    }
}

/// One non-empty section in the chapter annotations list.
nonisolated struct ChapterEditorAnnotationGroup: Identifiable, Equatable, Sendable {
    let kind: ChapterEditorAnnotationGroupKind
    let rows: [ChapterEditorAnnotationRow]

    var id: ChapterEditorAnnotationGroupKind { kind }
}

/// Groups a chapter's annotations into Note, TK, and Resolved sections with `"Paragraph N"` labels.
nonisolated enum ChapterEditorAnnotationListBuilder {
    static func shortDateString(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func groups(
        from annotations: [WritingAnnotation],
        in bodyHTML: String,
        lostIDs: Set<UUID> = [],
        formatDate: (Date) -> String = Self.shortDateString
    ) -> [ChapterEditorAnnotationGroup] {
        var noteRows: [ChapterEditorAnnotationRow] = []
        var tkRows: [ChapterEditorAnnotationRow] = []
        var resolvedRows: [ChapterEditorAnnotationRow] = []

        for annotation in annotations {
            let row = makeRow(
                for: annotation,
                in: bodyHTML,
                isLost: lostIDs.contains(annotation.id),
                formatDate: formatDate
            )
            switch row.group {
            case .note: noteRows.append(row)
            case .tk: tkRows.append(row)
            case .resolved: resolvedRows.append(row)
            }
        }

        noteRows.sort(by: openOrder)
        tkRows.sort(by: openOrder)
        resolvedRows.sort(by: resolvedOrder)

        var built: [ChapterEditorAnnotationGroup] = []
        if !noteRows.isEmpty {
            built.append(ChapterEditorAnnotationGroup(kind: .note, rows: noteRows))
        }
        if !tkRows.isEmpty {
            built.append(ChapterEditorAnnotationGroup(kind: .tk, rows: tkRows))
        }
        if !resolvedRows.isEmpty {
            built.append(ChapterEditorAnnotationGroup(kind: .resolved, rows: resolvedRows))
        }
        return built
    }

    /// Flat list in Note → TK → Resolved order for the unified `"In this chapter"` card
    /// (`Editor-Annotations.dc.html`).
    static func flatRows(
        from annotations: [WritingAnnotation],
        in bodyHTML: String,
        lostIDs: Set<UUID> = [],
        formatDate: (Date) -> String = Self.shortDateString
    ) -> [ChapterEditorAnnotationRow] {
        groups(
            from: annotations,
            in: bodyHTML,
            lostIDs: lostIDs,
            formatDate: formatDate
        ).flatMap(\.rows)
    }

    private static func makeRow(
        for annotation: WritingAnnotation,
        in bodyHTML: String,
        isLost: Bool,
        formatDate: (Date) -> String
    ) -> ChapterEditorAnnotationRow {
        let paragraph: Int? = isLost
            ? nil
            : ChapterEditorAnnotationAnchoring.paragraphNumber(
                atUTF16Offset: annotation.utf16Offset,
                in: bodyHTML
            )
        if let resolvedAt = annotation.resolvedAt {
            return ChapterEditorAnnotationRow(
                annotation: annotation,
                group: .resolved,
                paragraphNumber: paragraph,
                isAnchorLost: isLost,
                resolvedDateText: formatDate(resolvedAt)
            )
        }
        return ChapterEditorAnnotationRow(
            annotation: annotation,
            group: annotation.kind == .tk ? .tk : .note,
            paragraphNumber: paragraph,
            isAnchorLost: isLost,
            resolvedDateText: nil
        )
    }

    private static func openOrder(
        _ lhs: ChapterEditorAnnotationRow,
        _ rhs: ChapterEditorAnnotationRow
    ) -> Bool {
        if lhs.annotation.utf16Offset != rhs.annotation.utf16Offset {
            return lhs.annotation.utf16Offset < rhs.annotation.utf16Offset
        }
        if lhs.annotation.createdAt != rhs.annotation.createdAt {
            return lhs.annotation.createdAt < rhs.annotation.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func resolvedOrder(
        _ lhs: ChapterEditorAnnotationRow,
        _ rhs: ChapterEditorAnnotationRow
    ) -> Bool {
        let lhsDate = lhs.annotation.resolvedAt ?? lhs.annotation.updatedAt
        let rhsDate = rhs.annotation.resolvedAt ?? rhs.annotation.updatedAt
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return openOrder(lhs, rhs)
    }
}

/// Tracks `DraftSession.lastTypedTK` sequence numbers so each typed TK prompts once.
nonisolated struct ChapterEditorTKTracker: Equatable, Sendable {
    private(set) var lastSeenSequence: Int?
    private(set) var activeTK: DraftTypedTK?

    @discardableResult
    mutating func receive(_ typedTK: DraftTypedTK?) -> Bool {
        guard let typedTK, typedTK.sequence != lastSeenSequence else { return false }
        lastSeenSequence = typedTK.sequence
        activeTK = typedTK
        return true
    }

    mutating func dismiss() {
        activeTK = nil
    }
}

/// Tracks `DraftSession.lastAnnotationTap` sequence numbers so each highlight tap opens once.
nonisolated struct ChapterEditorAnnotationTapTracker: Equatable, Sendable {
    private(set) var lastSeenSequence: Int?

    mutating func receive(_ tap: DraftAnnotationTap?) -> String? {
        guard let tap, tap.sequence != lastSeenSequence else { return nil }
        lastSeenSequence = tap.sequence
        return tap.id
    }
}
