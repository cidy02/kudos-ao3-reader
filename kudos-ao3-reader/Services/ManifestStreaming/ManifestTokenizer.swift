import Foundation

/// A syntax-level failure; the stager maps every case but `cancelled` to `invalidDocument(.notJSON)`.
nonisolated enum ManifestScanError: Error, Equatable {
    case syntax(Int, String)
    case tooDeep
    case unexpectedEnd
    case cancelled
}

nonisolated enum ManifestValueKind: Equatable { case object, array, string, number, bool, null }

/// Strict JSON validator/splitter over a `ManifestInput`. It never holds more than one window.
nonisolated struct ManifestTokenizer {
    let input: ManifestInput
    var pos = 0
    private var base: UnsafeRawPointer?
    private var windowStart = 0
    private var windowEnd = 0
    static let maxDepth = 512

    init(input: ManifestInput, at position: Int = 0) {
        self.input = input
        pos = position
    }

    private mutating func refill() {
        let w = input.window(at: pos)
        base = w.baseAddress
        windowStart = pos
        windowEnd = pos + w.count
    }

    @inline(__always) mutating func peek() -> UInt8? {
        if pos >= windowEnd || pos < windowStart { refill(); if pos >= windowEnd { return nil } }
        return base!.load(fromByteOffset: pos - windowStart, as: UInt8.self)
    }

    mutating func skipWhitespace() {
        while let b = peek(), b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { pos += 1 }
    }

    func fail(_ message: String) -> ManifestScanError { .syntax(pos, message) }

    mutating func expectEnd() throws {
        skipWhitespace()
        if peek() != nil { throw fail("trailing content") }
    }

    /// Skips one JSON value (validating it) and returns its byte range and kind.
    mutating func skipValue(depth: Int = 0) throws -> (ManifestValueKind, Range<Int>) {
        if Task.isCancelled { throw ManifestScanError.cancelled }
        skipWhitespace()
        guard let b = peek() else { throw ManifestScanError.unexpectedEnd }
        let start = pos
        switch b {
        case UInt8(ascii: "{"):
            guard depth <= Self.maxDepth else { throw ManifestScanError.tooDeep }
            pos += 1
            skipWhitespace()
            if peek() == UInt8(ascii: "}") { pos += 1; return (.object, start ..< pos) }
            while true {
                skipWhitespace()
                guard peek() == UInt8(ascii: "\"") else { throw fail("object key") }
                _ = try skipString()
                skipWhitespace()
                guard peek() == UInt8(ascii: ":") else { throw fail("colon") }
                pos += 1
                _ = try skipValue(depth: depth + 1)
                skipWhitespace()
                guard let c = peek() else { throw ManifestScanError.unexpectedEnd }
                pos += 1
                if c == UInt8(ascii: "}") { return (.object, start ..< pos) }
                guard c == UInt8(ascii: ",") else { throw fail("object separator") }
                skipWhitespace()
                if peek() == UInt8(ascii: "}") { pos += 1; return (.object, start ..< pos) } // lenient, as today's route
            }
        case UInt8(ascii: "["):
            guard depth <= Self.maxDepth else { throw ManifestScanError.tooDeep }
            pos += 1
            skipWhitespace()
            if peek() == UInt8(ascii: "]") { pos += 1; return (.array, start ..< pos) }
            while true {
                _ = try skipValue(depth: depth + 1)
                skipWhitespace()
                guard let c = peek() else { throw ManifestScanError.unexpectedEnd }
                pos += 1
                if c == UInt8(ascii: "]") { return (.array, start ..< pos) }
                guard c == UInt8(ascii: ",") else { throw fail("array separator") }
                skipWhitespace()
                if peek() == UInt8(ascii: "]") { pos += 1; return (.array, start ..< pos) } // lenient, as today's route
            }
        case UInt8(ascii: "\""):
            return (.string, try skipString())
        case UInt8(ascii: "t"): try literal("true"); return (.bool, start ..< pos)
        case UInt8(ascii: "f"): try literal("false"); return (.bool, start ..< pos)
        case UInt8(ascii: "n"): try literal("null"); return (.null, start ..< pos)
        default:
            try number()
            return (.number, start ..< pos)
        }
    }

    private mutating func literal(_ word: String) throws {
        for expected in word.utf8 {
            guard peek() == expected else { throw fail("literal") }
            pos += 1
        }
    }

    private mutating func digits(min: Int) throws {
        var n = 0
        while let b = peek(), b >= 0x30, b <= 0x39 { pos += 1; n += 1 }
        if n < min { throw fail("digits") }
    }

    private mutating func number() throws {
        if peek() == UInt8(ascii: "-") { pos += 1 }
        guard let first = peek() else { throw ManifestScanError.unexpectedEnd }
        if first == 0x30 { pos += 1 } else if first >= 0x31, first <= 0x39 { try digits(min: 1) } else { throw fail("number") }
        if peek() == UInt8(ascii: ".") { pos += 1; try digits(min: 1) }
        if let e = peek(), e == UInt8(ascii: "e") || e == UInt8(ascii: "E") {
            pos += 1
            if let s = peek(), s == UInt8(ascii: "+") || s == UInt8(ascii: "-") { pos += 1 }
            try digits(min: 1)
        }
    }

    /// Scans a string with a UTF-8 DFA whose state survives window refills. The hot loop runs over the current window.
    mutating func skipString() throws -> Range<Int> {
        let start = pos
        pos += 1 // opening quote
        var pending = 0 // continuation bytes still owed
        var lower: UInt8 = 0x80, upper: UInt8 = 0xBF
        while true {
            if Task.isCancelled { throw ManifestScanError.cancelled } // once per window (1 MiB): bounded latency even inside one huge value
            if pos >= windowEnd || pos < windowStart { refill(); if pos >= windowEnd { throw ManifestScanError.unexpectedEnd } }
            let p = base!
            let off = pos - windowStart
            let count = windowEnd - windowStart
            var i = off
            while i < count {
                let b = p.load(fromByteOffset: i, as: UInt8.self)
                if pending > 0 {
                    guard b >= lower, b <= upper else { pos = windowStart + i; throw fail("utf8") }
                    pending -= 1; lower = 0x80; upper = 0xBF
                    i += 1
                    continue
                }
                if b == UInt8(ascii: "\"") { pos = windowStart + i + 1; return start ..< pos }
                if b == UInt8(ascii: "\\") {
                    // Escapes are short; step out to the slow path (it refills across the window edge itself).
                    pos = windowStart + i + 1
                    try escape()
                    break
                }
                if b < 0x20 { pos = windowStart + i; throw fail("control character") }
                if b < 0x80 { i += 1; continue }
                switch b {
                case 0xC2 ... 0xDF: pending = 1
                case 0xE0: pending = 2; lower = 0xA0
                case 0xE1 ... 0xEC, 0xEE ... 0xEF: pending = 2
                case 0xED: pending = 2; upper = 0x9F
                case 0xF0: pending = 3; lower = 0x90
                case 0xF1 ... 0xF3: pending = 3
                case 0xF4: pending = 3; upper = 0x8F
                default: pos = windowStart + i; throw fail("utf8")
                }
                // The first continuation byte has the tightened bounds; later ones are plain 80...BF.
                let tight = (lower, upper)
                i += 1
                if i < count {
                    let c = p.load(fromByteOffset: i, as: UInt8.self)
                    guard c >= tight.0, c <= tight.1 else { pos = windowStart + i; throw fail("utf8") }
                    pending -= 1; lower = 0x80; upper = 0xBF
                    i += 1
                } else {
                    // Window ended right after a lead byte: the bounds for the next byte must be kept.
                    lower = tight.0; upper = tight.1
                }
            }
            if i >= count { pos = windowStart + count } // consumed the window; loop refills
        }
    }

    private mutating func hex4() throws -> Int {
        var v = 0
        for _ in 0 ..< 4 {
            guard let h = peek() else { throw ManifestScanError.unexpectedEnd }
            switch h {
            case 0x30 ... 0x39: v = v << 4 | Int(h - 0x30)
            case 0x41 ... 0x46: v = v << 4 | Int(h - 0x41 + 10)
            case 0x61 ... 0x66: v = v << 4 | Int(h - 0x61 + 10)
            default: throw fail("\\u")
            }
            pos += 1
        }
        return v
    }

    private mutating func escape() throws {
        guard let c = peek() else { throw ManifestScanError.unexpectedEnd }
        pos += 1
        switch c {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"), UInt8(ascii: "b"), UInt8(ascii: "f"),
             UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
            return
        case UInt8(ascii: "u"):
            let first = try hex4()
            if (0xD800 ... 0xDBFF).contains(first) { // today's route rejects a lone surrogate
                guard peek() == UInt8(ascii: "\\") else { throw fail("lone high surrogate") }
                pos += 1
                guard peek() == UInt8(ascii: "u") else { throw fail("lone high surrogate") }
                pos += 1
                guard (0xDC00 ... 0xDFFF).contains(try hex4()) else { throw fail("bad low surrogate") }
            } else if (0xDC00 ... 0xDFFF).contains(first) {
                throw fail("lone low surrogate")
            }
        default:
            throw fail("escape")
        }
    }


    /// A UTF-8 BOM at the very start is accepted (today's `JSONSerialization` route accepts it).
    mutating func skipBOM() {
        if pos == 0, input.window(at: 0).starts(with: [0xEF, 0xBB, 0xBF]) { pos = 3; base = nil; windowEnd = 0 }
    }
}
