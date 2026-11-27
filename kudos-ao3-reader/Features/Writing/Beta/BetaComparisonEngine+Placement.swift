import Foundation

// MARK: - Live HTML placement (for Accept & Comment anchoring)

nonisolated extension BetaComparisonEngine {
    /// Maps a suggestion onto the chapter's current live HTML as a single-run UTF-16 range.
    static func place(
        _ suggestion: BetaSuggestionItem,
        in liveHTML: String
    ) -> BetaHTMLTextMapper.PlacementResult {
        if suggestion.isWholeParagraphAddition {
            return .wholeParagraphAddition
        }
        let textMap = BetaHTMLTextMapper.build(from: liveHTML)
        // Normalizing NBSP and curly quotes 1-to-1 preserves every UTF-16 offset while
        // surviving Word/Google Docs space and smart-quote conversions.
        let normalizedLive = normalizeForComparison(textMap.plainText)
        guard let plainRange = locatePlainRange(for: suggestion, in: normalizedLive) else {
            return .notFound
        }
        return textMap.htmlRange(forPlainUTF16Range: plainRange, allowInlineTags: false)
    }

    /// Confirms that `range` stays inside one HTML text run of `html` and its decoded text
    /// equals `deletedText` before `DraftSession.replaceText` modifies the chapter.
    static func rangeMatchesDeletedText(
        _ deletedText: String,
        at range: RichEditorTextRange,
        in html: String
    ) -> Bool {
        guard DraftSession.textRunRange(range, in: html) != nil,
              let rawSlice = sliceUTF16Range(in: html, range: range.from ..< range.to)
        else {
            return false
        }
        return BetaHTMLTextMapper.decodeEntities(in: rawSlice) == deletedText
    }

    /// Captures a 576d `WritingAnnotationAnchor` in `liveHTML` for a returned beta comment.
    static func anchor(
        for comment: BetaCommentItem,
        sentHTML: String,
        in liveHTML: String
    ) -> WritingAnnotationAnchor {
        let sentParagraphs = BetaHTMLDocument.parse(sentHTML).map(\.plainText)
        let sentContext = SentParagraphContexts.build(from: sentParagraphs)
        let textMap = BetaHTMLTextMapper.build(from: liveHTML)
        let normalizedLive = normalizeForComparison(textMap.plainText)

        if let plainRange = locateCommentPlainRange(
            comment: comment,
            sentParagraphs: sentParagraphs,
            sentContext: sentContext,
            livePlainText: normalizedLive
        ),
           case let .placed(htmlRange) = textMap.htmlRange(
               forPlainUTF16Range: plainRange,
               allowInlineTags: true
           ),
           let captured = WritingAnnotationReanchor.capture(
               in: liveHTML,
               utf16Range: htmlRange.from ..< htmlRange.to
           ) {
            return captured
        }

        let fallbackQuote = comment.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        return WritingAnnotationAnchor(
            quote: fallbackQuote.isEmpty ? "…" : fallbackQuote,
            prefix: "",
            suffix: "",
            utf16Offset: 0
        )
    }

    // MARK: - Locating suggestions & comments in live plain text

    private static func locatePlainRange(
        for suggestion: BetaSuggestionItem,
        in normalizedLive: String
    ) -> Range<Int>? {
        let normParaText = normalizeForComparison(suggestion.paragraphText)
        let normParaAnchor = WritingAnnotationAnchor(
            quote: normParaText,
            prefix: normalizeForComparison(suggestion.paragraphPrefix),
            suffix: normalizeForComparison(suggestion.paragraphSuffix),
            utf16Offset: suggestion.paragraphUTF16Offset
        )
        let normDeleted = normalizeForComparison(suggestion.deletedText)
        let normLocalPrefix = normalizeForComparison(suggestion.localPrefix)
        let normLocalSuffix = normalizeForComparison(suggestion.localSuffix)

        // Strategy A: anchor the whole sent paragraph first (as 576d anchors notes).
        if !normParaText.isEmpty,
           case let .placed(placedParagraph) = WritingAnnotationReanchor.reanchor(
               normParaAnchor,
               in: normalizedLive
           ) {
            if placedParagraph.quote == normParaText {
                let start = placedParagraph.utf16Offset + suggestion.editStartUTF16
                let end = placedParagraph.utf16Offset + suggestion.editEndUTF16
                if start >= 0, end >= start, end <= normalizedLive.utf16.count {
                    return start ..< end
                }
            }
            if let local = locateEditWithContext(
                in: placedParagraph.quote,
                deletedText: normDeleted,
                prefix: normLocalPrefix,
                suffix: normLocalSuffix,
                hintUTF16: suggestion.editStartUTF16
            ) {
                return (placedParagraph.utf16Offset + local.lowerBound)
                    ..< (placedParagraph.utf16Offset + local.upperBound)
            }
        }

        // Strategy B: paragraph shifted by >2 edits (e.g. an earlier suggestion in the same
        // paragraph was accepted). Locate exact deleted text or insertion seam with context.
        let globalHint = suggestion.paragraphUTF16Offset + suggestion.editStartUTF16
        return locateEditWithContext(
            in: normalizedLive,
            deletedText: normDeleted,
            prefix: normLocalPrefix,
            suffix: normLocalSuffix,
            hintUTF16: globalHint
        )
    }

    private static func locateEditWithContext(
        in haystack: String,
        deletedText: String,
        prefix: String,
        suffix: String,
        hintUTF16: Int
    ) -> Range<Int>? {
        if deletedText.isEmpty {
            return locateInsertionSeam(
                in: haystack,
                prefix: prefix,
                suffix: suffix,
                hintUTF16: hintUTF16
            )
        }
        let occurrences = exactLiteralRanges(of: deletedText, in: haystack)
        guard !occurrences.isEmpty else { return nil }

        var scored: [(range: Range<Int>, score: Int, dist: Int)] = []
        for match in occurrences {
            let startUTF16 = haystack.utf16.distance(
                from: haystack.utf16.startIndex,
                to: match.lowerBound
            )
            let endUTF16 = startUTF16 + deletedText.utf16.count
            let actualPrefix = String(haystack[..<match.lowerBound].suffix(prefix.count))
            let actualSuffix = String(haystack[match.upperBound...].prefix(suffix.count))

            guard contextMatches(
                expectedPrefix: prefix,
                actualPrefix: actualPrefix,
                expectedSuffix: suffix,
                actualSuffix: actualSuffix
            ) else { continue }

            let score = prefixMatchLength(prefix, actualPrefix)
                + suffixMatchLength(suffix, actualSuffix)
            scored.append((range: startUTF16 ..< endUTF16, score: score, dist: abs(startUTF16 - hintUTF16)))
        }
        guard let bestScore = scored.map(\.score).max() else { return nil }
        let topTier = scored.filter { $0.score == bestScore }
        guard let nearest = topTier.min(by: { $0.dist < $1.dist }) else { return nil }
        let tied = topTier.filter { $0.dist == nearest.dist }
        return tied.count == 1 ? nearest.range : nil
    }

    private static func locateInsertionSeam(
        in haystack: String,
        prefix: String,
        suffix: String,
        hintUTF16: Int
    ) -> Range<Int>? {
        let shortPrefix = String(prefix.suffix(12))
        let shortSuffix = String(suffix.prefix(12))
        let seam = shortPrefix + shortSuffix
        guard !seam.isEmpty else { return nil }

        let occurrences = exactLiteralRanges(of: seam, in: haystack)
        guard !occurrences.isEmpty else { return nil }

        var candidates: [(pos: Int, score: Int, dist: Int)] = []
        for match in occurrences {
            if shortPrefix.isEmpty, match.lowerBound > haystack.startIndex {
                guard haystack[haystack.index(before: match.lowerBound)] == "\n" else { continue }
            }
            if shortSuffix.isEmpty, match.upperBound < haystack.endIndex {
                guard haystack[match.upperBound] == "\n" else { continue }
            }
            let seamStart = haystack.utf16.distance(
                from: haystack.utf16.startIndex,
                to: match.lowerBound
            )
            let insertPos = seamStart + shortPrefix.utf16.count
            let beforePos = sliceUTF16Prefix(in: haystack, before: insertPos, maxChars: prefix.count)
            let afterPos = sliceUTF16Suffix(in: haystack, after: insertPos, maxChars: suffix.count)
            let score = prefixMatchLength(prefix, beforePos) + suffixMatchLength(suffix, afterPos)
            candidates.append((pos: insertPos, score: score, dist: abs(insertPos - hintUTF16)))
        }
        guard let bestScore = candidates.map(\.score).max() else { return nil }
        let topTier = candidates.filter { $0.score == bestScore }
        guard let nearest = topTier.min(by: { $0.dist < $1.dist }) else { return nil }
        let tied = topTier.filter { $0.dist == nearest.dist }
        guard tied.count == 1 else { return nil }
        return nearest.pos ..< nearest.pos
    }

    private static func locateCommentPlainRange(
        comment: BetaCommentItem,
        sentParagraphs: [String],
        sentContext: [SentParagraphContext],
        livePlainText: String
    ) -> Range<Int>? {
        let trimmedQuote = normalizeForComparison(
            comment.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if comment.paragraphIndex >= 0, comment.paragraphIndex < sentParagraphs.count {
            let sentPara = normalizeForComparison(sentParagraphs[comment.paragraphIndex])
            let ctx = sentContext[comment.paragraphIndex]
            let paraAnchor = WritingAnnotationAnchor(
                quote: sentPara,
                prefix: normalizeForComparison(ctx.prefix),
                suffix: normalizeForComparison(ctx.suffix),
                utf16Offset: ctx.utf16Offset
            )
            if case let .placed(placedPara) = WritingAnnotationReanchor.reanchor(
                paraAnchor,
                in: livePlainText
            ) {
                if !trimmedQuote.isEmpty {
                    let quoteAnchor = WritingAnnotationAnchor(
                        quote: trimmedQuote,
                        prefix: "",
                        suffix: "",
                        utf16Offset: min(comment.characterOffsetUTF16, placedPara.quote.utf16.count)
                    )
                    if case let .placed(placedQuote) = WritingAnnotationReanchor.reanchor(
                        quoteAnchor,
                        in: placedPara.quote
                    ) {
                        let start = placedPara.utf16Offset + placedQuote.utf16Offset
                        return start ..< (start + placedQuote.quote.utf16.count)
                    }
                    if trimmedQuote.contains("\n") {
                        let crossParaAnchor = WritingAnnotationAnchor(
                            quote: trimmedQuote,
                            prefix: "",
                            suffix: "",
                            utf16Offset: placedPara.utf16Offset
                                + min(comment.characterOffsetUTF16, placedPara.quote.utf16.count)
                        )
                        if case let .placed(placedCross) = WritingAnnotationReanchor.reanchor(
                            crossParaAnchor,
                            in: livePlainText
                        ) {
                            return placedCross.utf16Offset
                                ..< (placedCross.utf16Offset + placedCross.quote.utf16.count)
                        }
                    }
                }
                if !placedPara.quote.isEmpty {
                    let start = placedPara.utf16Offset
                    return start ..< (start + placedPara.quote.utf16.count)
                }
            }
        }
        guard !trimmedQuote.isEmpty else { return nil }
        let fallbackAnchor = WritingAnnotationAnchor(
            quote: trimmedQuote,
            prefix: "",
            suffix: "",
            utf16Offset: comment.characterOffsetUTF16
        )
        if case let .placed(placed) = WritingAnnotationReanchor.reanchor(
            fallbackAnchor,
            in: livePlainText
        ) {
            return placed.utf16Offset ..< (placed.utf16Offset + placed.quote.utf16.count)
        }
        return nil
    }

    private static func contextMatches(
        expectedPrefix: String,
        actualPrefix: String,
        expectedSuffix: String,
        actualSuffix: String
    ) -> Bool {
        if expectedPrefix.isEmpty, expectedSuffix.isEmpty {
            return true
        }
        let minPrefixCheck = min(expectedPrefix.count, 6)
        let minSuffixCheck = min(expectedSuffix.count, 6)
        let prefixOK = !expectedPrefix.isEmpty
            && prefixMatchLength(expectedPrefix, actualPrefix) >= minPrefixCheck
        let suffixOK = !expectedSuffix.isEmpty
            && suffixMatchLength(expectedSuffix, actualSuffix) >= minSuffixCheck
        return prefixOK || suffixOK
    }

    private static func prefixMatchLength(_ expected: String, _ actual: String) -> Int {
        var count = 0
        for (lhs, rhs) in zip(expected.reversed(), actual.reversed()) {
            if lhs == rhs { count += 1 } else { break }
        }
        return count
    }

    private static func suffixMatchLength(_ expected: String, _ actual: String) -> Int {
        var count = 0
        for (lhs, rhs) in zip(expected, actual) {
            if lhs == rhs { count += 1 } else { break }
        }
        return count
    }

    private static func exactLiteralRanges(
        of needle: String,
        in haystack: String
    ) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var searchRange = haystack.startIndex ..< haystack.endIndex
        while let range = haystack.range(of: needle, options: [.literal], range: searchRange) {
            found.append(range)
            guard range.upperBound < haystack.endIndex else { break }
            searchRange = range.upperBound ..< haystack.endIndex
        }
        return found
    }
}
