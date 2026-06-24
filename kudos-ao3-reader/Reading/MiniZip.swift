import Foundation
import Compression

// MARK: - Minimal ZIP reader

/// A single entry in a ZIP archive's central directory.
private struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

/// A tiny, dependency-free ZIP reader good enough for EPUB files
/// (stored or DEFLATE-compressed entries, no ZIP64).
struct MiniZip {
    private let data: Data
    private let entries: [ZipEntry]

    init?(data: Data) {
        self.data = data
        guard let eocd = MiniZip.findEOCD(in: data) else { return nil }
        let count = Int(data.u16(eocd + 10))
        var offset = Int(data.u32(eocd + 16))
        var parsed: [ZipEntry] = []
        for _ in 0..<count {
            guard offset + 46 <= data.count, data.u32(offset) == 0x0201_4b50 else { break }
            let method = data.u16(offset + 10)
            let compressedSize = Int(data.u32(offset + 20))
            let uncompressedSize = Int(data.u32(offset + 24))
            let nameLen = Int(data.u16(offset + 28))
            let extraLen = Int(data.u16(offset + 30))
            let commentLen = Int(data.u16(offset + 32))
            let localOffset = Int(data.u32(offset + 42))
            let nameStart = offset + 46
            let name = String(
                data: data.subdata(in: nameStart..<(nameStart + nameLen)),
                encoding: .utf8
            ) ?? ""
            parsed.append(ZipEntry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
            offset = nameStart + nameLen + extraLen + commentLen
        }
        self.entries = parsed
        if parsed.isEmpty { return nil }
    }

    /// All entry names in the archive.
    var names: [String] { entries.map(\.name) }

    /// Extracts a single entry's bytes by exact name.
    func data(named name: String) -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else { return nil }
        return extract(entry)
    }

    /// Unzips every file entry into `directory`, preserving relative paths.
    func unzip(to directory: URL) throws {
        let fm = FileManager.default
        for entry in entries where !entry.name.hasSuffix("/") {
            guard let bytes = extract(entry) else { continue }
            let dest = directory.appendingPathComponent(entry.name)
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try bytes.write(to: dest)
        }
    }

    private func extract(_ entry: ZipEntry) -> Data? {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count, data.u32(base) == 0x0403_4b50 else { return nil }
        let nameLen = Int(data.u16(base + 26))
        let extraLen = Int(data.u16(base + 28))
        let start = base + 30 + nameLen + extraLen
        let end = start + entry.compressedSize
        guard end <= data.count else { return nil }
        let payload = data.subdata(in: start..<end)
        if entry.method == 0 { return payload }            // stored
        return MiniZip.inflate(payload, expectedSize: entry.uncompressedSize)
    }

    /// Raw DEFLATE inflation via the Compression framework.
    private static func inflate(_ input: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            input.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        if written != expectedSize { output.removeSubrange(written..<output.count) }
        return output
    }

    /// Locates the End Of Central Directory record by scanning backwards.
    private static func findEOCD(in data: Data) -> Int? {
        let sig: UInt32 = 0x0605_4b50
        guard data.count >= 22 else { return nil }
        var i = data.count - 22
        let lowerBound = max(0, data.count - 22 - 65_536)
        while i >= lowerBound {
            if data.u32(i) == sig { return i }
            i -= 1
        }
        return nil
    }
}

private extension Data {
    /// Little-endian unsigned 16-bit read at an absolute index.
    func u16(_ index: Int) -> UInt16 {
        UInt16(self[index]) | (UInt16(self[index + 1]) << 8)
    }

    /// Little-endian unsigned 32-bit read at an absolute index.
    func u32(_ index: Int) -> UInt32 {
        UInt32(self[index]) | (UInt32(self[index + 1]) << 8)
            | (UInt32(self[index + 2]) << 16) | (UInt32(self[index + 3]) << 24)
    }
}
