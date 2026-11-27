import Foundation

// MARK: - Suggestion extraction (tracked, untracked, and whole-paragraph changes)

nonisolated extension BetaComparisonEngine {
    static func collectAlignedSuggestions(
        sentParagraphs: [String],
        sentContext: [SentParagraphContext],
        activeReturned: [(originalIndex: Int, paragraph: BetaDOCXParagraph)],
        alignment: [ParagraphAlignmentPair],
        betaName: String
    ) -> [BetaSuggestionItem] {
        var suggestions: [BetaSuggestionItem] = []
        for pair in alignment {
            let extracted = extractParagraphSuggestions(
                sentIndex: pair.sentIndex,
                sentText: sentParagraphs[pair.sentIndex],
                context: sentContext[pair.sentIndex],
                returned: activeReturned[pair.returnedIndex].paragraph,
                betaName: betaName
            )
            suggestions.append(contentsOf: extracted)
        }
        return suggestions
    }

    static func collectUnpairedParagraphSuggestions(
        sentParagraphs: [String],
        sentContext: [SentParagraphContext],
        activeReturned: [(originalIndex: Int, paragraph: BetaDOCXParagraph)],
        alignment: [ParagraphAlignmentPair],
        betaName: String
    ) -> [BetaSuggestionItem] {
        let alignedSent = Set(alignment.map(\.sentIndex))
        let alignedReturned = Set(alignment.map(\.returnedIndex))
        var items: [BetaSuggestionItem] = []

        for sentIndex in sentParagraphs.indices where !alignedSent.contains(sentIndex) {
            let sentText = sentParagraphs[sentIndex]
            guard !sentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let ctx = sentContext[sentIndex]
            items.append(
                BetaSuggestionItem(
                    author: betaName,
                    isTracked: false,
                    paragraphIndex: sentIndex,
                    paragraphText: sentText,
                    paragraphPrefix: ctx.prefix,
                    paragraphSuffix: ctx.suffix,
                    paragraphUTF16Offset: ctx.utf16Offset,
                    editStartUTF16: 0,
                    editEndUTF16: sentText.utf16.count,
                    deletedText: sentText,
                    insertedText: "",
                    localPrefix: "",
                    localSuffix: ""
                )
            )
        }

        for retIdx in activeReturned.indices where !alignedReturned.contains(retIdx) {
            let paragraph = activeReturned[retIdx].paragraph
            let addedText = paragraph.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !addedText.isEmpty else { continue }
            let anchorSentIdx = nearestSentIndex(
                forReturnedFilteredIndex: retIdx,
                alignment: alignment,
                sentCount: sentParagraphs.count
            )
            items.append(
                BetaSuggestionItem(
                    author: firstTrackedAuthor(in: paragraph) ?? betaName,
                    isTracked: paragraph.hasTrackedChanges,
                    paragraphIndex: anchorSentIdx,
                    paragraphText: "",
                    paragraphPrefix: "",
                    paragraphSuffix: "",
                    paragraphUTF16Offset: 0,
                    editStartUTF16: 0,
                    editEndUTF16: 0,
                    deletedText: "",
                    insertedText: addedText,
                    localPrefix: "",
                    localSuffix: "",
                    isWholeParagraphAddition: true
                )
            )
        }
        return items
    }

    private static func extractParagraphSuggestions(
        sentIndex: Int,
        sentText: String,
        context: SentParagraphContext,
        returned: BetaDOCXParagraph,
        betaName: String
    ) -> [BetaSuggestionItem] {
        let baselineMatches = normalizeForComparison(returned.baselineText)
            == normalizeForComparison(sentText)
        let rawList: [RawSuggestion]

        if baselineMatches {
            rawList = extractTrackedSuggestions(from: returned.segments, defaultAuthor: betaName)
        } else if !returned.hasTrackedChanges {
            rawList = wordDiffSuggestions(from: sentText, to: returned.finalText, author: betaName)
        } else {
            rawList = extractMixedSuggestions(sentText: sentText, returned: returned, betaName: betaName)
        }

        return rawList.compactMap { raw in
            guard raw.deletedText != raw.insertedText else { return nil }
            let clampedStart = max(0, min(raw.startUTF16, sentText.utf16.count))
            let clampedEnd = max(clampedStart, min(raw.endUTF16, sentText.utf16.count))
            return BetaSuggestionItem(
                author: raw.author,
                date: raw.date,
                isTracked: raw.isTracked,
                paragraphIndex: sentIndex,
                paragraphText: sentText,
                paragraphPrefix: context.prefix,
                paragraphSuffix: context.suffix,
                paragraphUTF16Offset: context.utf16Offset,
                editStartUTF16: clampedStart,
                editEndUTF16: clampedEnd,
                deletedText: raw.deletedText,
                insertedText: raw.insertedText,
                localPrefix: sliceUTF16Prefix(
                    in: sentText,
                    before: clampedStart,
                    maxChars: WritingAnnotationReanchor.contextLimit
                ),
                localSuffix: sliceUTF16Suffix(
                    in: sentText,
                    after: clampedEnd,
                    maxChars: WritingAnnotationReanchor.contextLimit
                )
            )
        }
    }

    private static func extractTrackedSuggestions(
        from segments: [BetaDOCXSegment],
        defaultAuthor: String
    ) -> [RawSuggestion] {
        var results: [RawSuggestion] = []
        var baselineOffset = 0
        var index = 0

        while index < segments.count {
            let segment = segments[index]
            switch segment.kind {
            case .unchanged:
                baselineOffset += segment.text.utf16.count
                index += 1

            case let .deletion(delAuthor, delDate, _):
                let start = baselineOffset
                let deleted = segment.text
                baselineOffset += segment.text.utf16.count
                index += 1
                var inserted = ""
                var resolvedAuthor = delAuthor
                var resolvedDate = delDate

                while index < segments.count,
                      case let .insertion(insAuthor, insDate, _) = segments[index].kind,
                      resolvedAuthor == nil || insAuthor == nil || resolvedAuthor == insAuthor {
                    inserted.append(segments[index].text)
                    resolvedAuthor = resolvedAuthor ?? insAuthor
                    resolvedDate = resolvedDate ?? insDate
                    index += 1
                }
                results.append(
                    RawSuggestion(
                        startUTF16: start,
                        endUTF16: baselineOffset,
                        deletedText: deleted,
                        insertedText: inserted,
                        author: resolvedAuthor ?? defaultAuthor,
                        date: resolvedDate,
                        isTracked: true
                    )
                )

            case let .insertion(insAuthor, insDate, _):
                let start = baselineOffset
                let inserted = segment.text
                index += 1
                var deleted = ""
                var resolvedAuthor = insAuthor
                var resolvedDate = insDate

                while index < segments.count,
                      case let .deletion(delAuthor, delDate, _) = segments[index].kind,
                      resolvedAuthor == nil || delAuthor == nil || resolvedAuthor == delAuthor {
                    deleted.append(segments[index].text)
                    baselineOffset += segments[index].text.utf16.count
                    resolvedAuthor = resolvedAuthor ?? delAuthor
                    resolvedDate = resolvedDate ?? delDate
                    index += 1
                }
                results.append(
                    RawSuggestion(
                        startUTF16: start,
                        endUTF16: baselineOffset,
                        deletedText: deleted,
                        insertedText: inserted,
                        author: resolvedAuthor ?? defaultAuthor,
                        date: resolvedDate,
                        isTracked: true
                    )
                )
            }
        }
        return results
    }

    private static func extractMixedSuggestions(
        sentText: String,
        returned: BetaDOCXParagraph,
        betaName: String
    ) -> [RawSuggestion] {
        let tracked = extractTrackedSuggestions(from: returned.segments, defaultAuthor: betaName)
        let baselineEdits = wordDiffWithBaselineMapping(from: sentText, to: returned.baselineText)

        var mappedTracked: [RawSuggestion] = []
        for item in tracked {
            guard let mappedRange = mapRange(
                item.startUTF16 ..< item.endUTF16,
                throughUnchangedSpans: baselineEdits.unchangedSpans
            ) else {
                let fallbackAuthor = firstTrackedAuthor(in: returned) ?? betaName
                return wordDiffSuggestions(from: sentText, to: returned.finalText, author: fallbackAuthor)
            }
            var shifted = item
            shifted.startUTF16 = mappedRange.lowerBound
            shifted.endUTF16 = mappedRange.upperBound
            mappedTracked.append(shifted)
        }
        let untracked = baselineEdits.hunks.map { hunk in
            RawSuggestion(
                startUTF16: hunk.startUTF16,
                endUTF16: hunk.endUTF16,
                deletedText: hunk.deletedText,
                insertedText: hunk.insertedText,
                author: betaName,
                date: nil,
                isTracked: false
            )
        }
        return (untracked + mappedTracked).sorted { $0.startUTF16 < $1.startUTF16 }
    }
}

// MARK: - Word-by-word diff for untracked edits

nonisolated extension BetaComparisonEngine {
    private struct DiffToken: Equatable {
        let text: String
        let utf16Start: Int
        let utf16Length: Int
        let isWhitespace: Bool
    }

    private struct DiffHunk {
        let startUTF16: Int
        let endUTF16: Int
        let deletedText: String
        let insertedText: String
    }

    private struct UnchangedSpan {
        let sentStart: Int
        let baseStart: Int
        let length: Int
    }

    private struct TokenMatch {
        let sentIndex: Int
        let targetIndex: Int
    }

    private static func wordDiffSuggestions(
        from sent: String,
        to returned: String,
        author: String
    ) -> [RawSuggestion] {
        wordDiffWithBaselineMapping(from: sent, to: returned).hunks.map { hunk in
            RawSuggestion(
                startUTF16: hunk.startUTF16,
                endUTF16: hunk.endUTF16,
                deletedText: hunk.deletedText,
                insertedText: hunk.insertedText,
                author: author,
                date: nil,
                isTracked: false
            )
        }
    }

    private static func wordDiffWithBaselineMapping(
        from sent: String,
        to target: String
    ) -> (hunks: [DiffHunk], unchangedSpans: [UnchangedSpan]) {
        let sentTokens = tokenizeWords(sent)
        let targetTokens = tokenizeWords(target)
        let matches = tokenLCS(sent: sentTokens, target: targetTokens)

        var unchangedSpans: [UnchangedSpan] = []
        var rawHunks: [DiffHunk] = []
        var sentCursor = 0
        var targetCursor = 0

        for match in matches {
            if sentCursor < match.sentIndex || targetCursor < match.targetIndex {
                rawHunks.append(
                    makeHunk(
                        sentTokens: sentTokens,
                        sentRange: sentCursor ..< match.sentIndex,
                        targetTokens: targetTokens,
                        targetRange: targetCursor ..< match.targetIndex,
                        sentTotalUTF16: sent.utf16.count
                    )
                )
            }
            appendUnchangedSpan(
                sentToken: sentTokens[match.sentIndex],
                targetToken: targetTokens[match.targetIndex],
                to: &unchangedSpans
            )
            sentCursor = match.sentIndex + 1
            targetCursor = match.targetIndex + 1
        }
        if sentCursor < sentTokens.count || targetCursor < targetTokens.count {
            rawHunks.append(
                makeHunk(
                    sentTokens: sentTokens,
                    sentRange: sentCursor ..< sentTokens.count,
                    targetTokens: targetTokens,
                    targetRange: targetCursor ..< targetTokens.count,
                    sentTotalUTF16: sent.utf16.count
                )
            )
        }
        return (mergeSpaceSeparatedHunks(rawHunks, in: sent), unchangedSpans)
    }

    private static func appendUnchangedSpan(
        sentToken: DiffToken,
        targetToken: DiffToken,
        to spans: inout [UnchangedSpan]
    ) {
        if let last = spans.last,
           last.sentStart + last.length == sentToken.utf16Start,
           last.baseStart + last.length == targetToken.utf16Start {
            spans[spans.count - 1] = UnchangedSpan(
                sentStart: last.sentStart,
                baseStart: last.baseStart,
                length: last.length + sentToken.utf16Length
            )
        } else {
            spans.append(
                UnchangedSpan(
                    sentStart: sentToken.utf16Start,
                    baseStart: targetToken.utf16Start,
                    length: sentToken.utf16Length
                )
            )
        }
    }

    private static func tokenizeWords(_ text: String) -> [DiffToken] {
        var tokens: [DiffToken] = []
        var index = text.startIndex
        var utf16Offset = 0

        while index < text.endIndex {
            let start = index
            let first = text[index]
            let isSpace = first.isWhitespace
            if isSpace {
                while index < text.endIndex, text[index].isWhitespace {
                    index = text.index(after: index)
                }
            } else if first.isLetter || first.isNumber || first == "'" || first == "’" {
                while index < text.endIndex {
                    let current = text[index]
                    if current.isLetter || current.isNumber || current == "'" || current == "’" {
                        index = text.index(after: index)
                    } else {
                        break
                    }
                }
            } else {
                index = text.index(after: index)
            }
            let slice = String(text[start ..< index])
            let len = slice.utf16.count
            tokens.append(
                DiffToken(text: slice, utf16Start: utf16Offset, utf16Length: len, isWhitespace: isSpace)
            )
            utf16Offset += len
        }
        return tokens
    }

    private static func tokenLCS(sent: [DiffToken], target: [DiffToken]) -> [TokenMatch] {
        var prefixLen = 0
        while prefixLen < sent.count,
              prefixLen < target.count,
              sent[prefixLen].text == target[prefixLen].text {
            prefixLen += 1
        }
        var sentEnd = sent.count
        var targetEnd = target.count
        while sentEnd > prefixLen,
              targetEnd > prefixLen,
              sent[sentEnd - 1].text == target[targetEnd - 1].text {
            sentEnd -= 1
            targetEnd -= 1
        }

        var matches: [TokenMatch] = (0 ..< prefixLen).map {
            TokenMatch(sentIndex: $0, targetIndex: $0)
        }
        let rows = sentEnd - prefixLen
        let cols = targetEnd - prefixLen
        if rows > 0, cols > 0, rows * cols <= 250_000 {
            var table = Array(repeating: Array(repeating: 0, count: cols + 1), count: rows + 1)
            for row in stride(from: rows - 1, through: 0, by: -1) {
                for col in stride(from: cols - 1, through: 0, by: -1) {
                    if sent[prefixLen + row].text == target[prefixLen + col].text {
                        table[row][col] = table[row + 1][col + 1] + 1
                    } else {
                        table[row][col] = max(table[row + 1][col], table[row][col + 1])
                    }
                }
            }
            var row = 0
            var col = 0
            while row < rows, col < cols {
                if sent[prefixLen + row].text == target[prefixLen + col].text {
                    matches.append(
                        TokenMatch(sentIndex: prefixLen + row, targetIndex: prefixLen + col)
                    )
                    row += 1
                    col += 1
                } else if table[row + 1][col] >= table[row][col + 1] {
                    row += 1
                } else {
                    col += 1
                }
            }
        }
        for offset in 0 ..< (sent.count - sentEnd) {
            matches.append(
                TokenMatch(sentIndex: sentEnd + offset, targetIndex: targetEnd + offset)
            )
        }
        return matches
    }

    private static func makeHunk(
        sentTokens: [DiffToken],
        sentRange: Range<Int>,
        targetTokens: [DiffToken],
        targetRange: Range<Int>,
        sentTotalUTF16: Int
    ) -> DiffHunk {
        let startUTF16: Int
        let endUTF16: Int
        if let first = sentRange.first, let last = sentRange.last {
            startUTF16 = sentTokens[first].utf16Start
            endUTF16 = sentTokens[last].utf16Start + sentTokens[last].utf16Length
        } else if sentRange.lowerBound < sentTokens.count {
            startUTF16 = sentTokens[sentRange.lowerBound].utf16Start
            endUTF16 = startUTF16
        } else {
            startUTF16 = sentTotalUTF16
            endUTF16 = sentTotalUTF16
        }
        return DiffHunk(
            startUTF16: startUTF16,
            endUTF16: endUTF16,
            deletedText: sentRange.map { sentTokens[$0].text }.joined(),
            insertedText: targetRange.map { targetTokens[$0].text }.joined()
        )
    }

    private static func mergeSpaceSeparatedHunks(_ hunks: [DiffHunk], in sent: String) -> [DiffHunk] {
        guard !hunks.isEmpty else { return [] }
        var merged: [DiffHunk] = [hunks[0]]
        for next in hunks.dropFirst() {
            let prev = merged[merged.count - 1]
            if prev.endUTF16 <= next.startUTF16,
               let gap = sliceUTF16Range(in: sent, range: prev.endUTF16 ..< next.startUTF16),
               !gap.isEmpty,
               gap.allSatisfy(\.isWhitespace) {
                merged[merged.count - 1] = DiffHunk(
                    startUTF16: prev.startUTF16,
                    endUTF16: next.endUTF16,
                    deletedText: prev.deletedText + gap + next.deletedText,
                    insertedText: prev.insertedText + gap + next.insertedText
                )
            } else {
                merged.append(next)
            }
        }
        return merged.map(trimSharedEdgeWhitespace)
    }

    private static func trimSharedEdgeWhitespace(_ hunk: DiffHunk) -> DiffHunk {
        guard !hunk.deletedText.isEmpty, !hunk.insertedText.isEmpty else { return hunk }
        var deleted = hunk.deletedText
        var inserted = hunk.insertedText
        var start = hunk.startUTF16
        var end = hunk.endUTF16

        while let firstDel = deleted.first,
              let firstIns = inserted.first,
              firstDel == firstIns,
              firstDel.isWhitespace {
            let step = String(firstDel).utf16.count
            deleted.removeFirst()
            inserted.removeFirst()
            start += step
        }
        while let lastDel = deleted.last,
              let lastIns = inserted.last,
              lastDel == lastIns,
              lastDel.isWhitespace {
            let step = String(lastDel).utf16.count
            deleted.removeLast()
            inserted.removeLast()
            end -= step
        }
        return DiffHunk(
            startUTF16: start,
            endUTF16: max(start, end),
            deletedText: deleted,
            insertedText: inserted
        )
    }

    private static func mapRange(
        _ range: Range<Int>,
        throughUnchangedSpans spans: [UnchangedSpan]
    ) -> Range<Int>? {
        for span in spans {
            let baseEnd = span.baseStart + span.length
            if range.lowerBound >= span.baseStart, range.upperBound <= baseEnd {
                let delta = span.sentStart - span.baseStart
                return (range.lowerBound + delta) ..< (range.upperBound + delta)
            }
        }
        return nil
    }
}
