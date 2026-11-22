import Darwin
import Foundation
@testable import Kudos

// PROTOTYPE ONLY (T-567 P1). Not wired into production. A validating, record-at-a-time manifest.json reader over a
// chunked byte-source interface, in two flavours: a buffered one (pread into one reusable window) and a mapped-spool
// one (the bytes are copied once to a private spool file and mapped; windows point into the mapping). The tokenizer is
// shared, so any difference between the flavours is the source, not the parser.

/// One interface for the bytes of the manifest, whatever holds them.
protocol ManifestByteSource: AnyObject {
    var length: Int { get }
    /// Up to `windowSize` bytes starting at `offset`; valid until the next call. Empty at EOF.
    func window(at offset: Int) -> UnsafeRawBufferPointer
    /// Copies `range` out. Callers bound the size (records are decoded one at a time).
    func read(_ range: Range<Int>) -> Data
}

extension ManifestByteSource {
    /// The chunked-payload view of a value: bounded pieces, never the whole value.
    func forEachChunk(of range: Range<Int>, size: Int = 64 * 1024, _ body: (UnsafeRawBufferPointer) throws -> Void) rethrows {
        var offset = range.lowerBound
        while offset < range.upperBound {
            let w = window(at: offset)
            guard !w.isEmpty else { return }
            let n = min(size, w.count, range.upperBound - offset)
            try body(UnsafeRawBufferPointer(rebasing: w[0 ..< n]))
            offset += n
        }
    }
}

let manifestWindowSize = 1 << 20

final class BufferedFileSource: ManifestByteSource {
    let length: Int
    private let fd: Int32
    private let base: Int
    private let buffer = UnsafeMutableRawPointer.allocate(byteCount: manifestWindowSize, alignment: 16)

    /// `range` selects the manifest bytes inside a larger file (a stored ZIP entry), or the whole file by default.
    init(url: URL, range: Range<Int>? = nil) throws {
        fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        let size = Int((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0)
        base = range?.lowerBound ?? 0
        length = range.map { $0.count } ?? size
    }

    deinit { close(fd); buffer.deallocate() }

    func window(at offset: Int) -> UnsafeRawBufferPointer {
        guard offset < length else { return UnsafeRawBufferPointer(start: nil, count: 0) }
        let n = pread(fd, buffer, min(manifestWindowSize, length - offset), off_t(base + offset))
        return UnsafeRawBufferPointer(start: buffer, count: max(0, n))
    }

    func read(_ range: Range<Int>) -> Data {
        var data = Data(count: range.count)
        data.withUnsafeMutableBytes { _ = pread(fd, $0.baseAddress, range.count, off_t(base + range.lowerBound)) }
        return data
    }
}

final class MappedSpoolSource: ManifestByteSource {
    let length: Int
    let spoolURL: URL
    private let pointer: UnsafeMutableRawPointer?
    private let dropBehind: Bool
    private var lastWindowStart = 0

    /// Spools `source`'s bytes to `spoolURL` in 1 MiB chunks (so no copy is ever resident), then maps the spool.
    init(copying source: ManifestByteSource, to spoolURL: URL, dropBehind: Bool = false) throws {
        self.spoolURL = spoolURL
        self.dropBehind = dropBehind
        FileManager.default.createFile(atPath: spoolURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: spoolURL)
        var offset = 0
        while offset < source.length {
            let w = source.window(at: offset)
            guard !w.isEmpty else { break }
            try out.write(contentsOf: Data(bytes: w.baseAddress!, count: w.count))
            offset += w.count
        }
        try out.close()
        length = offset
        let fd = open(spoolURL.path, O_RDONLY)
        guard fd >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        defer { close(fd) }
        if length > 0 {
            let p = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0)
            guard p != MAP_FAILED else { throw CocoaError(.fileReadUnknown) }
            madvise(p, length, MADV_SEQUENTIAL)
            pointer = p
        } else {
            pointer = nil
        }
    }

    deinit {
        if let pointer { munmap(pointer, length) }
        try? FileManager.default.removeItem(at: spoolURL)
    }

    func window(at offset: Int) -> UnsafeRawBufferPointer {
        guard let pointer, offset < length else { return UnsafeRawBufferPointer(start: nil, count: 0) }
        if dropBehind, offset > lastWindowStart + manifestWindowSize {
            // Hand the pages we have finished with back to the system.
            let start = lastWindowStart & ~0x3FFF
            madvise(pointer + start, offset - start, MADV_DONTNEED)
        }
        lastWindowStart = offset
        return UnsafeRawBufferPointer(start: pointer + offset, count: min(manifestWindowSize, length - offset))
    }

    func read(_ range: Range<Int>) -> Data { Data(bytes: pointer! + range.lowerBound, count: range.count) }
}

/// An in-memory source, for the corpus (no files).
final class DataSource: ManifestByteSource {
    private let data: Data
    var length: Int { data.count }
    init(_ data: Data) { self.data = Data(data) }
    func window(at offset: Int) -> UnsafeRawBufferPointer {
        guard offset < data.count else { return UnsafeRawBufferPointer(start: nil, count: 0) }
        // Corpus documents are small; hand back the whole tail (the scanner copes with any window size).
        return data.withUnsafeBytes { UnsafeRawBufferPointer(start: $0.baseAddress! + offset, count: data.count - offset) }
    }
    func read(_ range: Range<Int>) -> Data { data.subdata(in: range) }
}

/// First entry of a ZIP, if it is stored (what `MiniZip.ArchiveWriter` and the exporter always produce): the byte range
/// of its data. A deflated manifest would need a streaming inflater (P2); this prototype reports nil for that.
func storedFirstEntryRange(of zipURL: URL, named name: String = "manifest.json") -> Range<Int>? {
    guard let h = try? FileHandle(forReadingFrom: zipURL), let head = try? h.read(upToCount: 30 + 512), head.count >= 30 else { return nil }
    try? h.close()
    func u16(_ i: Int) -> Int { Int(head[i]) | Int(head[i + 1]) << 8 }
    func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
    guard u32(0) == 0x0403_4B50, u16(8) == 0 else { return nil } // signature, method 0 = stored
    let nameLength = u16(26), extraLength = u16(28)
    guard head.count >= 30 + nameLength, String(decoding: head[30 ..< 30 + nameLength], as: UTF8.self) == name else { return nil }
    var size = u32(22)
    if size == 0xFFFF_FFFF { // ZIP64 extra field carries the sizes
        let extraStart = 30 + nameLength
        guard head.count >= extraStart + extraLength, extraLength >= 12 else { return nil }
        var i = extraStart
        while i + 4 <= extraStart + extraLength {
            let id = u16(i), len = u16(i + 2)
            if id == 1 { size = Int(head[i + 4]) | Int(head[i + 5]) << 8 | Int(head[i + 6]) << 16 | Int(head[i + 7]) << 24
                | Int(head[i + 8]) << 32 | Int(head[i + 9]) << 40 | Int(head[i + 10]) << 48 | Int(head[i + 11]) << 56
                break }
            i += 4 + len
        }
    }
    let start = 30 + nameLength + extraLength
    return start ..< start + size
}

enum ManifestScanError: Error, Equatable {
    case syntax(Int, String)
    case tooDeep
    case unexpectedEnd
}

/// One top-level member of the manifest object.
struct ManifestMember {
    enum Kind { case object, array, string, number, bool, null }
    let key: String
    let kind: Kind
    let range: Range<Int>
}

/// Strict JSON validator/splitter over a `ManifestByteSource`. It never holds more than one window.
struct ManifestScanner {
    let source: ManifestByteSource
    private(set) var pos = 0
    private var base: UnsafeRawPointer?
    private var windowStart = 0
    private var windowEnd = 0
    static let maxDepth = 512

    init(source: ManifestByteSource, at position: Int = 0) {
        self.source = source
        pos = position
    }

    private mutating func refill() {
        let w = source.window(at: pos)
        base = w.baseAddress
        windowStart = pos
        windowEnd = pos + w.count
    }

    @inline(__always) private mutating func peek() -> UInt8? {
        if pos >= windowEnd || pos < windowStart { refill(); if pos >= windowEnd { return nil } }
        return base!.load(fromByteOffset: pos - windowStart, as: UInt8.self)
    }

    private mutating func skipWhitespace() {
        while let b = peek(), b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { pos += 1 }
    }

    private func fail(_ message: String) -> ManifestScanError { .syntax(pos, message) }

    mutating func expectEnd() throws {
        skipWhitespace()
        if peek() != nil { throw fail("trailing content") }
    }

    /// Skips one JSON value (validating it) and returns its byte range and kind.
    mutating func skipValue(depth: Int = 0) throws -> (ManifestMember.Kind, Range<Int>) {
        guard depth <= Self.maxDepth else { throw ManifestScanError.tooDeep }
        try Task.checkCancellation()
        skipWhitespace()
        guard let b = peek() else { throw ManifestScanError.unexpectedEnd }
        let start = pos
        switch b {
        case UInt8(ascii: "{"):
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
    private mutating func skipString() throws -> Range<Int> {
        let start = pos
        pos += 1 // opening quote
        var pending = 0 // continuation bytes still owed
        var lower: UInt8 = 0x80, upper: UInt8 = 0xBF
        while true {
            try Task.checkCancellation() // once per window (1 MiB): bounded latency even inside one huge value
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

    /// Validates the document to EOF and returns its top-level members (a duplicate key keeps the first value, as today's JSONDecoder does).
    mutating func indexTopLevel() throws -> [String: ManifestMember] {
        if pos == 0, source.window(at: 0).starts(with: [0xEF, 0xBB, 0xBF]) { pos = 3; base = nil; windowEnd = 0 } // BOM: accepted today
        skipWhitespace()
        // A UTF-8 BOM is not JSON; today's routes decide that (see the differential corpus).
        guard peek() == UInt8(ascii: "{") else {
            let (kind, _) = try skipValue()
            try expectEnd()
            // JSONSerialization (default options) accepts only an object or an array at the top level.
            guard kind == .array else { throw fail("top-level scalar") }
            return [:]
        }
        var members: [String: ManifestMember] = [:]
        pos += 1
        skipWhitespace()
        if peek() == UInt8(ascii: "}") { pos += 1; try expectEnd(); return members }
        while true {
            skipWhitespace()
            guard peek() == UInt8(ascii: "\"") else { throw fail("object key") }
            let keyRange = try skipString()
            skipWhitespace()
            guard peek() == UInt8(ascii: ":") else { throw fail("colon") }
            pos += 1
            let (kind, range) = try skipValue(depth: 1)
            let keyBytes = source.read(keyRange.count > 1 << 16 ? keyRange.lowerBound ..< keyRange.lowerBound + 2 : keyRange)
            let key = (try? JSONSerialization.jsonObject(with: keyBytes, options: .fragmentsAllowed) as? String) ?? "\u{0}invalid"
            if members[key] == nil { members[key] = ManifestMember(key: key, kind: kind, range: range) } // first wins, as today's decoder
            skipWhitespace()
            guard let c = peek() else { throw ManifestScanError.unexpectedEnd }
            pos += 1
            if c == UInt8(ascii: "}") { break }
            guard c == UInt8(ascii: ",") else { throw fail("object separator") }
            skipWhitespace()
            if peek() == UInt8(ascii: "}") { pos += 1; break }
        }
        try expectEnd()
        return members
    }

    /// Byte ranges of the elements of an already-validated array value.
    static func elementRanges(of arrayRange: Range<Int>, in source: ManifestByteSource, _ body: (Range<Int>) throws -> Void) throws {
        var s = ManifestScanner(source: source, at: arrayRange.lowerBound + 1)
        s.skipWhitespace()
        if s.peek() == UInt8(ascii: "]") { return }
        while true {
            let (_, r) = try s.skipValue(depth: 1)
            try body(r)
            s.skipWhitespace()
            guard let c = s.peek() else { return }
            s.pos += 1
            if c == UInt8(ascii: "]") { return }
        }
    }
}

/// Today's decoder configuration (`KudosBackupContents.makeDecoder` is private).
enum ManifestPrototypeDecoder {
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) static let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractional.date(from: string) { return KudosBackupContents.clampedArchiveDate(date) }
            if let date = whole.date(from: string) { return KudosBackupContents.clampedArchiveDate(date) }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
        }
        return decoder
    }
}

enum ManifestParseOutcome: Equatable {
    case notJSON
    case schema
    case unsupportedVersion(Int)
    case ok(KudosBackupManifest)

    var label: String {
        switch self {
        case .notJSON: "notJSON"
        case .schema: "schema"
        case let .unsupportedVersion(v): "unsupportedVersion(\(v))"
        case .ok: "ok"
        }
    }
}

/// Record-at-a-time typed reader. `over` a validated index, it hands each element to `body` and keeps nothing.
struct StreamingManifestReader {
    let source: ManifestByteSource
    let members: [String: ManifestMember]
    let decoder = ManifestPrototypeDecoder.make()
    /// Values longer than this are validated but not typed-decoded (the >64 MiB opaque case): reported, not held.
    var maxTypedElementBytes = 64 << 20
    private(set) var deferredElements = 0

    init(source: ManifestByteSource) throws {
        self.source = source
        var scanner = ManifestScanner(source: source)
        members = try scanner.indexTopLevel()
    }

    func decodeValue<T: Decodable>(_ m: ManifestMember, as type: T.Type = T.self) throws -> T {
        try decoder.decode(T.self, from: source.read(m.range))
    }

    /// `decode` semantics for an array section: every element must decode; the value must be an array.
    func forEachElement<T: Decodable>(_ m: ManifestMember, as type: T.Type = T.self, _ body: (T) throws -> Void) throws {
        guard m.kind == .array else {
            throw DecodingError.typeMismatch(T.self, .init(codingPath: [], debugDescription: "not an array"))
        }
        try ManifestScanner.elementRanges(of: m.range, in: source) { r in
            try body(decoder.decode(T.self, from: source.read(r)))
        }
    }

    /// `LossyArray` semantics: a non-array section is nil, a bad element is skipped.
    func forEachLossy<T: Decodable>(_ m: ManifestMember, as type: T.Type = T.self, deferred: inout Int, _ body: (T) throws -> Void) throws {
        guard m.kind == .array else { return }
        var skipped = 0
        try ManifestScanner.elementRanges(of: m.range, in: source) { r in
            if r.count > maxTypedElementBytes { skipped += 1; return }
            if let value = try? decoder.decode(T.self, from: source.read(r)) { try body(value) }
        }
        deferred += skipped
    }

    /// Whole-manifest assembly with `KudosBackupManifest.init(from:)`'s rules, for the differential. (The memory
    /// measurement uses `forEachElement` and keeps nothing.)
    func assemble() throws -> ManifestParseOutcome {
        func required<T: Decodable>(_ key: String, _: T.Type) throws -> [T] {
            guard let m = members[key], m.kind != .null else { throw DecodingError.keyNotFound(CodingKeys(key), .init(codingPath: [], debugDescription: key)) }
            var out: [T] = []
            try forEachElement(m, as: T.self) { out.append($0) }
            return out
        }
        func optional<T: Decodable>(_ key: String, _: T.Type) throws -> [T]? {
            guard let m = members[key], m.kind != .null else { return nil }
            var out: [T] = []
            try forEachElement(m, as: T.self) { out.append($0) }
            return out
        }
        do {
            guard let versionMember = members["version"], versionMember.kind != .null else { return .schema }
            let version: Int = try decodeValue(versionMember)
            guard let exportedMember = members["exportedAt"], exportedMember.kind != .null else { return .schema }
            let exportedAt: Date = try decodeValue(exportedMember)
            let works = try required("works", KudosBackupWork.self)
            let bookmarks = try required("bookmarks", KudosBackupBookmark.self)
            let fonts = try required("fonts", KudosBackupFont.self)
            let collections = try optional("collections", KudosBackupCollection.self) ?? []
            let queues = try optional("readingQueues", KudosBackupReadingQueue.self) ?? []
            let memberships = try optional("readingQueueMemberships", KudosBackupReadingQueueMembership.self) ?? []
            let annotations = try optional("annotations", KudosBackupAnnotation.self) ?? []
            let searches = try optional("savedSearches", KudosBackupSavedSearch.self) ?? []
            let sessions = try optional("readingSessions", KudosBackupReadingSession.self)
            let favorites = try optional("readingFavorites", KudosBackupReadingFavorite.self)
            let watermarks = try optional("fandomReadWatermarks", KudosBackupFandomReadWatermark.self)
            let followed = try optional("followedTags", KudosBackupFollowedTag.self)
            let aliases = try optional("tagAliases", KudosBackupTagAlias.self)
            guard let settingsMember = members["settings"], settingsMember.kind != .null else { return .schema }
            let settings: KudosBackupSettings = try decodeValue(settingsMember)
            var pron = KudosBackupPronunciations.empty
            if let m = members["pronunciations"], m.kind != .null { pron = try decodeValue(m) }
            let tombstones = try optional("tombstones", KudosBackupTombstone.self) ?? []
            var manifest = KudosBackupManifest(
                version: version, exportedAt: exportedAt, works: works, bookmarks: bookmarks, fonts: fonts,
                collections: collections, readingQueues: queues, readingQueueMemberships: memberships,
                annotations: annotations, savedSearches: searches, readingSessions: sessions,
                readingFavorites: favorites, fandomReadWatermarks: watermarks, followedTags: followed,
                tagAliases: aliases, settings: settings, pronunciations: pron, tombstones: tombstones
            )
            manifest.omittedKeys = Set(["collections", "readingQueues", "annotations", "savedSearches"].filter {
                members[$0] == nil || members[$0]?.kind == .null
            })
            var deferred = 0
            if let m = members["writingRecovery"], m.kind == .array {
                var v: [KudosBackupRecoveryCopy] = []
                try forEachLossy(m, as: KudosBackupRecoveryCopy.self, deferred: &deferred) { v.append($0) }
                manifest.writingRecovery = v
            }
            if let m = members["documents"], m.kind == .array {
                var v: [KudosBackupDocument] = []
                try forEachLossy(m, as: KudosBackupDocument.self, deferred: &deferred) { v.append($0) }
                manifest.documents = v
            }
            guard KudosBackupManifest.supportedVersions.contains(manifest.version) else { return .unsupportedVersion(manifest.version) }
            return .ok(manifest)
        } catch {
            return .schema
        }
    }

    private struct CodingKeys: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// The bounded walk used for memory/time measurement: every record decoded, one at a time, nothing kept.
    func walkAll() throws -> (records: Int, deferred: Int) {
        var records = 0, deferred = 0
        func count<T: Decodable>(_ key: String, _: T.Type, lossy: Bool = false) throws {
            guard let m = members[key], m.kind == .array else { return }
            if lossy { try forEachLossy(m, as: T.self, deferred: &deferred) { _ in records += 1 } }
            else { try forEachElement(m, as: T.self) { _ in records += 1 } }
        }
        try count("works", KudosBackupWork.self)
        try count("bookmarks", KudosBackupBookmark.self)
        try count("readingSessions", KudosBackupReadingSession.self)
        try count("tombstones", KudosBackupTombstone.self)
        try count("writingRecovery", KudosBackupRecoveryCopy.self, lossy: true)
        try count("documents", KudosBackupDocument.self, lossy: true)
        return (records, deferred)
    }
}

/// Today's route outcome for the same bytes: `JSONSerialization` (the live-route predicate), then `decodeManifest`.
func todaysOutcome(_ data: Data) -> ManifestParseOutcome {
    guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return .notJSON }
    do {
        return .ok(try KudosBackupContents.decodeManifest(data))
    } catch KudosBackupError.unsupportedVersion(let v) {
        return .unsupportedVersion(v)
    } catch {
        return .schema
    }
}

func prototypeOutcome(_ source: ManifestByteSource) -> ManifestParseOutcome {
    do {
        let reader = try StreamingManifestReader(source: source)
        // JSONSerialization (default options) accepts only an object or array at the top level.
        return try reader.assemble()
    } catch {
        return .notJSON
    }
}
