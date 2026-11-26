import Foundation

/// Finds a private note again after the chapter HTML changes.
///
/// Exact quote first. Prefix and suffix (32 characters) separate repeated quotes,
/// and the UTF-16 offset breaks a remaining tie by nearness. If the quote itself
/// changed, a passage within `maxEditDistance` edits counts only when its own
/// context is that close too, and only beside the old offset or an exact prefix
/// or suffix. A tie the offset cannot separate is lost: the note stays stored and
/// is reported, never pinned to a guess.
nonisolated enum WritingAnnotationReanchor {
    static let contextLimit = 32
    /// Insertions, deletions and substitutions that still count as the same passage.
    static let maxEditDistance = 2
    /// A shorter prefix or suffix is too common to search the whole chapter for.
    private static let minimumContextSearch = 8

    static func capture(in body: String, utf16Range: Range<Int>) -> WritingAnnotationAnchor? {
        guard let range = body.writingRange(utf16: utf16Range), !range.isEmpty else { return nil }
        return anchor(covering: range, in: body)
    }

    static func reanchor(_ anchor: WritingAnnotationAnchor, in body: String) -> WritingReanchorOutcome {
        let sought = clamped(anchor)
        if let range = exactMatch(sought, in: body) {
            return .placed(Self.anchor(covering: range, in: body, context: sought))
        }
        // One or two edits of a one-character quote match almost anything.
        guard sought.quote.utf16.count > maxEditDistance + 1 else { return .lost }
        guard let range = fuzzyMatch(sought, in: body) else { return .lost }
        return .placed(Self.anchor(covering: range, in: body, context: sought))
    }

    private static func clamped(_ anchor: WritingAnnotationAnchor) -> WritingAnnotationAnchor {
        WritingAnnotationAnchor(
            quote: anchor.quote,
            prefix: String(anchor.prefix.prefix(contextLimit)),
            suffix: String(anchor.suffix.prefix(contextLimit)),
            utf16Offset: max(0, anchor.utf16Offset)
        )
    }

    /// `context` keeps the stored prefix and suffix widths. A longer chapter must
    /// not grow them: the doubled-paragraph case still has the original anchor.
    private static func anchor(
        covering range: Range<String.Index>,
        in body: String,
        context sought: WritingAnnotationAnchor? = nil
    ) -> WritingAnnotationAnchor {
        let prefixCount = min(contextLimit, sought?.prefix.count ?? contextLimit)
        let suffixCount = min(contextLimit, sought?.suffix.count ?? contextLimit)
        return WritingAnnotationAnchor(
            quote: String(body[range]),
            prefix: String(body[..<range.lowerBound].suffix(prefixCount)),
            suffix: String(body[range.upperBound...].prefix(suffixCount)),
            utf16Offset: body.writingUTF16Offset(of: range.lowerBound)
        )
    }

    private struct Match {
        var range: Range<String.Index>
        var quoteDistance: Int
        var contextDistance: Int
        var hintDistance: Int
    }

    /// One exact quote is the passage. Several need a context that agrees, then the hint.
    private static func exactMatch(_ anchor: WritingAnnotationAnchor, in body: String) -> Range<String.Index>? {
        let matches = literalRanges(of: anchor.quote, in: body).map { range in
            score(range, anchor: anchor, in: body, quoteDistance: 0)
        }
        guard let nearest = matches.first else { return nil }
        if matches.count == 1 { return nearest.range }
        guard let bestContext = matches.map(\.contextDistance).min() else { return nil }
        guard bestContext <= maxEditDistance else { return nil }
        let tier = matches.filter { $0.contextDistance == bestContext }
        return choose(tier)?.range
    }

    private static func fuzzyMatch(_ anchor: WritingAnnotationAnchor, in body: String) -> Range<String.Index>? {
        var scored: [Match] = []
        for range in fuzzyRanges(anchor, in: body) {
            let text = String(body[range])
            guard let distance = editDistance(anchor.quote, text, limit: maxEditDistance), distance >= 1 else {
                continue
            }
            let match = score(range, anchor: anchor, in: body, quoteDistance: distance)
            guard match.contextDistance <= maxEditDistance else { continue }
            scored.append(match)
        }
        guard let bestQuote = scored.map(\.quoteDistance).min() else { return nil }
        let quoteTier = scored.filter { $0.quoteDistance == bestQuote }
        guard let bestContext = quoteTier.map(\.contextDistance).min() else { return nil }
        return choose(quoteTier.filter { $0.contextDistance == bestContext })?.range
    }

    /// Two different spans the hint cannot separate are not a placement.
    /// One span can arrive from the hint window and again from the prefix and
    /// suffix searches; those copies are the same match.
    private static func choose(_ matches: [Match]) -> Match? {
        guard let nearest = matches.min(by: { $0.hintDistance < $1.hintDistance }) else { return nil }
        let ranges = Set(matches.filter { $0.hintDistance == nearest.hintDistance }.map(\.range))
        return ranges.count == 1 ? nearest : nil
    }

    private static func score(
        _ range: Range<String.Index>,
        anchor: WritingAnnotationAnchor,
        in body: String,
        quoteDistance: Int
    ) -> Match {
        let offset = body.writingUTF16Offset(of: range.lowerBound)
        return Match(
            range: range,
            quoteDistance: quoteDistance,
            contextDistance: contextDistance(anchor, around: range, in: body),
            hintDistance: abs(offset - anchor.utf16Offset)
        )
    }

    private static func contextDistance(
        _ anchor: WritingAnnotationAnchor,
        around range: Range<String.Index>,
        in body: String
    ) -> Int {
        let actualPrefix = String(body[..<range.lowerBound].suffix(anchor.prefix.count))
        let actualSuffix = String(body[range.upperBound...].prefix(anchor.suffix.count))
        let prefixDistance = editDistance(anchor.prefix, actualPrefix, limit: maxEditDistance) ?? (maxEditDistance + 1)
        let suffixDistance = editDistance(anchor.suffix, actualSuffix, limit: maxEditDistance) ?? (maxEditDistance + 1)
        return max(prefixDistance, suffixDistance)
    }

    private static func fuzzyRanges(_ anchor: WritingAnnotationAnchor, in body: String) -> [Range<String.Index>] {
        let quoteLength = anchor.quote.utf16.count
        let minimum = max(1, quoteLength - maxEditDistance)
        let maximum = quoteLength + maxEditDistance
        var results: [Range<String.Index>] = []
        appendWindows(
            around: max(0, anchor.utf16Offset),
            slack: maxEditDistance,
            lengths: minimum...maximum,
            in: body,
            to: &results
        )
        if anchor.prefix.count >= minimumContextSearch {
            for prefixRange in literalRanges(of: anchor.prefix, in: body) {
                let start = body.writingUTF16Offset(of: prefixRange.upperBound)
                appendFixed(start: start, lengths: minimum...maximum, in: body, to: &results)
            }
        }
        if anchor.suffix.count >= minimumContextSearch {
            for suffixRange in literalRanges(of: anchor.suffix, in: body) {
                let end = body.writingUTF16Offset(of: suffixRange.lowerBound)
                for length in minimum...maximum where end - length >= 0 {
                    if let range = body.writingRange(utf16: (end - length)..<end) {
                        results.append(range)
                    }
                }
            }
        }
        return results
    }

    private static func appendWindows(
        around hint: Int,
        slack: Int,
        lengths: ClosedRange<Int>,
        in body: String,
        to results: inout [Range<String.Index>]
    ) {
        let lower = max(0, hint - slack)
        for start in lower...(hint + slack) {
            appendFixed(start: start, lengths: lengths, in: body, to: &results)
        }
    }

    private static func appendFixed(
        start: Int,
        lengths: ClosedRange<Int>,
        in body: String,
        to results: inout [Range<String.Index>]
    ) {
        for length in lengths {
            if let range = body.writingRange(utf16: start..<(start + length)) {
                results.append(range)
            }
        }
    }

    private static func literalRanges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var rest = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, options: [.literal], range: rest) {
            found.append(range)
            guard range.upperBound < haystack.endIndex else { break }
            rest = range.upperBound..<haystack.endIndex
        }
        return found
    }

    /// Levenshtein distance, or nil when it would pass `limit`.
    private static func editDistance(_ left: String, _ right: String, limit: Int) -> Int? {
        let leftChars = Array(left)
        let rightChars = Array(right)
        if abs(leftChars.count - rightChars.count) > limit { return nil }
        if leftChars.isEmpty { return rightChars.count }
        var previous = Array(0...rightChars.count)
        for row in 1...leftChars.count {
            var current = [row]
            var rowMinimum = row
            for column in 1...rightChars.count {
                let substitution = leftChars[row - 1] == rightChars[column - 1] ? 0 : 1
                let value = min(
                    previous[column] + 1,
                    current[column - 1] + 1,
                    previous[column - 1] + substitution
                )
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return nil }
            previous = current
        }
        return previous[rightChars.count] <= limit ? previous[rightChars.count] : nil
    }
}

private extension String {
    func writingRange(utf16 bounds: Range<Int>) -> Range<Index>? {
        guard bounds.lowerBound >= 0, bounds.upperBound >= bounds.lowerBound else { return nil }
        let view = self.utf16
        guard bounds.upperBound <= view.count else { return nil }
        let lower = view.index(view.startIndex, offsetBy: bounds.lowerBound)
        let upper = view.index(lower, offsetBy: bounds.upperBound - bounds.lowerBound)
        guard let start = Index(lower, within: self), let end = Index(upper, within: self) else { return nil }
        return start..<end
    }

    func writingUTF16Offset(of index: Index) -> Int {
        if let utf16Index = index.samePosition(in: utf16) {
            return utf16.distance(from: utf16.startIndex, to: utf16Index)
        }
        return self[..<index].utf16.count
    }
}
