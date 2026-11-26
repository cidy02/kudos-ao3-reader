import Foundation

/// Single-pass UTF-16 scanner that computes the 1-based paragraph number at a UTF-16 offset
/// in AO3 / Rich Text chapter HTML (or blank-line-delimited plain text).
nonisolated struct HTMLParagraphScanner {
    private static let leafBlockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "dt", "dd", "pre", "summary",
    ]
    private static let containerBlockTags: Set<String> = ["blockquote", "div"]

    private struct ParsedTag {
        var name: String?
        var isClosing: Bool = false
        var isSelfClosing: Bool = false
        var nextIndex: Int
    }

    let units: [UInt16]
    let limit: Int

    private var blockParagraphs = 0
    private var sawAnyBlockTag = false
    // `false` = open container block not yet counted; `true` = counted or has a child block.
    private var containerCountedStack: [Bool] = []
    private var plainParagraphs = 1
    private var sawPlainNonWhitespace = false
    private var newlineCount = 0

    init(units: [UInt16], limit: Int) {
        self.units = units
        self.limit = limit
    }

    mutating func scan() -> Int {
        var index = 0
        while index < units.count {
            if units[index] == 0x3C { // '<'
                if index > limit { break }
                let parsed = parseTag(at: index)
                index = parsed.nextIndex
                applyTag(parsed)
                continue
            }
            if index >= limit { break }
            consumeTextUnit(at: index)
            index += 1
        }

        if sawAnyBlockTag {
            if containerCountedStack.last == false,
               index < units.count,
               units[index] != 0x3C,
               !isASCIIWhitespace(units[index]) {
                blockParagraphs += 1
            }
            return max(1, blockParagraphs)
        }
        if sawPlainNonWhitespace, newlineCount >= 2 {
            plainParagraphs += 1
        }
        return plainParagraphs
    }

    private mutating func applyTag(_ parsed: ParsedTag) {
        guard let name = parsed.name else { return }
        if parsed.isClosing {
            if Self.containerBlockTags.contains(name), !containerCountedStack.isEmpty {
                containerCountedStack.removeLast()
            }
        } else if Self.leafBlockTags.contains(name) {
            sawAnyBlockTag = true
            blockParagraphs += 1
            if !containerCountedStack.isEmpty {
                containerCountedStack[containerCountedStack.count - 1] = true
            }
        } else if Self.containerBlockTags.contains(name) {
            sawAnyBlockTag = true
            if !parsed.isSelfClosing {
                containerCountedStack.append(false)
            }
        }
    }

    private mutating func consumeTextUnit(at index: Int) {
        let unit = units[index]
        if !isASCIIWhitespace(unit) {
            if containerCountedStack.last == false {
                blockParagraphs += 1
                containerCountedStack[containerCountedStack.count - 1] = true
            }
            if !sawAnyBlockTag {
                if sawPlainNonWhitespace, newlineCount >= 2 {
                    plainParagraphs += 1
                }
                sawPlainNonWhitespace = true
                newlineCount = 0
            }
        } else if !sawAnyBlockTag {
            let nextUnit = index + 1 < units.count ? units[index + 1] : nil
            if unit == 0x0A || (unit == 0x0D && nextUnit != 0x0A) {
                newlineCount += 1
            }
        }
    }

    private func parseTag(at start: Int) -> ParsedTag {
        let count = units.count
        if ChapterEditorAnnotationAnchoring.startsComment(in: units, at: start) {
            return ParsedTag(
                nextIndex: ChapterEditorAnnotationAnchoring.endOfComment(in: units, from: start + 4)
            )
        }

        var cursor = start + 1
        var isClosing = false
        if cursor < count, units[cursor] == 0x2F { // '/'
            isClosing = true
            cursor += 1
        }

        let nameStart = cursor
        while cursor < count, isASCIIAlphaNumeric(units[cursor]) {
            cursor += 1
        }
        guard cursor > nameStart else {
            return ParsedTag(nextIndex: start + 1)
        }

        let tagName = lowercaseASCII(from: nameStart, to: cursor)
        let closing = scanTagEnd(from: cursor)
        return ParsedTag(
            name: tagName,
            isClosing: isClosing,
            isSelfClosing: closing.isSelfClosing,
            nextIndex: closing.nextIndex
        )
    }

    private func lowercaseASCII(from start: Int, to end: Int) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(end - start)
        for idx in start..<end {
            let code = units[idx]
            let lower = (code >= 0x41 && code <= 0x5A) ? (code + 32) : code
            bytes.append(UInt8(truncatingIfNeeded: lower))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func scanTagEnd(from start: Int) -> (isSelfClosing: Bool, nextIndex: Int) {
        let count = units.count
        var cursor = start
        var quote: UInt16 = 0
        var lastNonSpace: UInt16 = 0

        while cursor < count {
            let unit = units[cursor]
            if quote != 0 {
                if unit == quote { quote = 0 }
            } else if unit == 0x22 || unit == 0x27 {
                quote = unit
            } else if unit == 0x3E { // '>'
                return (lastNonSpace == 0x2F, cursor + 1)
            } else if !isASCIIWhitespace(unit) {
                lastNonSpace = unit
            }
            cursor += 1
        }
        return (false, count)
    }

    private func isASCIIWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x0C
    }

    private func isASCIIAlphaNumeric(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A)
            || (unit >= 0x61 && unit <= 0x7A)
            || (unit >= 0x30 && unit <= 0x39)
    }
}
