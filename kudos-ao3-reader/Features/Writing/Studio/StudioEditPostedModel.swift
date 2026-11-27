import Foundation

// MARK: - Posted chapter comparison model (`Studio-Edit-Posted`)

/// Explains what the "Changes" view is comparing against.
/// Kudos does not persist a separate posted-body copy on disk yet:
/// when opened from AO3's posted chapter form, the initial snapshot is the live posted
/// text AO3 served; otherwise only local edits since opening the editor are known.
nonisolated enum StudioPostedBaselineSource: Equatable, Hashable, Sendable {
    case loadedFromAO3
    case editorSessionStart
}

nonisolated struct StudioPostedChapterSnapshot: Equatable, Hashable, Sendable {
    var title: String
    var summary: String
    var notesBefore: String
    var notesAfter: String
    var bodyHTML: String
}

nonisolated enum StudioPostedTextSpanKind: Equatable, Hashable, Sendable {
    case unchanged
    case deleted
    case inserted
}

nonisolated struct StudioPostedTextSpan: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let kind: StudioPostedTextSpanKind
    let text: String
}

nonisolated enum StudioPostedParagraphDiffKind: Equatable, Hashable, Sendable {
    case unchanged
    case modified
    case deleted
    case inserted
}

nonisolated struct StudioPostedParagraphDiff: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let kind: StudioPostedParagraphDiffKind
    let spans: [StudioPostedTextSpan]

    var accessibilityLabel: String {
        switch kind {
        case .unchanged:
            return spans.map(\.text).joined()
        case .deleted:
            return "Removed paragraph: \(spans.map(\.text).joined())"
        case .inserted:
            return "Added paragraph: \(spans.map(\.text).joined())"
        case .modified:
            var parts: [String] = []
            for span in spans {
                let trimmed = span.text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                switch span.kind {
                case .unchanged: parts.append(trimmed)
                case .deleted: parts.append("Removed: \(trimmed)")
                case .inserted: parts.append("Added: \(trimmed)")
                }
            }
            return "Changed paragraph. \(parts.joined(separator: ". "))"
        }
    }
}

nonisolated struct StudioPostedFieldDiff: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let label: String
    let before: String
    let after: String
}

/// Pure, testable diff between a posted chapter's baseline and the current local edits.
nonisolated struct StudioPostedChapterDiff: Equatable, Sendable {
    let baselineSource: StudioPostedBaselineSource
    let paragraphs: [StudioPostedParagraphDiff]
    let paragraphsChanged: Int
    let wordDelta: Int
    let titleChanged: Bool
    let summaryChanged: Bool
    let notesBeforeChanged: Bool
    let notesAfterChanged: Bool
    let metadataDiffs: [StudioPostedFieldDiff]

    var notesChanged: Bool { notesBeforeChanged || notesAfterChanged }

    var hasAnyChanges: Bool {
        paragraphsChanged > 0
            || wordDelta != 0
            || titleChanged
            || summaryChanged
            || notesChanged
    }

    /// Footer summary matching `Studio-Edit-Posted.dc.html`:
    /// e.g. `"1 paragraph changed · +9 words · notes and title unchanged"`.
    var summaryLine: String {
        guard hasAnyChanges else {
            switch baselineSource {
            case .loadedFromAO3:
                return "No changes since posted"
            case .editorSessionStart:
                return "No local changes since opening"
            }
        }

        var parts: [String] = []
        if paragraphsChanged == 0 {
            parts.append("No paragraphs changed")
        } else if paragraphsChanged == 1 {
            parts.append("1 paragraph changed")
        } else {
            parts.append("\(paragraphsChanged.formatted()) paragraphs changed")
        }

        if wordDelta > 0 {
            let unit = wordDelta == 1 ? "word" : "words"
            parts.append("+\(wordDelta.formatted()) \(unit)")
        } else if wordDelta < 0 {
            let absDelta = abs(wordDelta)
            let unit = absDelta == 1 ? "word" : "words"
            parts.append("-\(absDelta.formatted()) \(unit)")
        } else if paragraphsChanged > 0 {
            parts.append("0 words")
        }

        parts.append(metadataClause)
        return parts.joined(separator: " · ")
    }

    var accessibilitySummary: String {
        summaryLine
            .replacingOccurrences(of: " · ", with: ", ")
            .replacingOccurrences(of: "+", with: "plus ")
    }

    private var metadataClause: String {
        var changed: [String] = []
        if notesChanged { changed.append("notes") }
        if titleChanged { changed.append("title") }
        if summaryChanged { changed.append("summary") }

        if changed.isEmpty {
            return "notes and title unchanged"
        }
        var unchanged: [String] = []
        if !notesChanged { unchanged.append("notes") }
        if !titleChanged { unchanged.append("title") }

        let changedText = "\(Self.joinNames(changed)) changed"
        if unchanged.isEmpty {
            return changedText
        }
        return "\(changedText) · \(Self.joinNames(unchanged)) unchanged"
    }

    private static func joinNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            return "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])"
        }
    }
}

// MARK: - Comparison engine

nonisolated extension StudioPostedChapterDiff {
    static func compare(
        posted: StudioPostedChapterSnapshot,
        current: StudioPostedChapterSnapshot,
        baselineSource: StudioPostedBaselineSource = .loadedFromAO3
    ) -> StudioPostedChapterDiff {
        let oldParagraphs = BetaHTMLDocument.parse(posted.bodyHTML).map(\.plainText)
        let newParagraphs = BetaHTMLDocument.parse(current.bodyHTML).map(\.plainText)
        let diffParagraphs = diffParagraphLists(old: oldParagraphs, new: newParagraphs)
        let changedCount = diffParagraphs.reduce(0) { $0 + ($1.kind == .unchanged ? 0 : 1) }
        let wordDelta = AO3WordCounter.count(current.bodyHTML) - AO3WordCounter.count(posted.bodyHTML)

        let titleChanged = posted.title != current.title
        let summaryChanged = posted.summary != current.summary
        let notesBeforeChanged = posted.notesBefore != current.notesBefore
        let notesAfterChanged = posted.notesAfter != current.notesAfter
        let metadataDiffs = buildMetadataDiffs(posted: posted, current: current)

        return StudioPostedChapterDiff(
            baselineSource: baselineSource,
            paragraphs: diffParagraphs,
            paragraphsChanged: changedCount,
            wordDelta: wordDelta,
            titleChanged: titleChanged,
            summaryChanged: summaryChanged,
            notesBeforeChanged: notesBeforeChanged,
            notesAfterChanged: notesAfterChanged,
            metadataDiffs: metadataDiffs
        )
    }

    private static func buildMetadataDiffs(
        posted: StudioPostedChapterSnapshot,
        current: StudioPostedChapterSnapshot
    ) -> [StudioPostedFieldDiff] {
        var diffs: [StudioPostedFieldDiff] = []
        if posted.title != current.title {
            diffs.append(
                StudioPostedFieldDiff(id: "title", label: "Chapter title", before: posted.title, after: current.title)
            )
        }
        if posted.summary != current.summary {
            diffs.append(
                StudioPostedFieldDiff(id: "summary", label: "Summary", before: posted.summary, after: current.summary)
            )
        }
        if posted.notesBefore != current.notesBefore {
            diffs.append(
                StudioPostedFieldDiff(
                    id: "notesBefore",
                    label: "Notes before",
                    before: posted.notesBefore,
                    after: current.notesBefore
                )
            )
        }
        if posted.notesAfter != current.notesAfter {
            diffs.append(
                StudioPostedFieldDiff(
                    id: "notesAfter",
                    label: "Notes after",
                    before: posted.notesAfter,
                    after: current.notesAfter
                )
            )
        }
        return diffs
    }

    private struct AlignedPair {
        let oldIndex: Int
        let newIndex: Int
    }

    private static func diffParagraphLists(old: [String], new: [String]) -> [StudioPostedParagraphDiff] {
        let oldNorm = old.map { BetaComparisonEngine.normalizeForComparison($0) }
        let newNorm = new.map { BetaComparisonEngine.normalizeForComparison($0) }
        let exactDiff = newNorm.difference(from: oldNorm)

        var removedIndices: Set<Int> = []
        var insertedIndices: Set<Int> = []
        for change in exactDiff {
            switch change {
            case let .remove(offset, _, _): removedIndices.insert(offset)
            case let .insert(offset, _, _): insertedIndices.insert(offset)
            }
        }

        var anchors: [AlignedPair] = []
        var oldIdx = 0
        var newIdx = 0
        while oldIdx < old.count, newIdx < new.count {
            if removedIndices.contains(oldIdx) {
                oldIdx += 1
            } else if insertedIndices.contains(newIdx) {
                newIdx += 1
            } else {
                anchors.append(AlignedPair(oldIndex: oldIdx, newIndex: newIdx))
                oldIdx += 1
                newIdx += 1
            }
        }

        var output: [StudioPostedParagraphDiff] = []
        var nextID = 0
        var prevOld = 0
        var prevNew = 0

        for anchor in anchors {
            emitGap(
                old: old,
                oldRange: prevOld ..< anchor.oldIndex,
                new: new,
                newRange: prevNew ..< anchor.newIndex,
                into: &output,
                nextID: &nextID
            )
            appendSingleParagraph(new[anchor.newIndex], kind: .unchanged, into: &output, nextID: &nextID)
            prevOld = anchor.oldIndex + 1
            prevNew = anchor.newIndex + 1
        }
        emitGap(
            old: old,
            oldRange: prevOld ..< old.count,
            new: new,
            newRange: prevNew ..< new.count,
            into: &output,
            nextID: &nextID
        )
        return output
    }

    private static func appendSingleParagraph(
        _ text: String,
        kind: StudioPostedParagraphDiffKind,
        into output: inout [StudioPostedParagraphDiff],
        nextID: inout Int
    ) {
        let spanKind: StudioPostedTextSpanKind
        switch kind {
        case .unchanged, .modified: spanKind = .unchanged
        case .deleted: spanKind = .deleted
        case .inserted: spanKind = .inserted
        }
        output.append(
            StudioPostedParagraphDiff(
                id: nextID,
                kind: kind,
                spans: [StudioPostedTextSpan(id: 0, kind: spanKind, text: text)]
            )
        )
        nextID += 1
    }

    private static func emitGap(
        old: [String],
        oldRange: Range<Int>,
        new: [String],
        newRange: Range<Int>,
        into output: inout [StudioPostedParagraphDiff],
        nextID: inout Int
    ) {
        guard !oldRange.isEmpty || !newRange.isEmpty else { return }

        if oldRange.isEmpty {
            for idx in newRange {
                appendSingleParagraph(new[idx], kind: .inserted, into: &output, nextID: &nextID)
            }
            return
        }
        if newRange.isEmpty {
            for idx in oldRange {
                appendSingleParagraph(old[idx], kind: .deleted, into: &output, nextID: &nextID)
            }
            return
        }

        let pairs = pairGapBySimilarity(old: old, oldRange: oldRange, new: new, newRange: newRange)
        var oldCursor = oldRange.lowerBound
        var newCursor = newRange.lowerBound

        for pair in pairs {
            while oldCursor < pair.oldIndex {
                appendSingleParagraph(old[oldCursor], kind: .deleted, into: &output, nextID: &nextID)
                oldCursor += 1
            }
            while newCursor < pair.newIndex {
                appendSingleParagraph(new[newCursor], kind: .inserted, into: &output, nextID: &nextID)
                newCursor += 1
            }
            let spans = diffParagraphWords(old: old[pair.oldIndex], new: new[pair.newIndex])
            output.append(StudioPostedParagraphDiff(id: nextID, kind: .modified, spans: spans))
            nextID += 1
            oldCursor = pair.oldIndex + 1
            newCursor = pair.newIndex + 1
        }

        while oldCursor < oldRange.upperBound {
            appendSingleParagraph(old[oldCursor], kind: .deleted, into: &output, nextID: &nextID)
            oldCursor += 1
        }
        while newCursor < newRange.upperBound {
            appendSingleParagraph(new[newCursor], kind: .inserted, into: &output, nextID: &nextID)
            newCursor += 1
        }
    }

    private static func pairGapBySimilarity(
        old: [String],
        oldRange: Range<Int>,
        new: [String],
        newRange: Range<Int>
    ) -> [AlignedPair] {
        let rows = oldRange.count
        let cols = newRange.count
        let threshold = (rows == 1 && cols == 1) ? 0.2 : 0.35

        if rows * cols > 10_000 {
            let count = min(rows, cols)
            return (0 ..< count).map { offset in
                AlignedPair(oldIndex: oldRange.lowerBound + offset, newIndex: newRange.lowerBound + offset)
            }
        }

        let oldBags = oldRange.map { wordBag(old[$0]) }
        let newBags = newRange.map { wordBag(new[$0]) }
        var score = Array(repeating: Array(repeating: 0.0, count: cols + 1), count: rows + 1)
        var take = Array(repeating: Array(repeating: false, count: cols), count: rows)

        for row in stride(from: rows - 1, through: 0, by: -1) {
            for col in stride(from: cols - 1, through: 0, by: -1) {
                let sim = diceSimilarity(oldBags[row], newBags[col])
                var best = max(score[row + 1][col], score[row][col + 1])
                if sim >= threshold, sim + score[row + 1][col + 1] > best {
                    best = sim + score[row + 1][col + 1]
                    take[row][col] = true
                }
                score[row][col] = best
            }
        }

        var result: [AlignedPair] = []
        var row = 0
        var col = 0
        while row < rows, col < cols {
            if take[row][col] {
                result.append(
                    AlignedPair(oldIndex: oldRange.lowerBound + row, newIndex: newRange.lowerBound + col)
                )
                row += 1
                col += 1
            } else if score[row + 1][col] >= score[row][col + 1] {
                row += 1
            } else {
                col += 1
            }
        }
        return result
    }

    private struct WordToken {
        let text: String
        let key: String
    }

    private static func diffParagraphWords(old: String, new: String) -> [StudioPostedTextSpan] {
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)
        let diff = newTokens.map(\.key).difference(from: oldTokens.map(\.key))

        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in diff {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }

        var rawSpans: [(kind: StudioPostedTextSpanKind, text: String)] = []
        var oldIdx = 0
        var newIdx = 0
        while oldIdx < oldTokens.count || newIdx < newTokens.count {
            if oldIdx < oldTokens.count, removed.contains(oldIdx) {
                rawSpans.append((.deleted, oldTokens[oldIdx].text))
                oldIdx += 1
            } else if newIdx < newTokens.count, inserted.contains(newIdx) {
                rawSpans.append((.inserted, newTokens[newIdx].text))
                newIdx += 1
            } else if oldIdx < oldTokens.count, newIdx < newTokens.count {
                rawSpans.append((.unchanged, newTokens[newIdx].text))
                oldIdx += 1
                newIdx += 1
            } else if oldIdx < oldTokens.count {
                rawSpans.append((.deleted, oldTokens[oldIdx].text))
                oldIdx += 1
            } else {
                rawSpans.append((.inserted, newTokens[newIdx].text))
                newIdx += 1
            }
        }

        var merged: [StudioPostedTextSpan] = []
        for item in rawSpans {
            if let last = merged.last, last.kind == item.kind {
                merged[merged.count - 1] = StudioPostedTextSpan(
                    id: last.id,
                    kind: last.kind,
                    text: last.text + item.text
                )
            } else {
                merged.append(StudioPostedTextSpan(id: merged.count, kind: item.kind, text: item.text))
            }
        }
        return merged
    }

    private static func tokenize(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var index = text.startIndex
        while index < text.endIndex {
            let start = index
            let ch = text[index]
            if ch.isWhitespace {
                while index < text.endIndex, text[index].isWhitespace {
                    index = text.index(after: index)
                }
            } else if BetaComparisonEngine.isCJKIdeographOrKana(ch) {
                index = text.index(after: index)
            } else if isWordChar(ch) {
                while index < text.endIndex,
                      isWordChar(text[index]),
                      !BetaComparisonEngine.isCJKIdeographOrKana(text[index]) {
                    index = text.index(after: index)
                }
            } else {
                index = text.index(after: index)
            }
            let slice = String(text[start ..< index])
            tokens.append(
                WordToken(
                    text: slice,
                    key: BetaComparisonEngine.normalizeForComparison(slice)
                )
            )
        }
        return tokens
    }

    private static func isWordChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "'" || ch == "’" || ch == "‘"
    }

    private static func wordBag(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for token in tokenize(text.lowercased()) {
            let trimmed = token.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                counts[trimmed, default: 0] += 1
            }
        }
        return counts
    }

    private static func diceSimilarity(_ lhs: [String: Int], _ rhs: [String: Int]) -> Double {
        let lhsTotal = lhs.values.reduce(0, +)
        let rhsTotal = rhs.values.reduce(0, +)
        guard lhsTotal > 0, rhsTotal > 0 else { return 0 }
        var overlap = 0
        for (key, count) in lhs {
            if let other = rhs[key] {
                overlap += min(count, other)
            }
        }
        return Double(2 * overlap) / Double(lhsTotal + rhsTotal)
    }
}
