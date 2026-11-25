import Foundation

/// Ordered duplicate-member cuts for one kept value. A tiny binary spill keeps memory flat when an oversized
/// deferred lossy record contains many non-adjacent duplicates. The stager deletes the spill after writing the row.
nonisolated final class ManifestRemovalSpool {
    private let directory: URL
    private let batchSize: Int
    private var buffered: [Range<Int>] = []
    private var fileURL: URL?
    private var writer: FileHandle?
    private(set) var hasRanges = false
    private(set) var peakBufferedCount = 0

    init(directory: URL, batchSize: Int = 4096) {
        self.directory = directory
        self.batchSize = max(1, batchSize)
    }

    deinit { try? discard() }

    func append(_ ranges: [Range<Int>]) throws {
        for range in ranges {
            buffered.append(range)
            hasRanges = true
            peakBufferedCount = max(peakBufferedCount, buffered.count)
            if buffered.count >= batchSize { try flush() }
        }
    }

    private func flush() throws {
        guard !buffered.isEmpty else { return }
        if writer == nil {
            let url = directory.appendingPathComponent("cuts-\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw ManifestStreamError.io("create duplicate-cut spill")
            }
            fileURL = url
            writer = try FileHandle(forWritingTo: url)
        }
        var bytes = Data(capacity: buffered.count * 16)
        for range in buffered {
            var lower = Int64(range.lowerBound).littleEndian
            var upper = Int64(range.upperBound).littleEndian
            withUnsafeBytes(of: &lower) { bytes.append(contentsOf: $0) }
            withUnsafeBytes(of: &upper) { bytes.append(contentsOf: $0) }
        }
        try writer?.write(contentsOf: bytes)
        buffered.removeAll(keepingCapacity: true)
    }

    /// Scanner order is source order: children of a losing member are not separately recorded.
    func forEachRange(_ body: (Range<Int>) throws -> Void) throws {
        if let writer { try writer.close(); self.writer = nil }
        if let fileURL {
            let reader = try FileHandle(forReadingFrom: fileURL)
            defer { try? reader.close() }
            var pending = Data()
            while let bytes = try reader.read(upToCount: 64 << 10), !bytes.isEmpty {
                pending.append(bytes)
                let complete = pending.count / 16 * 16
                try pending.withUnsafeBytes { raw in
                    for offset in stride(from: 0, to: complete, by: 16) {
                        let lowerBits = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                        let upperBits = raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self)
                        let lower = Int64(bitPattern: UInt64(littleEndian: lowerBits))
                        let upper = Int64(bitPattern: UInt64(littleEndian: upperBits))
                        try body(Int(lower) ..< Int(upper))
                    }
                }
                pending.removeSubrange(0 ..< complete)
            }
            if !pending.isEmpty { throw ManifestStreamError.io("short duplicate-cut spill") }
        }
        for range in buffered { try body(range) }
    }

    func discard() throws {
        if let writer { try writer.close(); self.writer = nil }
        if let fileURL { try FileManager.default.removeItem(at: fileURL); self.fileURL = nil }
        buffered.removeAll(keepingCapacity: false)
    }
}
