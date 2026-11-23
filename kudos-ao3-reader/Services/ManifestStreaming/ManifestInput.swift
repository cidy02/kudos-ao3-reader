import Darwin
import Foundation

// T-567 P2: the byte side of the streaming manifest reader. Called by no production path yet (P4/P5 wire it).

/// Why a streaming read of `manifest.json` did not produce a staged run. Each case is a different caller decision
/// (see `docs/MANIFEST_CONTRACT.md`): only `invalidDocument(.notJSON)` makes a live manifest eligible for the `.bak` fallback.
nonisolated enum ManifestStreamError: Error, Equatable {
    enum InvalidReason: Equatable {
        /// Not a JSON document (syntax, bad UTF-8, trailing content, nesting over 512, top-level scalar, truncation).
        case notJSON
        /// Whole JSON that is not a decodable manifest (missing required key, wrong kind, a record that does not decode).
        case schema
    }

    case invalidDocument(InvalidReason)
    case unsupportedVersion(Int)
    /// The source or the staging database could not be read or written.
    case io(String)
    case cancelled
    /// No room to stage (disk preflight, or SQLite reported the disk full).
    case resourceExhausted(String)
}

/// The bytes of one manifest, whatever holds them. The tokenizer never holds more than one window.
nonisolated protocol ManifestInput: AnyObject {
    var length: Int { get }
    /// Up to `manifestWindowSize` bytes starting at `offset`; valid until the next call. Empty at EOF or on failure.
    func window(at offset: Int) -> UnsafeRawBufferPointer
    /// Copies `range` out. Callers bound the size (a record that fits the typed-decode budget).
    func read(_ range: Range<Int>) -> Data
    /// Set by a failed read; the stager reports it as `.io` whatever the tokenizer saw next.
    var failure: String? { get }
}

nonisolated let manifestWindowSize = 1 << 20

/// Buffered `pread` over a file, or over a byte range of one (a stored ZIP entry).
nonisolated final class ManifestFileInput: ManifestInput {
    let length: Int
    private(set) var failure: String?
    private let fd: Int32
    private let base: Int
    private let buffer = UnsafeMutableRawPointer.allocate(byteCount: manifestWindowSize, alignment: 16)

    init(url: URL, range: Range<Int>? = nil) throws {
        fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw ManifestStreamError.io("open: errno \(errno)") }
        var st = stat()
        guard fstat(fd, &st) == 0 else { close(fd); throw ManifestStreamError.io("fstat: errno \(errno)") }
        base = range?.lowerBound ?? 0
        length = range?.count ?? Int(st.st_size)
        if let range, range.upperBound > Int(st.st_size) {
            close(fd)
            throw ManifestStreamError.io("range beyond end of file")
        }
    }

    deinit { close(fd); buffer.deallocate() }

    func window(at offset: Int) -> UnsafeRawBufferPointer {
        guard offset < length, failure == nil else { return UnsafeRawBufferPointer(start: nil, count: 0) }
        let n = pread(fd, buffer, min(manifestWindowSize, length - offset), off_t(base + offset))
        guard n > 0 else {
            failure = n < 0 ? "pread: errno \(errno)" : "file shorter than expected"
            return UnsafeRawBufferPointer(start: nil, count: 0)
        }
        return UnsafeRawBufferPointer(start: buffer, count: n)
    }

    func read(_ range: Range<Int>) -> Data {
        var data = Data(count: range.count)
        var done = 0
        while done < range.count, failure == nil {
            let n = data.withUnsafeMutableBytes { pread(fd, $0.baseAddress! + done, range.count - done, off_t(base + range.lowerBound + done)) }
            if n <= 0 { failure = n < 0 ? "pread: errno \(errno)" : "file shorter than expected"; break }
            done += n
        }
        return data
    }
}

/// In-memory bytes (tests, and callers that already hold a small manifest).
nonisolated final class ManifestDataInput: ManifestInput {
    let length: Int
    var failure: String? { nil }
    private let bytes: UnsafeMutableRawBufferPointer

    init(_ data: Data) {
        length = data.count
        bytes = .allocate(byteCount: max(data.count, 1), alignment: 1)
        data.copyBytes(to: bytes.bindMemory(to: UInt8.self))
    }

    deinit { bytes.deallocate() }

    func window(at offset: Int) -> UnsafeRawBufferPointer {
        guard offset < length else { return UnsafeRawBufferPointer(start: nil, count: 0) }
        return UnsafeRawBufferPointer(rebasing: bytes[offset ..< length])
    }

    func read(_ range: Range<Int>) -> Data { Data(bytes[range]) }
}

extension ManifestInput {
    /// The chunked-payload view of a value: bounded pieces, never the whole value.
    func forEachChunk(of range: Range<Int>, size: Int, _ body: (UnsafeRawBufferPointer) throws -> Void) rethrows {
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
