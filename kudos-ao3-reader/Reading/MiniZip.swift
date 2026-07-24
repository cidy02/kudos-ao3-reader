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

/// A tiny, dependency-free ZIP reader/writer good enough for EPUB files and
/// `.kudosbackup` archives (stored or DEFLATE-compressed entries, ZIP64
/// supported, no encryption). Every entry is fully validated — signature,
/// bounds, method, size/ratio limits, uniqueness, and path safety — while
/// parsing the central directory, so a caller that only inspects specific
/// named entries (rather than extracting every one) sees exactly the same
/// pass/fail verdict as full extraction would. A classic field saturated at
/// its sentinel (0xFFFF / 0xFFFFFFFF) is never read as a value: it must
/// resolve through the matching ZIP64 record, or the archive is rejected.
nonisolated struct MiniZip {
    /// Bounds on what an archive may claim before any allocation trusts it.
    /// Profiles exist because the two archive kinds this app reads have very
    /// different plausible sizes: a single EPUB versus a whole-library backup.
    struct Limits {
        let maxEntryCount: Int
        let maxSingleEntryUncompressedSize: Int
        let maxTotalUncompressedSize: Int
        /// DEFLATE's practical single-pass ceiling is ~1032:1; the profiles
        /// leave headroom for legitimate, highly-repetitive text while still
        /// catching a bomb.
        let maxCompressionRatio: Int

        /// Conservative limits sized for EPUBs (small, text-and-image
        /// documents), not general-purpose archives — comfortably above
        /// anything a real EPUB needs, while still bounding a hostile
        /// archive's worst case.
        static let epub = Limits(
            maxEntryCount: 10_000,
            maxSingleEntryUncompressedSize: 200_000_000,
            maxTotalUncompressedSize: 500_000_000,
            maxCompressionRatio: 1100
        )

        /// Sized for `.kudosbackup` archives: a manifest plus one EPUB per
        /// library work. The total stays bounded well below anything that
        /// could be materialized in memory anyway.
        static let backup = Limits(
            maxEntryCount: 50_000,
            maxSingleEntryUncompressedSize: 500_000_000,
            maxTotalUncompressedSize: 2_000_000_000,
            maxCompressionRatio: 1100
        )
    }

    private let data: Data
    private let entries: [ZipEntry]
    private let entryIndexByName: [String: Int]

    init(data: Data, limits: Limits = .epub) throws {
        self.data = data
        guard let eocd = MiniZip.findEOCD(in: data) else { throw MiniZipError.malformedArchive }
        let directory = try MiniZip.locateCentralDirectory(in: data, eocd: eocd)
        let count = directory.entryCount
        guard count <= limits.maxEntryCount else { throw MiniZipError.archiveTooLarge }
        let centralStart = directory.start

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

            guard let nameStart = MiniZip.addChecked(offset, 46),
                  let nameEnd = MiniZip.addChecked(nameStart, Int(nameLenRaw)),
                  let extraEnd = MiniZip.addChecked(nameEnd, Int(extraLenRaw)),
                  let recordEnd = MiniZip.addChecked(extraEnd, Int(commentLenRaw)),
                  recordEnd <= data.count
            else { throw MiniZipError.truncatedRecord }

            var compressedSize = Int(compressedSizeRaw)
            var uncompressedSize = Int(uncompressedSizeRaw)
            var localHeaderOffset = Int(localOffsetRaw)
            if compressedSizeRaw == 0xFFFF_FFFF || uncompressedSizeRaw == 0xFFFF_FFFF
                || localOffsetRaw == 0xFFFF_FFFF {
                let resolved = try MiniZip.parseZip64Extra(
                    in: data,
                    start: nameEnd,
                    end: extraEnd,
                    needsUncompressedSize: uncompressedSizeRaw == 0xFFFF_FFFF,
                    needsCompressedSize: compressedSizeRaw == 0xFFFF_FFFF,
                    needsLocalHeaderOffset: localOffsetRaw == 0xFFFF_FFFF
                )
                uncompressedSize = resolved.uncompressedSize ?? uncompressedSize
                compressedSize = resolved.compressedSize ?? compressedSize
                localHeaderOffset = resolved.localHeaderOffset ?? localHeaderOffset
            }

            try MiniZip.validateMethodAndSize(
                method: method,
                flags: flags,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                limits: limits
            )
            guard let runningTotal = MiniZip.addChecked(totalUncompressed, uncompressedSize),
                  runningTotal <= limits.maxTotalUncompressedSize
            else { throw MiniZipError.archiveTooLarge }
            totalUncompressed = runningTotal

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
                localHeaderOffset: localHeaderOffset
            ))
            offset = recordEnd
        }
        guard !parsed.isEmpty else { throw MiniZipError.malformedArchive }
        entries = parsed
        entryIndexByName = Dictionary(
            parsed.enumerated().map { ($0.element.name, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// All entry names in the archive.
    var names: [String] {
        entries.map(\.name)
    }

    /// Extracts a single entry's bytes by exact name, or nil if the name isn't
    /// present or the entry fails validation while extracting.
    func data(named name: String) -> Data? {
        guard let index = entryIndexByName[name] else { return nil }
        return try? extract(entries[index])
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

    private struct CentralDirectoryLocation {
        let entryCount: Int
        let start: Int
    }

    /// Resolves the central directory's entry count and start offset from the
    /// classic EOCD, or — when the ZIP64 EOCD locator precedes it — from the
    /// ZIP64 EOCD record it points at. Classic fields stuck at their sentinel
    /// (0xFFFF / 0xFFFFFFFF) are never read as values: without ZIP64 records
    /// to resolve them the archive is rejected outright.
    private static func locateCentralDirectory(
        in data: Data,
        eocd: Int
    ) throws -> CentralDirectoryLocation {
        guard let count16 = data.safeU16(eocd + 10),
              let size32 = data.safeU32(eocd + 12),
              let start32 = data.safeU32(eocd + 16)
        else { throw MiniZipError.malformedArchive }

        // The ZIP64 EOCD locator, when present, sits immediately before the
        // classic EOCD. Its record supersedes every classic field.
        if eocd >= 20, data.safeU32(eocd - 20) == 0x0706_4B50 {
            let locator = eocd - 20
            guard let zip64Disk = data.safeU32(locator + 4),
                  let recordOffsetRaw = data.safeU64(locator + 8),
                  let totalDisks = data.safeU32(locator + 16),
                  zip64Disk == 0, totalDisks <= 1,
                  let record = Int(exactly: recordOffsetRaw),
                  data.safeU32(record) == 0x0606_4B50,
                  let diskNumber = data.safeU32(record + 16),
                  let directoryDisk = data.safeU32(record + 20),
                  diskNumber == 0, directoryDisk == 0,
                  let totalEntriesRaw = data.safeU64(record + 32),
                  let startRaw = data.safeU64(record + 48)
            else { throw MiniZipError.malformedArchive }
            guard let entryCount = Int(exactly: totalEntriesRaw),
                  let start = Int(exactly: startRaw), start <= data.count
            else { throw MiniZipError.malformedArchive }
            return CentralDirectoryLocation(entryCount: entryCount, start: start)
        }

        guard count16 != 0xFFFF, size32 != 0xFFFF_FFFF, start32 != 0xFFFF_FFFF else {
            throw MiniZipError.malformedArchive
        }
        return CentralDirectoryLocation(entryCount: Int(count16), start: Int(start32))
    }

    private struct Zip64ExtraValues {
        var uncompressedSize: Int?
        var compressedSize: Int?
        var localHeaderOffset: Int?
    }

    /// Reads the ZIP64 extended-information extra field (header ID 0x0001)
    /// from a central-directory record's extra area. Called only when at least
    /// one fixed field is saturated; per spec the block carries values only
    /// for the saturated fields, always ordered original (uncompressed) size,
    /// compressed size, then local-header offset. A saturated field the block
    /// doesn't cover — or no block at all — rejects the archive.
    private static func parseZip64Extra(
        in data: Data,
        start: Int,
        end: Int,
        needsUncompressedSize: Bool,
        needsCompressedSize: Bool,
        needsLocalHeaderOffset: Bool
    ) throws -> Zip64ExtraValues {
        var cursor = start
        while let fieldsStart = addChecked(cursor, 4), fieldsStart <= end {
            guard let headerID = data.safeU16(cursor),
                  let blockSize = data.safeU16(cursor + 2),
                  let blockEnd = addChecked(fieldsStart, Int(blockSize)),
                  blockEnd <= end
            else { throw MiniZipError.truncatedRecord }
            if headerID == 0x0001 {
                var values = Zip64ExtraValues()
                var field = fieldsStart
                if needsUncompressedSize {
                    values.uncompressedSize = try readZip64Field(in: data, at: &field, before: blockEnd)
                }
                if needsCompressedSize {
                    values.compressedSize = try readZip64Field(in: data, at: &field, before: blockEnd)
                }
                if needsLocalHeaderOffset {
                    values.localHeaderOffset = try readZip64Field(in: data, at: &field, before: blockEnd)
                }
                return values
            }
            cursor = blockEnd
        }
        throw MiniZipError.malformedArchive
    }

    /// One 8-byte value inside a ZIP64 extra block, bounds-checked against the
    /// block and converted to a non-negative Int (fails on values above
    /// Int.max rather than truncating).
    private static func readZip64Field(
        in data: Data,
        at cursor: inout Int,
        before end: Int
    ) throws -> Int {
        guard let fieldEnd = addChecked(cursor, 8), fieldEnd <= end,
              let raw = data.safeU64(cursor),
              let value = Int(exactly: raw)
        else { throw MiniZipError.malformedArchive }
        cursor = fieldEnd
        return value
    }

    /// Validates a central-directory entry's method, encryption flag, and
    /// declared sizes before it's trusted for allocation or extraction.
    private static func validateMethodAndSize(
        method: UInt16,
        flags: UInt16,
        compressedSize: Int,
        uncompressedSize: Int,
        limits: Limits
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
        guard uncompressedSize <= limits.maxSingleEntryUncompressedSize else {
            throw MiniZipError.entryTooLarge
        }
        if compressedSize > 0 {
            guard uncompressedSize / compressedSize <= limits.maxCompressionRatio else {
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

// MARK: - Minimal ZIP writer

extension MiniZip {
    /// Builds a ZIP archive from named entries using stored (uncompressed)
    /// entries only — EPUB payloads are already internally DEFLATE-compressed,
    /// so re-compressing them buys nothing, and stored entries keep the writer
    /// trivially verifiable (declared sizes are the real sizes). Entry names
    /// pass the same `validatedRelativePath` safety rules the reader enforces,
    /// so everything this writer produces is readable by `MiniZip` and by any
    /// standard ZIP tool. No ZIP64: entry count, sizes, and offsets must fit
    /// the classic 16/32-bit fields, which comfortably covers any archive this
    /// app can materialize in memory anyway.
    static func archiveData(_ entries: [(name: String, data: Data)]) throws -> Data {
        guard !entries.isEmpty, entries.count <= 0xFFFF else {
            throw MiniZipError.malformedArchive
        }

        var seenNames = Set<String>()
        var archive = Data()
        var centralDirectory = Data()

        for (name, payload) in entries {
            _ = try validatedRelativePath(name)
            guard seenNames.insert(name).inserted else { throw MiniZipError.malformedArchive }
            guard let nameBytes = name.data(using: .utf8), nameBytes.count <= 0xFFFF else {
                throw MiniZipError.pathTraversal
            }
            guard payload.count < 0xFFFF_FFFF, archive.count < 0xFFFF_FFFF else {
                throw MiniZipError.entryTooLarge
            }

            let crc = crc32(payload)
            let localHeaderOffset = UInt32(archive.count)

            // Local file header. Flags set only bit 11 (UTF-8 names); the
            // fixed 1980-01-01 DOS timestamp keeps output deterministic —
            // `exportedAt` inside the manifest is the meaningful date.
            archive.appendU32(0x0403_4B50)
            archive.appendU16(20) // version needed
            archive.appendU16(0x0800) // flags: UTF-8 names
            archive.appendU16(0) // method: stored
            archive.appendU16(0) // DOS time
            archive.appendU16(0x0021) // DOS date: 1980-01-01
            archive.appendU32(crc)
            archive.appendU32(UInt32(payload.count)) // compressed
            archive.appendU32(UInt32(payload.count)) // uncompressed
            archive.appendU16(UInt16(nameBytes.count))
            archive.appendU16(0) // extra length
            archive.append(nameBytes)
            archive.append(payload)

            // Matching central-directory record.
            centralDirectory.appendU32(0x0201_4B50)
            centralDirectory.appendU16(20) // version made by
            centralDirectory.appendU16(20) // version needed
            centralDirectory.appendU16(0x0800) // flags: UTF-8 names
            centralDirectory.appendU16(0) // method: stored
            centralDirectory.appendU16(0) // DOS time
            centralDirectory.appendU16(0x0021) // DOS date
            centralDirectory.appendU32(crc)
            centralDirectory.appendU32(UInt32(payload.count))
            centralDirectory.appendU32(UInt32(payload.count))
            centralDirectory.appendU16(UInt16(nameBytes.count))
            centralDirectory.appendU16(0) // extra length
            centralDirectory.appendU16(0) // comment length
            centralDirectory.appendU16(0) // disk number
            centralDirectory.appendU16(0) // internal attributes
            centralDirectory.appendU32(0) // external attributes
            centralDirectory.appendU32(localHeaderOffset)
            centralDirectory.append(nameBytes)
        }

        let centralDirectoryOffset = archive.count
        guard centralDirectoryOffset + centralDirectory.count < 0xFFFF_FFFF else {
            throw MiniZipError.archiveTooLarge
        }
        archive.append(centralDirectory)

        // End of central directory.
        archive.appendU32(0x0605_4B50)
        archive.appendU16(0) // this disk
        archive.appendU16(0) // central-directory disk
        archive.appendU16(UInt16(entries.count))
        archive.appendU16(UInt16(entries.count))
        archive.appendU32(UInt32(centralDirectory.count))
        archive.appendU32(UInt32(centralDirectoryOffset))
        archive.appendU16(0) // comment length
        return archive
    }

    /// Standard CRC-32 (IEEE 802.3, polynomial 0xEDB88320), required by the
    /// ZIP format for every entry. Table-driven; verified in tests against the
    /// canonical "123456789" → 0xCBF43926 check value.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = (crc >> 8) ^ Self.crcTable[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
        }
        return value
    }
}

nonisolated private extension Data {
    mutating func appendU16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendU32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8(value >> 24))
    }
}

nonisolated private extension Data {
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

    /// Little-endian unsigned 64-bit read at an absolute index, or nil if the
    /// read would run past the end of the buffer. ZIP64 records are the only
    /// place the format stores 64-bit values.
    func safeU64(_ index: Int) -> UInt64? {
        guard index >= 0, index <= count - 8 else { return nil }
        var value: UInt64 = 0
        for byteIndex in 0 ..< 8 {
            value |= UInt64(self[index + byteIndex]) << (8 * byteIndex)
        }
        return value
    }
}
