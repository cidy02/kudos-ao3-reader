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
        /// library work. Streaming export and ZIP64 mean the archive itself is
        /// no longer bounded by memory or classic 32-bit ZIP fields; these
        /// caps bound what a hostile archive can make the reader allocate
        /// (per entry, and per restore in total) while comfortably covering
        /// any real library.
        static let backup = Limits(
            maxEntryCount: 250_000,
            maxSingleEntryUncompressedSize: 1_000_000_000,
            maxTotalUncompressedSize: 64_000_000_000,
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
                    over: nameEnd ..< extraEnd,
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
        over extraField: Range<Int>,
        needsUncompressedSize: Bool,
        needsCompressedSize: Bool,
        needsLocalHeaderOffset: Bool
    ) throws -> Zip64ExtraValues {
        let end = extraField.upperBound
        var cursor = extraField.lowerBound
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
    /// Incremental stored-entry ZIP writer. Each appended entry's local header
    /// and payload go straight to the sink; only the (small) central-directory
    /// records stay in memory until `finish()`, so an archive of any size can
    /// be produced without ever materializing it. Entries are stored
    /// (uncompressed) only — EPUB payloads are already internally
    /// DEFLATE-compressed, so re-compressing them buys nothing, and stored
    /// entries keep the writer trivially verifiable (declared sizes are the
    /// real sizes). Entry names pass the same `validatedRelativePath` safety
    /// rules the reader enforces.
    ///
    /// ZIP64 records are emitted exactly when a value outgrows its classic
    /// 16/32-bit field (entry size, local-header offset, entry count, or
    /// central-directory offset/size), so archives below those thresholds stay
    /// byte-identical to the pre-ZIP64 writer's output.
    ///
    /// Not reusable: after `finish()` — or any thrown error, which can leave
    /// the sink mid-record — the writer must be discarded.
    final class ArchiveWriter {
        /// Bytes are handed over in write order and never revisited, so a sink
        /// may append to a file handle or to an in-memory buffer.
        private let sink: (Data) throws -> Void
        /// Read size for file-backed payloads; injectable so tests can force
        /// multi-chunk streaming with small fixtures.
        private let chunkSize: Int
        private var offset: UInt64 = 0
        private var centralDirectory = Data()
        private var entryCount = 0
        private var seenNames = Set<String>()
        private var finished = false

        init(chunkSize: Int = 4 << 20, sink: @escaping (Data) throws -> Void) {
            self.chunkSize = max(1, chunkSize)
            self.sink = sink
        }

        /// Appends one stored entry whose payload is already in memory.
        func append(name: String, data payload: Data) throws {
            try appendEntry(name: name, size: UInt64(payload.count), crc: MiniZip.crc32(payload)) {
                try emit(payload)
            }
        }

        /// Appends one stored entry streamed from a file in `chunkSize` reads,
        /// so the payload never lives in memory at once. The file is read
        /// twice — once for the CRC-32 the stored local header must declare
        /// ahead of the payload, once to stream the payload — and exactly the
        /// initially-measured byte count both times: a file that shrinks
        /// between passes fails the append (`truncatedRecord`) rather than
        /// producing a corrupt archive.
        func append(name: String, contentsOf url: URL) throws {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()

            try handle.seek(toOffset: 0)
            var crcState: UInt32 = 0xFFFF_FFFF
            try readExactly(size, from: handle) { chunk in
                crcState = MiniZip.crc32Update(crcState, chunk)
            }

            try handle.seek(toOffset: 0)
            try appendEntry(name: name, size: size, crc: crcState ^ 0xFFFF_FFFF) {
                try readExactly(size, from: handle) { chunk in
                    try emit(chunk)
                }
            }
        }

        /// Writes the central directory, the ZIP64 EOCD record + locator when
        /// any count or offset outgrew its classic field, and the classic EOCD.
        func finish() throws {
            precondition(!finished, "ArchiveWriter used after finish()")
            finished = true
            guard entryCount > 0 else { throw MiniZipError.malformedArchive }

            let centralDirectoryOffset = offset
            let centralDirectorySize = UInt64(centralDirectory.count)
            try emit(centralDirectory)
            centralDirectory = Data()

            let needsZip64 = entryCount >= 0xFFFF
                || centralDirectoryOffset >= 0xFFFF_FFFF
                || centralDirectorySize >= 0xFFFF_FFFF
            if needsZip64 {
                let zip64EOCDOffset = offset
                var records = Data()
                // ZIP64 end of central directory record.
                records.appendU32(0x0606_4B50)
                records.appendU64(44) // size of the record after this field
                records.appendU16(45) // version made by
                records.appendU16(45) // version needed
                records.appendU32(0) // this disk
                records.appendU32(0) // central-directory disk
                records.appendU64(UInt64(entryCount))
                records.appendU64(UInt64(entryCount))
                records.appendU64(centralDirectorySize)
                records.appendU64(centralDirectoryOffset)
                // ZIP64 end of central directory locator.
                records.appendU32(0x0706_4B50)
                records.appendU32(0) // disk holding the ZIP64 EOCD
                records.appendU64(zip64EOCDOffset)
                records.appendU32(1) // total disks
                try emit(records)
            }

            var eocd = Data()
            eocd.appendU32(0x0605_4B50)
            eocd.appendU16(0) // this disk
            eocd.appendU16(0) // central-directory disk
            let count16 = UInt16(clampingToSentinel: UInt64(entryCount))
            eocd.appendU16(count16)
            eocd.appendU16(count16)
            eocd.appendU32(UInt32(clampingToSentinel: centralDirectorySize))
            eocd.appendU32(UInt32(clampingToSentinel: centralDirectoryOffset))
            eocd.appendU16(0) // comment length
            try emit(eocd)
        }

        /// Writes the local header and matching central-directory record for
        /// one stored entry, with `payload` emitting exactly `size` bytes in
        /// between.
        private func appendEntry(
            name: String,
            size: UInt64,
            crc: UInt32,
            payload: () throws -> Void
        ) throws {
            precondition(!finished, "ArchiveWriter used after finish()")
            _ = try MiniZip.validatedRelativePath(name)
            guard seenNames.insert(name).inserted else { throw MiniZipError.malformedArchive }
            guard let nameBytes = name.data(using: .utf8), nameBytes.count <= 0xFFFF else {
                throw MiniZipError.pathTraversal
            }

            let localHeaderOffset = offset
            let needsZip64Sizes = size >= 0xFFFF_FFFF
            let needsZip64Offset = localHeaderOffset >= 0xFFFF_FFFF
            let size32 = UInt32(clampingToSentinel: size)

            // Local file header. Flags set only bit 11 (UTF-8 names); the
            // fixed 1980-01-01 DOS timestamp keeps output deterministic —
            // `exportedAt` inside the manifest is the meaningful date.
            var local = Data()
            local.appendU32(0x0403_4B50)
            local.appendU16(needsZip64Sizes ? 45 : 20) // version needed
            local.appendU16(0x0800) // flags: UTF-8 names
            local.appendU16(0) // method: stored
            local.appendU16(0) // DOS time
            local.appendU16(0x0021) // DOS date: 1980-01-01
            local.appendU32(crc)
            local.appendU32(size32) // compressed
            local.appendU32(size32) // uncompressed
            local.appendU16(UInt16(nameBytes.count))
            local.appendU16(needsZip64Sizes ? 20 : 0) // extra length
            local.append(nameBytes)
            if needsZip64Sizes {
                local.appendU16(0x0001)
                local.appendU16(16)
                local.appendU64(size) // original (uncompressed) size
                local.appendU64(size) // compressed size
            }
            try emit(local)

            try payload()

            // Matching central-directory record; saturated fields carry their
            // real values in the ZIP64 extra block, in spec order.
            let zip64FieldCount = (needsZip64Sizes ? 2 : 0) + (needsZip64Offset ? 1 : 0)
            let needsZip64 = zip64FieldCount > 0
            var central = Data()
            central.appendU32(0x0201_4B50)
            central.appendU16(needsZip64 ? 45 : 20) // version made by
            central.appendU16(needsZip64 ? 45 : 20) // version needed
            central.appendU16(0x0800) // flags: UTF-8 names
            central.appendU16(0) // method: stored
            central.appendU16(0) // DOS time
            central.appendU16(0x0021) // DOS date
            central.appendU32(crc)
            central.appendU32(size32)
            central.appendU32(size32)
            central.appendU16(UInt16(nameBytes.count))
            central.appendU16(needsZip64 ? UInt16(4 + 8 * zip64FieldCount) : 0) // extra length
            central.appendU16(0) // comment length
            central.appendU16(0) // disk number
            central.appendU16(0) // internal attributes
            central.appendU32(0) // external attributes
            central.appendU32(UInt32(clampingToSentinel: localHeaderOffset))
            central.append(nameBytes)
            if needsZip64 {
                central.appendU16(0x0001)
                central.appendU16(UInt16(8 * zip64FieldCount))
                if needsZip64Sizes {
                    central.appendU64(size) // original (uncompressed) size
                    central.appendU64(size) // compressed size
                }
                if needsZip64Offset {
                    central.appendU64(localHeaderOffset)
                }
            }
            centralDirectory.append(central)
            entryCount += 1
        }

        /// Reads exactly `size` bytes from `handle` in `chunkSize` slices,
        /// handing each to `consume`. Fewer available bytes than promised —
        /// the file shrank since it was measured — fail the archive.
        private func readExactly(
            _ size: UInt64,
            from handle: FileHandle,
            consume: (Data) throws -> Void
        ) throws {
            var remaining = size
            while remaining > 0 {
                let request = Int(min(remaining, UInt64(chunkSize)))
                guard let chunk = try handle.read(upToCount: request), !chunk.isEmpty else {
                    throw MiniZipError.truncatedRecord
                }
                try consume(chunk)
                remaining -= UInt64(chunk.count)
            }
        }

        private func emit(_ bytes: Data) throws {
            try sink(bytes)
            offset += UInt64(bytes.count)
        }
    }

    /// Builds a ZIP archive from named entries entirely in memory — the
    /// streaming `ArchiveWriter` with an in-memory sink. Suited to small
    /// archives; the backup exporter streams to a file instead.
    static func archiveData(_ entries: [(name: String, data: Data)]) throws -> Data {
        guard !entries.isEmpty else { throw MiniZipError.malformedArchive }
        var archive = Data()
        let writer = ArchiveWriter { archive.append($0) }
        for entry in entries {
            try writer.append(name: entry.name, data: entry.data)
        }
        try writer.finish()
        return archive
    }

    /// Standard CRC-32 (IEEE 802.3, polynomial 0xEDB88320), required by the
    /// ZIP format for every entry. Table-driven; verified in tests against the
    /// canonical "123456789" → 0xCBF43926 check value.
    static func crc32(_ data: Data) -> UInt32 {
        crc32Update(0xFFFF_FFFF, data) ^ 0xFFFF_FFFF
    }

    /// Incremental form: seed with 0xFFFFFFFF, fold in each chunk, then XOR
    /// the final state with 0xFFFFFFFF. Lets file-backed archive entries be
    /// checksummed in bounded memory.
    fileprivate static func crc32Update(_ state: UInt32, _ chunk: Data) -> UInt32 {
        chunk.withUnsafeBytes { buffer in
            var crc = state
            for byte in buffer {
                crc = (crc >> 8) ^ Self.crcTable[Int((crc ^ UInt32(byte)) & 0xFF)]
            }
            return crc
        }
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
        }
        return value
    }
}

nonisolated private extension UInt16 {
    /// The value itself when it fits below the ZIP64 sentinel, else the
    /// sentinel (0xFFFF) directing readers to the ZIP64 record.
    init(clampingToSentinel value: UInt64) {
        self = value >= 0xFFFF ? 0xFFFF : UInt16(value)
    }
}

nonisolated private extension UInt32 {
    /// The value itself when it fits below the ZIP64 sentinel, else the
    /// sentinel (0xFFFFFFFF) directing readers to the ZIP64 extra field.
    init(clampingToSentinel value: UInt64) {
        self = value >= 0xFFFF_FFFF ? 0xFFFF_FFFF : UInt32(value)
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

    mutating func appendU64(_ value: UInt64) {
        appendU32(UInt32(value & 0xFFFF_FFFF))
        appendU32(UInt32(value >> 32))
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
