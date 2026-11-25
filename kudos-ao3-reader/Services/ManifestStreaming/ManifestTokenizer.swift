import Foundation

/// A syntax-level failure; the stager maps every case but `cancelled` to `invalidDocument(.notJSON)`.
nonisolated enum ManifestScanError: Error, Equatable {
    case syntax(Int, String)
    case tooDeep
    case unexpectedEnd
    case cancelled
}

/// Resource limits shared with Android (A-567 P2). New limits, pending owner approval: one constant each so they are easy to change.
/// Real manifests are nowhere near any of them. Record arrays, records and unknown values have no size limit.
nonisolated enum ManifestLimits {
    /// UTF-16 code units of one decoded object key.
    static let maxKeyUnits = 64 * 1024
    /// Source characters of one number token.
    static let maxNumberChars = 64 * 1024
    /// Source members (before first-wins dedupe) in any one object, at any depth, including inside skipped duplicate values.
    static let maxKeysPerObject = 262_144
    /// Source bytes of a known root value as written (whitespace included): `version`, `exportedAt`, `settings`,
    /// `pronunciations`, `exportedBy`, and a known section holding the wrong kind of value.
    static let maxRootValueBytes = 16 * 1024 * 1024
    /// UTF-16 units of distinct decoded keys held for dedupe across open objects. Ten Mi units is below the
    /// 182,361 × 60-unit shared boundary while preserving the existing approximately 32 MiB allocation guard.
    static let maxLiveKeyUnits = 10 * 1024 * 1024
    /// Nesting: containers on the path from the root, the root included.
    static let maxDepth = 512
}

/// What one open object remembers while it is scanned: its keys (exact UTF-16 sequences, no normalisation) for first-wins.
nonisolated struct ManifestObjectScan {
    var seen = Set<[UInt16]>()
    var cost = 0
    var members = 0
    /// Position of the comma before the current member, -1 for the first.
    var separator = -1
}

nonisolated enum ManifestValueKind: Equatable { case object, array, string, number, bool, null }

/// Strict JSON validator/splitter over a `ManifestInput`. It never holds more than one window.
nonisolated struct ManifestTokenizer {
    let input: ManifestInput
    var pos = 0
    private var base: UnsafeRawPointer?
    private var windowStart = 0
    private var windowEnd = 0
    /// The first resource limit met. Scanning goes on (a syntax error later still wins, `docs/MANIFEST_CONTRACT.md` § precedence)
    /// but nothing more is remembered or staged.
    private(set) var limitHit: String?
    private var liveKeyUnits = 0
    /// Source ranges of later duplicate members (`,"k":v`), at any depth, so a record can be rewritten first-wins before typed decode.
    private(set) var removals: [Range<Int>] = []
    /// A retained value can have arbitrarily many non-adjacent cuts. Flush them before this array grows with input size.
    var onRemovalBatch: (([Range<Int>]) throws -> Void)?
    var removalBatchSize = 4096
    private var whitespaceRun = 0
    /// A container beyond `ManifestLimits.maxDepth` was met. Scanning goes on (iteratively, remembering nothing) so a malformed
    /// tail still reports syntax first; the stager reports the depth outcome at EOF and stages nothing from then on.
    private(set) var depthExceeded = false

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

    mutating func noteLimit(_ message: String) { if limitHit == nil { limitHit = message } }

    /// Cancellation is polled here too (a gigabyte of whitespace is an unbounded loop); a poll that sees it makes the next
    /// token fail, and the stager reports cancellation ahead of any syntax outcome.
    mutating func skipWhitespace() {
        while let b = peek(), b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
            pos += 1
            whitespaceRun += 1
            if whitespaceRun & 0xFFFF == 0, Task.isCancelled { pos = Int.max / 2; return }
        }
    }

    mutating func takeRemovals() -> [Range<Int>] {
        defer { removals.removeAll(keepingCapacity: true) }
        return removals
    }

    func fail(_ message: String) -> ManifestScanError { .syntax(pos, message) }

    mutating func expectEnd() throws {
        skipWhitespace()
        if peek() != nil { throw fail("trailing content") }
    }

    /// Skips one JSON value (validating it) and returns its byte range and kind.
    mutating func skipValue(depth: Int = 0, trackDuplicates: Bool = true,
                            recordRemovals: Bool = true) throws -> (ManifestValueKind, Range<Int>) {
        if Task.isCancelled { throw ManifestScanError.cancelled }
        skipWhitespace()
        guard let b = peek() else { throw ManifestScanError.unexpectedEnd }
        let start = pos
        switch b {
        case UInt8(ascii: "{"):
            guard depth < ManifestLimits.maxDepth else { try skipDeep(); return (.object, start ..< pos) }
            pos += 1
            skipWhitespace()
            if peek() == UInt8(ascii: "}") { pos += 1; return (.object, start ..< pos) }
            var scan = ManifestObjectScan()
            defer { liveKeyUnits -= scan.cost }
            while true {
                skipWhitespace()
                guard peek() == UInt8(ascii: "\"") else { throw fail("object key") }
                let keyRange = try skipString()
                let duplicate = try noteKey(keyRange, in: &scan, retain: trackDuplicates).duplicate
                skipWhitespace()
                guard peek() == UInt8(ascii: ":") else { throw fail("colon") }
                pos += 1
                let (_, value) = try skipValue(depth: depth + 1, trackDuplicates: trackDuplicates && !duplicate,
                                               recordRemovals: recordRemovals && !duplicate)
                if recordRemovals, duplicate, scan.separator >= 0 {
                    let cut = scan.separator ..< value.upperBound
                    if let last = removals.last, last.upperBound == cut.lowerBound {
                        removals[removals.count - 1] = last.lowerBound ..< cut.upperBound
                    } else { removals.append(cut) }
                    if let onRemovalBatch, removals.count >= removalBatchSize {
                        try onRemovalBatch(removals)
                        removals.removeAll(keepingCapacity: true)
                    }
                }
                skipWhitespace()
                guard let c = peek() else { throw ManifestScanError.unexpectedEnd }
                pos += 1
                if c == UInt8(ascii: "}") { return (.object, start ..< pos) }
                guard c == UInt8(ascii: ",") else { throw fail("object separator") }
                scan.separator = pos - 1
                skipWhitespace()
                if peek() == UInt8(ascii: "}") { pos += 1; return (.object, start ..< pos) } // lenient, as today's route
            }
        case UInt8(ascii: "["):
            guard depth < ManifestLimits.maxDepth else { try skipDeep(); return (.array, start ..< pos) }
            pos += 1
            skipWhitespace()
            if peek() == UInt8(ascii: "]") { pos += 1; return (.array, start ..< pos) }
            while true {
                _ = try skipValue(depth: depth + 1, trackDuplicates: trackDuplicates,
                                  recordRemovals: recordRemovals)
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

    /// Validates one container nested past the limit without recursion and without keeping keys (an explicit one-byte-per-level
    /// stack, itself capped), so hostile nesting cannot overflow the call stack and a malformed tail is still found.
    private mutating func skipDeep() throws {
        depthExceeded = true
        var stack: [UInt8] = [] // 1 object, 0 array
        var expectValue = true
        func closer(_ isObject: Bool) -> UInt8 { isObject ? UInt8(ascii: "}") : UInt8(ascii: "]") }
        func key(_ t: inout ManifestTokenizer) throws {
            t.skipWhitespace()
            guard t.peek() == UInt8(ascii: "\"") else { throw t.fail("object key") }
            _ = try t.skipString()
            t.skipWhitespace()
            guard t.peek() == UInt8(ascii: ":") else { throw t.fail("colon") }
            t.pos += 1
        }
        while true {
            if Task.isCancelled { throw ManifestScanError.cancelled }
            skipWhitespace()
            if expectValue {
                guard let b = peek() else { throw ManifestScanError.unexpectedEnd }
                switch b {
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    guard stack.count < 1 << 24 else { throw ManifestScanError.tooDeep }
                    let isObject = b == UInt8(ascii: "{")
                    pos += 1
                    skipWhitespace()
                    stack.append(isObject ? 1 : 0)
                    if peek() == closer(isObject) { pos += 1; stack.removeLast(); expectValue = false; continue }
                    if isObject { try key(&self) }
                case UInt8(ascii: "\""): _ = try skipString(); expectValue = false
                case UInt8(ascii: "t"): try literal("true"); expectValue = false
                case UInt8(ascii: "f"): try literal("false"); expectValue = false
                case UInt8(ascii: "n"): try literal("null"); expectValue = false
                default: try number(); expectValue = false
                }
            } else {
                guard let top = stack.last else { return }
                let isObject = top == 1
                guard let c = peek() else { throw ManifestScanError.unexpectedEnd }
                pos += 1
                if c == closer(isObject) { stack.removeLast(); continue }
                guard c == UInt8(ascii: ",") else { throw fail("separator") }
                skipWhitespace()
                if peek() == closer(isObject) { pos += 1; stack.removeLast(); continue } // trailing comma, as elsewhere
                if isObject { try key(&self) }
                expectValue = true
            }
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
        while let b = peek(), b >= 0x30, b <= 0x39 {
            pos += 1; n += 1
            if n & 0xFFFF == 0 {
                if Task.isCancelled { throw ManifestScanError.cancelled }
                if n > ManifestLimits.maxNumberChars { noteLimit("number token longer than \(ManifestLimits.maxNumberChars)") }
            }
        }
        if n < min { throw fail("digits") }
    }

    private mutating func number() throws {
        let numberStart = pos
        if peek() == UInt8(ascii: "-") { pos += 1 }
        guard let first = peek() else { throw ManifestScanError.unexpectedEnd }
        if first == 0x30 { pos += 1 } else if first >= 0x31, first <= 0x39 { try digits(min: 1) } else { throw fail("number") }
        if peek() == UInt8(ascii: ".") { pos += 1; try digits(min: 1) }
        if let e = peek(), e == UInt8(ascii: "e") || e == UInt8(ascii: "E") {
            pos += 1
            if let s = peek(), s == UInt8(ascii: "+") || s == UInt8(ascii: "-") { pos += 1 }
            try digits(min: 1)
        }
        if pos - numberStart > ManifestLimits.maxNumberChars { noteLimit("number token longer than \(ManifestLimits.maxNumberChars)") }
    }

    // MARK: Keys

    /// Registers one object key (already scanned at `range`): counts the member, enforces the limits and returns whether an
    /// equal key came earlier in this object (the later value then loses). Equality is the exact UTF-16 sequence after
    /// unescaping, with no Unicode normalisation.
    mutating func noteKey(_ range: Range<Int>, in scan: inout ManifestObjectScan,
                          retain: Bool = true) throws -> (units: [UInt16]?, duplicate: Bool) {
        scan.members += 1
        if scan.members > ManifestLimits.maxKeysPerObject { noteLimit("more than \(ManifestLimits.maxKeysPerObject) members in one object") }
        guard limitHit == nil else { return (nil, false) }
        guard let units = try keyUnits(range) else { return (nil, false) }
        guard retain else { return (nil, false) }
        // A duplicate costs nothing, so it is found before the budget is checked (shared decision 19a).
        if scan.seen.contains(units) { return (units, true) }
        let cost = units.count
        guard liveKeyUnits + cost <= ManifestLimits.maxLiveKeyUnits else {
            noteLimit("decoded keys held at once exceed \(ManifestLimits.maxLiveKeyUnits) UTF-16 units")
            return (nil, false)
        }
        scan.seen.insert(units)
        liveKeyUnits += cost
        scan.cost += cost
        return (units, false)
    }

    /// Releases an object's key memory (the nested path does this itself; the stager's root loop calls it at the end).
    mutating func release(_ scan: ManifestObjectScan) { liveKeyUnits -= scan.cost }

    /// The decoded key as UTF-16 units; nil (and a limit noted) when it is over the unit limit.
    mutating func keyUnits(_ range: Range<Int>) throws -> [UInt16]? {
        guard range.count <= 6 * ManifestLimits.maxKeyUnits + 2 else { noteLimit("object key longer than \(ManifestLimits.maxKeyUnits) UTF-16 units"); return nil }
        var units: [UInt16] = []
        func decode(_ b: UnsafeRawBufferPointer) {
            let inner = UnsafeRawBufferPointer(rebasing: b[1 ..< b.count - 1])
            if !inner.contains(UInt8(ascii: "\\")) { units = Array(String(decoding: inner, as: UTF8.self).utf16); return }
            var bytes: [UInt8] = []
            var i = 0
            func hex4(_ at: Int) -> UInt32 { (0 ..< 4).reduce(0) { $0 << 4 | UInt32(Self.hexValue(inner[at + $1])) } }
            while i < inner.count {
                let c = inner[i]
                guard c == UInt8(ascii: "\\") else { bytes.append(c); i += 1; continue }
                let e = inner[i + 1]
                switch e {
                case UInt8(ascii: "b"): bytes.append(8); i += 2
                case UInt8(ascii: "f"): bytes.append(12); i += 2
                case UInt8(ascii: "n"): bytes.append(10); i += 2
                case UInt8(ascii: "r"): bytes.append(13); i += 2
                case UInt8(ascii: "t"): bytes.append(9); i += 2
                case UInt8(ascii: "u"):
                    var scalar = hex4(i + 2)
                    i += 6
                    if (0xD800 ... 0xDBFF).contains(scalar) { scalar = 0x10000 + ((scalar - 0xD800) << 10) + (hex4(i + 2) - 0xDC00); i += 6 }
                    bytes.append(contentsOf: Array(String(Unicode.Scalar(scalar) ?? "\u{FFFD}").utf8))
                default: bytes.append(e); i += 2 // \" \\ \/
                }
            }
            units = Array(String(decoding: bytes, as: UTF8.self).utf16)
        }
        if windowStart <= range.lowerBound, range.upperBound <= windowEnd, let base {
            decode(UnsafeRawBufferPointer(start: base + (range.lowerBound - windowStart), count: range.count))
        } else {
            let data = input.read(range)
            if let failure = input.failure { throw ManifestStreamError.io(failure) }
            guard data.count == range.count, data.count >= 2 else { throw ManifestStreamError.io("short key read") }
            data.withUnsafeBytes { decode($0) }
        }
        if units.count > ManifestLimits.maxKeyUnits { noteLimit("object key longer than \(ManifestLimits.maxKeyUnits) UTF-16 units"); return nil }
        return units
    }

    private static func hexValue(_ h: UInt8) -> UInt8 {
        switch h {
        case 0x30 ... 0x39: h - 0x30
        case 0x41 ... 0x46: h - 0x41 + 10
        default: h - 0x61 + 10
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


    /// A UTF-8 BOM at the very start is accepted (today's `JSONSerialization` route accepts it). The three bytes are read
    /// directly, so a first window shorter than three bytes does not hide one.
    mutating func skipBOM() {
        if pos == 0, input.length >= 3, input.read(0 ..< 3).elementsEqual([0xEF, 0xBB, 0xBF]) { pos = 3; base = nil; windowEnd = 0 }
    }
}
