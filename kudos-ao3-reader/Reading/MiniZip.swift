import Compression
import Foundation

// MARK: - Minimal ZIP reader

/// Typed failures from validating or extracting a ZIP archive. Every case is
/// raised before any unchecked allocation, `subdata`, or filesystem write — a
/// malformed or hostile archive fails cleanly instead of crashing, exhausting
/// memory/disk, or writing outside its extraction root.
nonisolated enum MiniZipError: LocalizedError, Equatable {
    case malformedArchive
    case truncatedRecord
    case unsupportedEntry
    case pathTraversal
    case entryTooLarge
    case archiveTooLarge
    case suspiciousCompressionRatio
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .malformedArchive: "The archive's central directory is missing or malformed."
        case .truncatedRecord: "An archive record is truncated or points outside the file."
        case .unsupportedEntry: "The archive contains an unsupported or encrypted entry."
        case .pathTraversal: "The archive contains an entry with an unsafe path."
        case .entryTooLarge: "An entry in the archive exceeds the allowed size limit."
        case .archiveTooLarge: "The archive's total uncompressed size exceeds the allowed limit."
        case .suspiciousCompressionRatio: "An entry's compression ratio is implausibly high."
        case .decompressionFailed: "An entry couldn't be decompressed."
        }
    }
}

/// A single entry in a ZIP archive's central directory. Every field here has
/// already passed bounds/consistency/limit checks by the time it's constructed.
private struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

/// A tiny, dependency-free ZIP reader good enough for EPUB files (stored or
/// DEFLATE-compressed entries; no ZIP64, no encryption). Every entry is fully
/// validated — signature, bounds, method, size/ratio limits, uniqueness, and
/// path safety — while parsing the central directory, so a caller that only
/// inspects specific named entries (rather than extracting every one) sees
/// exactly the same pass/fail verdict as full extraction would.
nonisolated struct MiniZip {
    /// Conservative limits sized for EPUBs (small, text-and-image documents),
    /// not general-purpose archives — comfortably above anything a real EPUB
    /// needs, while still bounding a hostile archive's worst case.
    private static let maxEntryCount = 10_000
    private static let maxSingleEntryUncompressedSize = 200_000_000
    private static let maxTotalUncompressedSize = 500_000_000
    /// DEFLATE's practical single-pass ceiling is ~1032:1; this leaves headroom
    /// for legitimate, highly-repetitive text while still catching a bomb.
    private static let maxCompressionRatio = 1100

    private let data: Data
    private let entries: [ZipEntry]

    init(data: Data) throws {
        self.data = data
        guard let eocd = MiniZip.findEOCD(in: data) else { throw MiniZipError.malformedArchive }
        guard let countRaw = data.safeU16(eocd + 10),
              let centralStartRaw = data.safeU32(eocd + 16)
        else { throw MiniZipError.malformedArchive }
        let count = Int(countRaw)
        guard count <= MiniZip.maxEntryCount else { throw MiniZipError.archiveTooLarge }
        let centralStart = Int(centralStartRaw)
        guard centralStart >= 0, centralStart <= data.count else { throw MiniZipError.malformedArchive }

        var offset = centralStart
        var parsed: [ZipEntry] = []
        parsed.reserveCapacity(count)
        var totalUncompressed = 0
        var seenNames = Set<String>()

        for _ in 0 ..< count {
            guard let signature = data.safeU32(offset), signature == 0x0201_4B50 else {
                throw MiniZipError.malformedArchive
            }
            guard let flags = data.safeU16(offset + 8),
                  let method = data.safeU16(offset + 10),
                  let compressedSizeRaw = data.safeU32(offset + 20),
                  let uncompressedSizeRaw = data.safeU32(offset + 24),
                  let nameLenRaw = data.safeU16(offset + 28),
                  let extraLenRaw = data.safeU16(offset + 30),
                  let commentLenRaw = data.safeU16(offset + 32),
                  let localOffsetRaw = data.safeU32(offset + 42)
            else { throw MiniZipError.truncatedRecord }

            let compressedSize = Int(compressedSizeRaw)
            let uncompressedSize = Int(uncompressedSizeRaw)
            try MiniZip.validateMethodAndSize(
                method: method,
                flags: flags,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize
            )
            guard let runningTotal = MiniZip.addChecked(totalUncompressed, uncompressedSize),
                  runningTotal <= MiniZip.maxTotalUncompressedSize
            else { throw MiniZipError.archiveTooLarge }
            totalUncompressed = runningTotal

            guard let nameStart = MiniZip.addChecked(offset, 46),
                  let nameEnd = MiniZip.addChecked(nameStart, Int(nameLenRaw)),
                  let extraEnd = MiniZip.addChecked(nameEnd, Int(extraLenRaw)),
                  let recordEnd = MiniZip.addChecked(extraEnd, Int(commentLenRaw)),
                  recordEnd <= data.count
            else { throw MiniZipError.truncatedRecord }

            let name = String(data: data.subdata(in: nameStart ..< nameEnd), encoding: .utf8) ?? ""
            // Validated here — at construction, not just at `unzip` time — so a
            // hostile entry name fails the archive before any preflight caller
            // (`EPUBDocument.inspectPackage`, used by the backup-restore EPUB
            // validator) can treat the archive as safe just because it never
            // happened to read that specific entry by name.
            guard seenNames.insert(name).inserted else { throw MiniZipError.malformedArchive }
            if !name.hasSuffix("/") {
                _ = try MiniZip.validatedRelativePath(name)
            }
            parsed.append(ZipEntry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: Int(localOffsetRaw)
            ))
            offset = recordEnd
        }
        guard !parsed.isEmpty else { throw MiniZipError.malformedArchive }
        entries = parsed
    }

    /// All entry names in the archive.
    var names: [String] {
        entries.map(\.name)
    }

    /// Extracts a single entry's bytes by exact name, or nil if the name isn't
    /// present or the entry fails validation while extracting.
    func data(named name: String) -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else { return nil }
        return try? extract(entry)
    }

    /// Unzips every file entry, preserving relative paths. Extraction happens in
    /// a private staging directory first; `directory`'s contents are replaced
    /// only after every entry has validated and extracted successfully, so a
    /// hostile or malformed archive can never leave partial or unsafe output
    /// behind. Every standardized destination is proven to stay under the fresh
    /// staging root before anything is written.
    func unzip(to directory: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(
            "MiniZip-\(UUID().uuidString)", isDirectory: true
        )
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let stagingRoot = staging.standardizedFileURL.path

        for entry in entries where !entry.name.hasSuffix("/") {
            let relativePath = try MiniZip.validatedRelativePath(entry.name)
            let dest = staging.appendingPathComponent(relativePath).standardizedFileURL
            guard dest.path == stagingRoot || dest.path.hasPrefix(stagingRoot + "/") else {
                throw MiniZipError.pathTraversal
            }
            let bytes = try extract(entry)
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try bytes.write(to: dest)
        }

        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
        try fm.createDirectory(
            at: directory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.moveItem(at: staging, to: directory)
    }

    private func extract(_ entry: ZipEntry) throws -> Data {
        guard let signature = data.safeU32(entry.localHeaderOffset), signature == 0x0403_4B50 else {
            throw MiniZipError.malformedArchive
        }
        guard let nameLenRaw = data.safeU16(entry.localHeaderOffset + 26),
              let extraLenRaw = data.safeU16(entry.localHeaderOffset + 28)
        else { throw MiniZipError.truncatedRecord }
        guard let start = MiniZip.addChecked(entry.localHeaderOffset, 30, Int(nameLenRaw), Int(extraLenRaw)),
              let end = MiniZip.addChecked(start, entry.compressedSize),
              end <= data.count
        else { throw MiniZipError.truncatedRecord }

        let payload = data.subdata(in: start ..< end)
        if entry.method == 0 { return payload } // stored
        return try MiniZip.inflate(payload, expectedSize: entry.uncompressedSize)
    }

    /// Raw DEFLATE inflation via the Compression framework. `expectedSize` was
    /// already bounded against `maxSingleEntryUncompressedSize` while parsing
    /// the central directory, so this allocation is never attacker-controlled
    /// beyond that limit.
    private static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            input.withUnsafeBytes { src -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    dstBase, expectedSize, srcBase, input.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw MiniZipError.decompressionFailed }
        if written != expectedSize { output.removeSubrange(written ..< output.count) }
        return output
    }

    /// Locates the End Of Central Directory record by scanning backwards.
    private static func findEOCD(in data: Data) -> Int? {
        let sig: UInt32 = 0x0605_4B50
        guard data.count >= 22 else { return nil }
        var i = data.count - 22
        let lowerBound = max(0, data.count - 22 - 65536)
        while i >= lowerBound {
            if data.safeU32(i) == sig { return i }
            i -= 1
        }
        return nil
    }

    /// Validates a central-directory entry's method, encryption flag, and
    /// declared sizes before it's trusted for allocation or extraction.
    private static func validateMethodAndSize(
        method: UInt16,
        flags: UInt16,
        compressedSize: Int,
        uncompressedSize: Int
    ) throws {
        // Bit 0 of the general-purpose flag marks a Traditional PKWARE (or
        // stronger) encrypted entry, which this reader cannot decrypt or safely
        // ignore. Only stored/DEFLATE entries are supported; a real EPUB never
        // uses anything else.
        guard flags & 0x1 == 0, method == 0 || method == 8 else {
            throw MiniZipError.unsupportedEntry
        }
        if method == 0 {
            // Stored entries are their own proof: declared sizes must match.
            guard compressedSize == uncompressedSize else { throw MiniZipError.malformedArchive }
        }
        guard uncompressedSize <= MiniZip.maxSingleEntryUncompressedSize else {
            throw MiniZipError.entryTooLarge
        }
        if compressedSize > 0 {
            guard uncompressedSize / compressedSize <= MiniZip.maxCompressionRatio else {
                throw MiniZipError.suspiciousCompressionRatio
            }
        }
    }

    /// Sums arbitrarily many offsets/lengths, failing on overflow instead of
    /// wrapping. Every archive-controlled offset in this file is validated
    /// through this before it's used to index or slice `data`.
    private static func addChecked(_ values: Int...) -> Int? {
        var total = 0
        for value in values {
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }

    /// Normalizes an archive entry name into a safe path relative to the
    /// extraction root, rejecting absolute paths, `..` traversal, backslash
    /// traversal, and drive/scheme-like prefixes (`C:\`, `file://`). The
    /// standardized-path containment check in `unzip` is a second, independent
    /// line of defense on top of this.
    private static func validatedRelativePath(_ rawName: String) throws -> String {
        guard !rawName.isEmpty, !rawName.contains("\\"), !rawName.contains("\0") else {
            throw MiniZipError.pathTraversal
        }
        if let colon = rawName.firstIndex(of: ":"),
           rawName.distance(from: rawName.startIndex, to: colon) <= 2 {
            throw MiniZipError.pathTraversal
        }
        let components = rawName.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = components.first, !first.isEmpty else { throw MiniZipError.pathTraversal }
        guard !components.contains(where: { $0 == ".." || $0.isEmpty }) else {
            throw MiniZipError.pathTraversal
        }
        return rawName
    }
}

private extension Data {
    /// Little-endian unsigned 16-bit read at an absolute index, or nil if the
    /// read would run past the end of the buffer.
    func safeU16(_ index: Int) -> UInt16? {
        guard index >= 0, index + 2 <= count else { return nil }
        return UInt16(self[index]) | (UInt16(self[index + 1]) << 8)
    }

    /// Little-endian unsigned 32-bit read at an absolute index, or nil if the
    /// read would run past the end of the buffer.
    func safeU32(_ index: Int) -> UInt32? {
        guard index >= 0, index + 4 <= count else { return nil }
        return UInt32(self[index]) | (UInt32(self[index + 1]) << 8)
            | (UInt32(self[index + 2]) << 16) | (UInt32(self[index + 3]) << 24)
    }
}
