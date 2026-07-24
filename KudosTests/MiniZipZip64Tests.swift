import Foundation
import Testing
@testable import Kudos

/// ZIP64 coverage for `MiniZip`, both directions. Reader side: saturated
/// classic fields (0xFFFF / 0xFFFFFFFF) must resolve through the ZIP64
/// records — extra field 0x0001, ZIP64 EOCD record + locator — and must
/// reject the archive when those records are missing, truncated, or claim
/// sizes beyond the limits; a sentinel is never silently read as a value.
/// Writer side: `ArchiveWriter` emits ZIP64 records exactly when a value
/// outgrows its classic field, streams file-backed payloads in chunks with an
/// incremental CRC, and stays byte-identical to the in-memory path.
struct MiniZipZip64Tests {
    // MARK: - Hand-assembled ZIP64 fixtures

    /// Builds a single-entry archive whose central-directory fields, extra
    /// field, and EOCD chain can each be forced into ZIP64 shapes the writer
    /// would never produce on its own — including invalid ones.
    private enum Fixture {
        static func le16(_ value: UInt16) -> Data {
            Data([UInt8(value & 0xFF), UInt8(value >> 8)])
        }

        static func le32(_ value: UInt32) -> Data {
            le16(UInt16(value & 0xFFFF)) + le16(UInt16(value >> 16))
        }

        static func le64(_ value: UInt64) -> Data {
            le32(UInt32(value & 0xFFFF_FFFF)) + le32(UInt32(value >> 32))
        }

        /// A ZIP64 extended-information extra field carrying the given 8-byte
        /// values in order.
        static func zip64Extra(_ values: [UInt64]) -> Data {
            values.reduce(le16(0x0001) + le16(UInt16(values.count * 8))) { $0 + le64($1) }
        }

        // swiftlint:disable:next function_body_length
        static func archive(
            name: String = "a.bin",
            payload: Data = Data("hello".utf8),
            centralCompressed: UInt32? = nil,
            centralUncompressed: UInt32? = nil,
            centralLocalOffset: UInt32 = 0,
            centralExtra: Data = Data(),
            zip64EOCD: Bool = false,
            bogusLocatorOffset: UInt64? = nil,
            saturateEOCD: Bool = false
        ) -> Data {
            let nameBytes = Data(name.utf8)
            var body = Data()

            // Local file header (CRC 0 — the reader never checks local CRCs).
            body += le32(0x0403_4B50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
            body += le32(0)
            body += le32(UInt32(payload.count)) + le32(UInt32(payload.count))
            body += le16(UInt16(nameBytes.count)) + le16(0)
            body += nameBytes + payload

            let centralStart = body.count
            body += le32(0x0201_4B50) + le16(45) + le16(45) + le16(0) + le16(0) + le16(0) + le16(0)
            body += le32(0)
            body += le32(centralCompressed ?? UInt32(payload.count))
            body += le32(centralUncompressed ?? UInt32(payload.count))
            body += le16(UInt16(nameBytes.count)) + le16(UInt16(centralExtra.count))
            body += le16(0) + le16(0) + le16(0)
            body += le32(0)
            body += le32(centralLocalOffset)
            body += nameBytes + centralExtra
            let cdSize = body.count - centralStart

            if zip64EOCD {
                let recordOffset = UInt64(body.count)
                body += le32(0x0606_4B50) + le64(44) + le16(45) + le16(45) + le32(0) + le32(0)
                body += le64(1) + le64(1) + le64(UInt64(cdSize)) + le64(UInt64(centralStart))
                body += le32(0x0706_4B50) + le32(0) + le64(recordOffset) + le32(1)
            } else if let bogusLocatorOffset {
                body += le32(0x0706_4B50) + le32(0) + le64(bogusLocatorOffset) + le32(1)
            }

            body += le32(0x0605_4B50) + le16(0) + le16(0)
            let count: UInt16 = saturateEOCD ? 0xFFFF : 1
            body += le16(count) + le16(count)
            body += le32(saturateEOCD ? 0xFFFF_FFFF : UInt32(cdSize))
            body += le32(saturateEOCD ? 0xFFFF_FFFF : UInt32(centralStart))
            body += le16(0)
            return body
        }
    }

    // MARK: - Reader: ZIP64 extra field

    @Test func zip64ExtraResolvesSaturatedSizesAndOffset() throws {
        let archive = Fixture.archive(
            centralCompressed: 0xFFFF_FFFF,
            centralUncompressed: 0xFFFF_FFFF,
            centralLocalOffset: 0xFFFF_FFFF,
            centralExtra: Fixture.zip64Extra([5, 5, 0])
        )
        let zip = try MiniZip(data: archive)
        #expect(zip.names == ["a.bin"])
        #expect(zip.data(named: "a.bin") == Data("hello".utf8))
    }

    @Test func saturatedSizesWithoutZip64ExtraAreRejected() {
        let archive = Fixture.archive(
            centralCompressed: 0xFFFF_FFFF,
            centralUncompressed: 0xFFFF_FFFF
        )
        #expect(throws: MiniZipError.malformedArchive) {
            _ = try MiniZip(data: archive)
        }
    }

    @Test func zip64ExtraBlockShorterThanItsSaturatedFieldsIsRejected() {
        // Both sizes saturated, but the block only carries one 8-byte value.
        let archive = Fixture.archive(
            centralCompressed: 0xFFFF_FFFF,
            centralUncompressed: 0xFFFF_FFFF,
            centralExtra: Fixture.zip64Extra([5])
        )
        #expect(throws: MiniZipError.malformedArchive) {
            _ = try MiniZip(data: archive)
        }
    }

    /// A ZIP64 size passes through the same limit checks as a classic one —
    /// a multi-gigabyte claim is rejected before any allocation trusts it.
    @Test func zip64DeclaredSizeBeyondTheSingleEntryLimitIsRejected() {
        let archive = Fixture.archive(
            centralCompressed: 0xFFFF_FFFF,
            centralUncompressed: 0xFFFF_FFFF,
            centralExtra: Fixture.zip64Extra([2_000_000_000, 2_000_000_000])
        )
        #expect(throws: MiniZipError.entryTooLarge) {
            _ = try MiniZip(data: archive, limits: .backup)
        }
    }

    // MARK: - Reader: ZIP64 EOCD record + locator

    @Test func zip64EOCDRecordDrivesCentralDirectoryLocation() throws {
        let archive = Fixture.archive(zip64EOCD: true, saturateEOCD: true)
        let zip = try MiniZip(data: archive)
        #expect(zip.names == ["a.bin"])
        #expect(zip.data(named: "a.bin") == Data("hello".utf8))
    }

    @Test func saturatedEOCDFieldsWithoutZip64RecordsAreRejected() {
        let archive = Fixture.archive(saturateEOCD: true)
        #expect(throws: MiniZipError.malformedArchive) {
            _ = try MiniZip(data: archive)
        }
    }

    @Test func locatorPointingOutsideTheFileIsRejected() {
        let archive = Fixture.archive(bogusLocatorOffset: 1 << 40)
        #expect(throws: MiniZipError.malformedArchive) {
            _ = try MiniZip(data: archive)
        }
    }

    // MARK: - Writer: ZIP64 EOCD when the entry count overflows

    /// Above 65 534 entries the classic EOCD count can't hold the value; the
    /// writer must emit the ZIP64 EOCD chain and the reader must follow it —
    /// end to end, not against fixtures.
    @Test func entryCountOverflowRoundTripsThroughTheZip64EOCD() throws {
        var archive = Data()
        let writer = MiniZip.ArchiveWriter { archive.append($0) }
        let count = 65_600
        for index in 0 ..< count {
            try writer.append(name: "e\(index).bin", data: Data("p\(index)".utf8))
        }
        try writer.finish()

        // The ZIP64 EOCD record signature must be present…
        #expect(archive.range(of: Data([0x50, 0x4B, 0x06, 0x06])) != nil)

        let zip = try MiniZip(data: archive, limits: .backup)
        #expect(zip.names.count == count)
        #expect(zip.data(named: "e0.bin") == Data("p0".utf8))
        #expect(zip.data(named: "e65599.bin") == Data("p65599".utf8))
    }

    @Test func smallArchivesCarryNoZip64Records() throws {
        let archive = try MiniZip.archiveData([
            (name: "manifest.json", data: Data(#"{"version":7}"#.utf8)),
            (name: "Works/AB.epub", data: Data((0 ..< 4096).map { UInt8($0 % 251) }))
        ])
        // Neither the ZIP64 EOCD record nor the locator signature appears.
        #expect(archive.range(of: Data([0x50, 0x4B, 0x06, 0x06])) == nil)
        #expect(archive.range(of: Data([0x50, 0x4B, 0x06, 0x07])) == nil)
    }

    // MARK: - Writer: streaming file-backed entries

    /// A file-backed entry streamed in deliberately tiny chunks must produce
    /// exactly the bytes of the all-in-memory path — which also proves the
    /// incremental CRC matches the one-shot CRC.
    @Test func streamedFileEntriesMatchTheInMemoryOutput() throws {
        let entries: [(name: String, data: Data)] = [
            (name: "manifest.json", data: Data(#"{"version":7}"#.utf8)),
            (name: "Works/AB.epub", data: Data((0 ..< 10_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })),
            (name: "empty.bin", data: Data())
        ]
        let inMemory = try MiniZip.archiveData(entries)

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiniZipZip64Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        var streamed = Data()
        let writer = MiniZip.ArchiveWriter(chunkSize: 512) { streamed.append($0) }
        for (index, entry) in entries.enumerated() {
            let file = staging.appendingPathComponent("entry-\(index)")
            try entry.data.write(to: file)
            try writer.append(name: entry.name, contentsOf: file)
        }
        try writer.finish()

        #expect(streamed == inMemory)
        let zip = try MiniZip(data: streamed, limits: .backup)
        for entry in entries {
            #expect(zip.data(named: entry.name) == entry.data)
        }
    }
}
