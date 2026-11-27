import Foundation
import SwiftSoup

// MARK: - Plain-text ↔ HTML UTF-16 offset mapper

/// Maps plain text rendered from chapter HTML back to exact UTF-16 ranges in the
/// source HTML, treating HTML entities (`&amp;`, `&#x2019;`, …) as single characters
/// and rejecting edits that cross inline tags or split an entity.
nonisolated enum BetaHTMLTextMapper {
    struct Entry: Equatable, Sendable {
        let htmlStart: Int
        let htmlEnd: Int
        let runID: Int
        let isSynthetic: Bool
    }

    struct TextMap: Equatable, Sendable {
        let plainText: String
        let entries: [Entry]

        func htmlRange(
            forPlainUTF16Range range: Range<Int>,
            allowInlineTags: Bool
        ) -> PlacementResult {
            guard range.lowerBound >= 0, range.upperBound <= entries.count else {
                return .notFound
            }
            if range.isEmpty {
                return insertionRange(at: range.lowerBound)
            }
            if splitsEntityBoundary(at: range.lowerBound) || splitsEntityBoundary(at: range.upperBound) {
                return .crossesFormatting
            }
            if allowInlineTags {
                return rangeAllowingTags(range)
            }
            let first = entries[range.lowerBound]
            guard !first.isSynthetic else { return .crossesFormatting }
            for idx in range {
                let entry = entries[idx]
                if entry.isSynthetic || entry.runID != first.runID {
                    return .crossesFormatting
                }
            }
            let last = entries[range.upperBound - 1]
            return .placed(RichEditorTextRange(from: first.htmlStart, to: last.htmlEnd))
        }

        private func insertionRange(at pos: Int) -> PlacementResult {
            if splitsEntityBoundary(at: pos) {
                return .crossesFormatting
            }
            if pos > 0, pos < entries.count {
                let prev = entries[pos - 1]
                let next = entries[pos]
                if !prev.isSynthetic, !next.isSynthetic, prev.runID == next.runID {
                    return .placed(RichEditorTextRange(from: next.htmlStart, to: next.htmlStart))
                }
            }
            if pos < entries.count, !entries[pos].isSynthetic {
                let offset = entries[pos].htmlStart
                return .placed(RichEditorTextRange(from: offset, to: offset))
            }
            if pos > 0, !entries[pos - 1].isSynthetic {
                let offset = entries[pos - 1].htmlEnd
                return .placed(RichEditorTextRange(from: offset, to: offset))
            }
            return .crossesFormatting
        }

        private func rangeAllowingTags(_ range: Range<Int>) -> PlacementResult {
            var firstNonSynthetic: Entry?
            var lastNonSynthetic: Entry?
            for idx in range {
                let entry = entries[idx]
                guard !entry.isSynthetic else { continue }
                if firstNonSynthetic == nil { firstNonSynthetic = entry }
                lastNonSynthetic = entry
            }
            guard let first = firstNonSynthetic,
                  let last = lastNonSynthetic,
                  last.htmlEnd > first.htmlStart
            else {
                return .notFound
            }
            return .placed(RichEditorTextRange(from: first.htmlStart, to: last.htmlEnd))
        }

        private func splitsEntityBoundary(at pos: Int) -> Bool {
            guard pos > 0, pos < entries.count else { return false }
            let prev = entries[pos - 1]
            let next = entries[pos]
            guard !prev.isSynthetic, !next.isSynthetic else { return false }
            return prev.htmlStart == next.htmlStart && prev.htmlEnd == next.htmlEnd
        }
    }

    enum PlacementResult: Equatable, Sendable {
        case placed(RichEditorTextRange)
        case crossesFormatting
        case notFound
        case wholeParagraphAddition
    }

    private static let blockTags: Set<String> = [
        "p", "div", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "hr", "pre", "center", "details", "summary",
        "dl", "dt", "dd", "section", "article", "header", "footer", "aside",
    ]

    private static let commonNamedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "mdash": "—", "ndash": "–", "hellip": "…",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "laquo": "«", "raquo": "»", "copy": "©", "reg": "®", "trade": "™",
        "bull": "•", "middot": "·", "sect": "§", "para": "¶", "deg": "°",
        "times": "×", "divide": "÷", "plusmn": "±", "dagger": "†", "Dagger": "‡",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢",
    ]

    static func build(from html: String) -> TextMap {
        let units = Array(html.utf16)
        var scanner = HTMLMapScanner(units: units)
        return scanner.scan()
    }

    /// Decodes HTML character references in a single raw text run without collapsing
    /// or trimming whitespace (used to verify an HTML replacement slice against `deletedText`).
    static func decodeEntities(in slice: String) -> String {
        guard slice.contains("&") else { return slice }
        let units = Array(slice.utf16)
        var output: [UInt16] = []
        output.reserveCapacity(units.count)
        var cursor = 0
        while cursor < units.count {
            if units[cursor] == 0x26, let entity = decodeEntity(in: units, at: cursor) {
                output.append(contentsOf: entity.decoded.utf16)
                cursor = entity.nextIndex
            } else {
                output.append(units[cursor])
                cursor += 1
            }
        }
        return String(decoding: output, as: UTF16.self)
    }

    fileprivate static func decodeEntity(
        in units: [UInt16],
        at start: Int
    ) -> (decoded: String, nextIndex: Int)? {
        let maxEnd = min(units.count, start + 36)
        var cursor = start + 1
        while cursor < maxEnd {
            let unit = units[cursor]
            if unit == 0x3B { // ';'
                let raw = String(decoding: units[start ... cursor], as: UTF16.self)
                if let decoded = resolveEntity(raw) {
                    return (decoded, cursor + 1)
                }
                return nil
            }
            if unit == 0x26 || unit == 0x3C || isASCIIWhitespace(unit) {
                return nil
            }
            cursor += 1
        }
        return nil
    }

    fileprivate static func isASCIIWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x0C
    }

    private struct HTMLMapScanner {
        let units: [UInt16]
        var plainUnits: [UInt16] = []
        var entries: [Entry] = []
        var runID = 0
        var preDepth = 0
        var skipContentTag: String?
        var atLineStart = true
        var previousWasSpace = false
        var needsBlockSeparator = false

        mutating func scan() -> TextMap {
            var cursor = 0
            while cursor < units.count {
                if units[cursor] == 0x3C { // '<'
                    cursor = handleTagOrComment(at: cursor)
                    continue
                }
                if skipContentTag != nil {
                    cursor += 1
                    continue
                }
                if preDepth > 0 {
                    cursor = consumePreformattedUnit(at: cursor)
                } else {
                    cursor = consumeProseUnit(at: cursor)
                }
            }
            trimTrailingWhitespace()
            return TextMap(plainText: String(decoding: plainUnits, as: UTF16.self), entries: entries)
        }

        private mutating func handleTagOrComment(at start: Int) -> Int {
            runID += 1
            if startsComment(at: start) {
                return endOfComment(from: start + 4)
            }
            let parsed = parseTag(at: start)
            guard let tag = parsed.name else {
                return parsed.nextIndex
            }
            if let skipTag = skipContentTag {
                if parsed.isClosing, tag == skipTag {
                    skipContentTag = nil
                }
                return parsed.nextIndex
            }
            if !parsed.isClosing, !parsed.isSelfClosing, tag == "script" || tag == "style" {
                skipContentTag = tag
                return parsed.nextIndex
            }
            applyTagSemantics(tag: tag, isClosing: parsed.isClosing, at: start)
            return parsed.nextIndex
        }

        private mutating func applyTagSemantics(tag: String, isClosing: Bool, at offset: Int) {
            if tag == "pre" {
                if isClosing {
                    preDepth = max(0, preDepth - 1)
                } else {
                    beginBlockBoundary()
                    preDepth += 1
                }
                return
            }
            if tag == "br", !isClosing {
                trimTrailingWhitespace()
                emitSynthetic("\n", at: offset)
                atLineStart = true
                previousWasSpace = false
                return
            }
            if tag == "hr", !isClosing {
                beginBlockBoundary()
                emitBlockSeparatorIfNeeded(at: offset)
                emitSynthetic("* * *", at: offset)
                atLineStart = true
                previousWasSpace = false
                needsBlockSeparator = true
                return
            }
            if BetaHTMLTextMapper.blockTags.contains(tag) {
                beginBlockBoundary()
            }
        }

        private mutating func beginBlockBoundary() {
            trimTrailingWhitespace()
            if !plainUnits.isEmpty {
                needsBlockSeparator = true
            }
            atLineStart = true
            previousWasSpace = false
        }

        private mutating func emitBlockSeparatorIfNeeded(at offset: Int) {
            guard needsBlockSeparator else { return }
            needsBlockSeparator = false
            if !plainUnits.isEmpty {
                emitSynthetic("\n", at: offset)
            }
        }

        private mutating func consumePreformattedUnit(at start: Int) -> Int {
            emitBlockSeparatorIfNeeded(at: start)
            let unit = units[start]
            if unit == 0x0D { // '\r'
                let next = (start + 1 < units.count && units[start + 1] == 0x0A) ? start + 2 : start + 1
                emitMapped(unit: 0x0A, htmlStart: start, htmlEnd: next)
                return next
            }
            if unit == 0x26, let entity = decodeEntity(at: start) {
                emitDecoded(entity.decoded, htmlStart: start, htmlEnd: entity.nextIndex)
                return entity.nextIndex
            }
            emitMapped(unit: unit, htmlStart: start, htmlEnd: start + 1)
            return start + 1
        }

        private mutating func consumeProseUnit(at start: Int) -> Int {
            let unit = units[start]
            if isASCIIWhitespace(unit) {
                var end = start + 1
                while end < units.count, isASCIIWhitespace(units[end]) {
                    end += 1
                }
                if !atLineStart, !previousWasSpace {
                    emitMapped(unit: 0x20, htmlStart: start, htmlEnd: end)
                    previousWasSpace = true
                }
                return end
            }

            emitBlockSeparatorIfNeeded(at: start)
            if unit == 0x26, let entity = decodeEntity(at: start) {
                emitDecoded(entity.decoded, htmlStart: start, htmlEnd: entity.nextIndex)
                atLineStart = false
                previousWasSpace = entity.decoded.last == " "
                return entity.nextIndex
            }
            emitMapped(unit: unit, htmlStart: start, htmlEnd: start + 1)
            atLineStart = false
            previousWasSpace = false
            return start + 1
        }

        private mutating func emitMapped(unit: UInt16, htmlStart: Int, htmlEnd: Int) {
            plainUnits.append(unit)
            entries.append(Entry(htmlStart: htmlStart, htmlEnd: htmlEnd, runID: runID, isSynthetic: false))
        }

        private mutating func emitDecoded(_ text: String, htmlStart: Int, htmlEnd: Int) {
            for codeUnit in text.utf16 {
                plainUnits.append(codeUnit)
                entries.append(Entry(htmlStart: htmlStart, htmlEnd: htmlEnd, runID: runID, isSynthetic: false))
            }
        }

        private mutating func emitSynthetic(_ text: String, at offset: Int) {
            for codeUnit in text.utf16 {
                plainUnits.append(codeUnit)
                entries.append(Entry(htmlStart: offset, htmlEnd: offset, runID: runID, isSynthetic: true))
            }
        }

        private mutating func trimTrailingWhitespace() {
            while let lastUnit = plainUnits.last,
                  let lastEntry = entries.last,
                  !lastEntry.isSynthetic,
                  lastUnit == 0x20 {
                plainUnits.removeLast()
                entries.removeLast()
            }
        }

        private func decodeEntity(at start: Int) -> (decoded: String, nextIndex: Int)? {
            BetaHTMLTextMapper.decodeEntity(in: units, at: start)
        }

        private func startsComment(at start: Int) -> Bool {
            start + 3 < units.count
                && units[start + 1] == 0x21
                && units[start + 2] == 0x2D
                && units[start + 3] == 0x2D
        }

        private func endOfComment(from start: Int) -> Int {
            var cursor = start
            while cursor + 2 < units.count {
                if units[cursor] == 0x2D, units[cursor + 1] == 0x2D, units[cursor + 2] == 0x3E {
                    return cursor + 3
                }
                cursor += 1
            }
            return units.count
        }

        private struct ParsedTag {
            var name: String?
            var isClosing = false
            var isSelfClosing = false
            var nextIndex: Int
        }

        private func parseTag(at start: Int) -> ParsedTag {
            let count = units.count
            var cursor = start + 1
            var isClosing = false
            if cursor < count, units[cursor] == 0x2F { // '/'
                isClosing = true
                cursor += 1
            }
            let nameStart = cursor
            while cursor < count, isASCIIAlphaNum(units[cursor]) {
                cursor += 1
            }
            guard cursor > nameStart else {
                return ParsedTag(nextIndex: start + 1)
            }
            let rawName = String(decoding: units[nameStart ..< cursor], as: UTF16.self).lowercased()

            var quote: UInt16 = 0
            var lastNonSpace: UInt16 = 0
            while cursor < count {
                let unit = units[cursor]
                if quote != 0 {
                    if unit == quote { quote = 0 }
                } else if unit == 0x22 || unit == 0x27 {
                    quote = unit
                } else if unit == 0x3E { // '>'
                    return ParsedTag(
                        name: rawName,
                        isClosing: isClosing,
                        isSelfClosing: lastNonSpace == 0x2F,
                        nextIndex: cursor + 1
                    )
                } else if !isASCIIWhitespace(unit) {
                    lastNonSpace = unit
                }
                cursor += 1
            }
            return ParsedTag(name: rawName, isClosing: isClosing, isSelfClosing: false, nextIndex: count)
        }

        private func isASCIIWhitespace(_ unit: UInt16) -> Bool {
            BetaHTMLTextMapper.isASCIIWhitespace(unit)
        }

        private func isASCIIAlphaNum(_ unit: UInt16) -> Bool {
            (unit >= 0x41 && unit <= 0x5A)
                || (unit >= 0x61 && unit <= 0x7A)
                || (unit >= 0x30 && unit <= 0x39)
        }
    }

    fileprivate static func resolveEntity(_ raw: String) -> String? {
        guard raw.hasPrefix("&"), raw.hasSuffix(";"), raw.count >= 3 else { return nil }
        let body = String(raw.dropFirst().dropLast())
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let codePoint: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                codePoint = UInt32(digits.dropFirst(), radix: 16)
            } else {
                codePoint = UInt32(digits, radix: 10)
            }
            if let codePoint, let scalar = UnicodeScalar(codePoint) {
                return String(scalar)
            }
            return nil
        }
        if let known = commonNamedEntities[body] {
            return known
        }
        guard let bodyEl = try? SwiftSoup.parseBodyFragment(raw).body(),
              let textNode = bodyEl.getChildNodes().first as? TextNode
        else { return nil }
        let decoded = textNode.getWholeText()
        return decoded == raw ? nil : decoded
    }
}
