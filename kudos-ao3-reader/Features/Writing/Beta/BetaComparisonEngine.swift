import Foundation

// MARK: - Comparison engine (paragraph alignment & entry points)

nonisolated enum BetaComparisonEngine {
    struct ComparisonResult: Equatable, Sendable {
        var suggestions: [BetaSuggestionItem]
        var comments: [BetaCommentItem]
    }

    struct ParagraphAlignmentPair: Equatable, Sendable {
        let sentIndex: Int
        let returnedIndex: Int
    }

    struct SentParagraphContext {
        let utf16Offset: Int
        let prefix: String
        let suffix: String
    }

    enum SentParagraphContexts {
        static func build(from paragraphs: [String]) -> [SentParagraphContext] {
            let joined = paragraphs.joined(separator: "\n")
            var contexts: [SentParagraphContext] = []
            contexts.reserveCapacity(paragraphs.count)
            var cursor = 0
            for (index, paragraph) in paragraphs.enumerated() {
                let len = paragraph.utf16.count
                let prefix = BetaComparisonEngine.sliceUTF16Prefix(
                    in: joined,
                    before: cursor,
                    maxChars: WritingAnnotationReanchor.contextLimit
                )
                let suffix = BetaComparisonEngine.sliceUTF16Suffix(
                    in: joined,
                    after: cursor + len,
                    maxChars: WritingAnnotationReanchor.contextLimit
                )
                contexts.append(SentParagraphContext(utf16Offset: cursor, prefix: prefix, suffix: suffix))
                cursor += len + (index + 1 < paragraphs.count ? 1 : 0)
            }
            return contexts
        }
    }

    struct RawSuggestion {
        var startUTF16: Int
        var endUTF16: Int
        var deletedText: String
        var insertedText: String
        var author: String
        var date: Date?
        var isTracked: Bool
    }

    /// Compares a beta's returned `.docx` against the exact HTML originally sent.
    static func compare(
        sentHTML: String,
        returned: BetaDOCXDocument,
        betaName: String
    ) -> ComparisonResult {
        let sentParagraphs = BetaHTMLDocument.parse(sentHTML).map(\.plainText)
        let sentContext = SentParagraphContexts.build(from: sentParagraphs)

        let commentedReturnedIndices = Set(returned.comments.map(\.paragraphIndex))
        var activeReturned: [(originalIndex: Int, paragraph: BetaDOCXParagraph)] = []
        for (idx, paragraph) in returned.paragraphs.enumerated() {
            let hasContent = !paragraph.baselineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !paragraph.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || paragraph.hasTrackedChanges
                || commentedReturnedIndices.contains(idx)
            if hasContent {
                activeReturned.append((originalIndex: idx, paragraph: paragraph))
            }
        }

        let alignment = alignParagraphs(
            sent: sentParagraphs,
            returned: activeReturned.map(\.paragraph)
        )
        let sentIndexByReturnedOriginal = buildReturnedIndexMap(
            activeReturned: activeReturned,
            alignment: alignment,
            sentCount: sentParagraphs.count
        )

        var suggestions = collectAlignedSuggestions(
            sentParagraphs: sentParagraphs,
            sentContext: sentContext,
            activeReturned: activeReturned,
            alignment: alignment,
            betaName: betaName
        )
        suggestions.append(
            contentsOf: collectUnpairedParagraphSuggestions(
                sentParagraphs: sentParagraphs,
                sentContext: sentContext,
                activeReturned: activeReturned,
                alignment: alignment,
                betaName: betaName
            )
        )
        suggestions.sort { lhs, rhs in
            if lhs.paragraphIndex != rhs.paragraphIndex {
                return lhs.paragraphIndex < rhs.paragraphIndex
            }
            if lhs.editStartUTF16 != rhs.editStartUTF16 {
                return lhs.editStartUTF16 < rhs.editStartUTF16
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let comments: [BetaCommentItem] = returned.comments.map { comment in
            BetaCommentItem(
                sourceCommentID: comment.id,
                author: comment.author ?? betaName,
                date: comment.date,
                quote: comment.quote,
                text: comment.text,
                paragraphIndex: sentIndexByReturnedOriginal[comment.paragraphIndex] ?? 0,
                characterOffsetUTF16: max(0, comment.baselineStartUTF16)
            )
        }
        return ComparisonResult(suggestions: suggestions, comments: comments)
    }

    // MARK: - Paragraph alignment (exact LCS + gap similarity DP)

    static func alignParagraphs(
        sent: [String],
        returned: [BetaDOCXParagraph]
    ) -> [ParagraphAlignmentPair] {
        let sentNorm = sent.map(normalizeForComparison)
        let retNorm = returned.map { normalizeForComparison($0.baselineText) }

        let exactPairs = exactLCSPairs(sent: sentNorm, returned: retNorm)
        var result: [ParagraphAlignmentPair] = []
        var prevSent = 0
        var prevRet = 0

        for anchor in exactPairs {
            if prevSent < anchor.sentIndex, prevRet < anchor.returnedIndex {
                result.append(
                    contentsOf: matchGapBySimilarity(
                        sent: sentNorm,
                        sentRange: prevSent ..< anchor.sentIndex,
                        returned: retNorm,
                        returnedRange: prevRet ..< anchor.returnedIndex
                    )
                )
            }
            result.append(anchor)
            prevSent = anchor.sentIndex + 1
            prevRet = anchor.returnedIndex + 1
        }
        if prevSent < sentNorm.count, prevRet < retNorm.count {
            result.append(
                contentsOf: matchGapBySimilarity(
                    sent: sentNorm,
                    sentRange: prevSent ..< sentNorm.count,
                    returned: retNorm,
                    returnedRange: prevRet ..< retNorm.count
                )
            )
        }
        return result
    }

    private static func exactLCSPairs(
        sent: [String],
        returned: [String]
    ) -> [ParagraphAlignmentPair] {
        var prefixLen = 0
        while prefixLen < sent.count,
              prefixLen < returned.count,
              sent[prefixLen] == returned[prefixLen] {
            prefixLen += 1
        }
        var sentEnd = sent.count
        var retEnd = returned.count
        while sentEnd > prefixLen,
              retEnd > prefixLen,
              sent[sentEnd - 1] == returned[retEnd - 1] {
            sentEnd -= 1
            retEnd -= 1
        }

        var pairs: [ParagraphAlignmentPair] = (0 ..< prefixLen).map {
            ParagraphAlignmentPair(sentIndex: $0, returnedIndex: $0)
        }
        if sentEnd > prefixLen, retEnd > prefixLen {
            pairs.append(
                contentsOf: runExactLCS(
                    sent: Array(sent[prefixLen ..< sentEnd]),
                    returned: Array(returned[prefixLen ..< retEnd]),
                    sentOffset: prefixLen,
                    returnedOffset: prefixLen
                )
            )
        }
        for offset in 0 ..< (sent.count - sentEnd) {
            pairs.append(
                ParagraphAlignmentPair(sentIndex: sentEnd + offset, returnedIndex: retEnd + offset)
            )
        }
        return pairs
    }

    private static func runExactLCS(
        sent: [String],
        returned: [String],
        sentOffset: Int,
        returnedOffset: Int
    ) -> [ParagraphAlignmentPair] {
        let rows = sent.count
        let cols = returned.count
        var table = Array(repeating: Array(repeating: 0, count: cols + 1), count: rows + 1)
        for row in stride(from: rows - 1, through: 0, by: -1) {
            for col in stride(from: cols - 1, through: 0, by: -1) {
                if sent[row] == returned[col] {
                    table[row][col] = table[row + 1][col + 1] + 1
                } else {
                    table[row][col] = max(table[row + 1][col], table[row][col + 1])
                }
            }
        }
        var matched: [ParagraphAlignmentPair] = []
        var row = 0
        var col = 0
        while row < rows, col < cols {
            if sent[row] == returned[col] {
                matched.append(
                    ParagraphAlignmentPair(
                        sentIndex: sentOffset + row,
                        returnedIndex: returnedOffset + col
                    )
                )
                row += 1
                col += 1
            } else if table[row + 1][col] >= table[row][col + 1] {
                row += 1
            } else {
                col += 1
            }
        }
        return matched
    }

    private static func matchGapBySimilarity(
        sent: [String],
        sentRange: Range<Int>,
        returned: [String],
        returnedRange: Range<Int>
    ) -> [ParagraphAlignmentPair] {
        let sentCount = sentRange.count
        let retCount = returnedRange.count
        let threshold = (sentCount == 1 && retCount == 1) ? 0.25 : 0.35

        let sentBags = sentRange.map { wordBag(sent[$0]) }
        let retBags = returnedRange.map { wordBag(returned[$0]) }

        var score = Array(repeating: Array(repeating: 0.0, count: retCount + 1), count: sentCount + 1)
        var take = Array(repeating: Array(repeating: false, count: retCount), count: sentCount)

        for row in stride(from: sentCount - 1, through: 0, by: -1) {
            for col in stride(from: retCount - 1, through: 0, by: -1) {
                let sim = diceSimilarity(sentBags[row], retBags[col])
                var best = max(score[row + 1][col], score[row][col + 1])
                if sim >= threshold, sim + score[row + 1][col + 1] > best {
                    best = sim + score[row + 1][col + 1]
                    take[row][col] = true
                }
                score[row][col] = best
            }
        }

        var matched: [ParagraphAlignmentPair] = []
        var row = 0
        var col = 0
        while row < sentCount, col < retCount {
            if take[row][col] {
                matched.append(
                    ParagraphAlignmentPair(
                        sentIndex: sentRange.lowerBound + row,
                        returnedIndex: returnedRange.lowerBound + col
                    )
                )
                row += 1
                col += 1
            } else if score[row + 1][col] >= score[row][col + 1] {
                row += 1
            } else {
                col += 1
            }
        }
        return matched
    }

    private static func wordBag(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        var currentWord = ""
        func flushWord() {
            guard !currentWord.isEmpty else { return }
            counts[currentWord, default: 0] += 1
            currentWord.removeAll(keepingCapacity: true)
        }
        for character in text.lowercased() {
            if isCJKIdeographOrKana(character) {
                flushWord()
                counts[String(character), default: 0] += 1
            } else if character.isLetter || character.isNumber {
                currentWord.append(character)
            } else {
                flushWord()
            }
        }
        flushWord()
        return counts
    }

    private static func diceSimilarity(_ lhs: [String: Int], _ rhs: [String: Int]) -> Double {
        let lhsTotal = lhs.values.reduce(0, +)
        let rhsTotal = rhs.values.reduce(0, +)
        guard lhsTotal > 0, rhsTotal > 0 else { return 0 }
        var overlap = 0
        for (word, count) in lhs {
            if let other = rhs[word] {
                overlap += min(count, other)
            }
        }
        return Double(2 * overlap) / Double(lhsTotal + rhsTotal)
    }

    // MARK: - Shared helpers

    /// Folds NBSP and curly apostrophes/quotes into ASCII equivalents 1-to-1 in UTF-16 so
    /// Word/Google Docs smart-quote curling does not manufacture diffs while preserving all offsets.
    static func normalizeForComparison(_ text: String) -> String {
        var needsNormalization = false
        for unit in text.utf16 {
            if unit == 0x00A0 || unit == 0x2018 || unit == 0x2019 || unit == 0x201C || unit == 0x201D {
                needsNormalization = true
                break
            }
        }
        guard needsNormalization else { return text }
        var units = Array(text.utf16)
        for idx in units.indices {
            switch units[idx] {
            case 0x00A0: units[idx] = 0x0020
            case 0x2018, 0x2019: units[idx] = 0x0027
            case 0x201C, 0x201D: units[idx] = 0x0022
            default: break
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    static func isCJKIdeographOrKana(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040 ... 0x309F, // Hiragana
             0x30A0 ... 0x30FF, // Katakana
             0x31F0 ... 0x31FF, // Katakana Phonetic Extensions
             0x3400 ... 0x4DBF, // CJK Unified Ideographs Extension A
             0x4E00 ... 0x9FFF, // CJK Unified Ideographs
             0xF900 ... 0xFAFF, // CJK Compatibility Ideographs
             0xFF66 ... 0xFF9F, // Halfwidth Katakana
             0x20000 ... 0x2FA1F: // CJK Extensions B–F & Compatibility Supplement
            return true
        default:
            return false
        }
    }

    static func firstTrackedAuthor(in paragraph: BetaDOCXParagraph) -> String? {
        for segment in paragraph.segments {
            switch segment.kind {
            case let .insertion(author, _, _), let .deletion(author, _, _):
                if let author, !author.isEmpty { return author }
            case .unchanged:
                continue
            }
        }
        return nil
    }

    static func buildReturnedIndexMap(
        activeReturned: [(originalIndex: Int, paragraph: BetaDOCXParagraph)],
        alignment: [ParagraphAlignmentPair],
        sentCount: Int
    ) -> [Int: Int] {
        var map: [Int: Int] = [:]
        var alignedByFiltered: [Int: Int] = [:]
        for pair in alignment {
            alignedByFiltered[pair.returnedIndex] = pair.sentIndex
        }
        for (filteredIdx, item) in activeReturned.enumerated() {
            if let sentIdx = alignedByFiltered[filteredIdx] {
                map[item.originalIndex] = sentIdx
            } else {
                map[item.originalIndex] = nearestSentIndex(
                    forReturnedFilteredIndex: filteredIdx,
                    alignment: alignment,
                    sentCount: sentCount
                )
            }
        }
        return map
    }

    static func nearestSentIndex(
        forReturnedFilteredIndex retIdx: Int,
        alignment: [ParagraphAlignmentPair],
        sentCount: Int
    ) -> Int {
        guard sentCount > 0 else { return 0 }
        if let preceding = alignment.last(where: { $0.returnedIndex < retIdx }) {
            return min(preceding.sentIndex + 1, sentCount - 1)
        }
        return 0
    }

    static func sliceUTF16Prefix(in text: String, before utf16Offset: Int, maxChars: Int) -> String {
        guard utf16Offset > 0, maxChars > 0 else { return "" }
        let clamped = min(utf16Offset, text.utf16.count)
        let utf16Idx = text.utf16.index(text.utf16.startIndex, offsetBy: clamped)
        guard let strIdx = String.Index(utf16Idx, within: text) else { return "" }
        return String(text[..<strIdx].suffix(maxChars))
    }

    static func sliceUTF16Suffix(in text: String, after utf16Offset: Int, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        let clamped = max(0, min(utf16Offset, text.utf16.count))
        let utf16Idx = text.utf16.index(text.utf16.startIndex, offsetBy: clamped)
        guard let strIdx = String.Index(utf16Idx, within: text) else { return "" }
        return String(text[strIdx...].prefix(maxChars))
    }

    static func sliceUTF16Range(in text: String, range: Range<Int>) -> String? {
        guard range.lowerBound >= 0,
              range.upperBound <= text.utf16.count,
              range.lowerBound <= range.upperBound
        else {
            return nil
        }
        let lower = text.utf16.index(text.utf16.startIndex, offsetBy: range.lowerBound)
        let upper = text.utf16.index(text.utf16.startIndex, offsetBy: range.upperBound)
        guard let start = String.Index(lower, within: text),
              let end = String.Index(upper, within: text)
        else { return nil }
        return String(text[start ..< end])
    }
}
