import Foundation
import Testing
@testable import Kudos

/// A5-F2 hostile-input coverage for `MiniZip`: path traversal, truncated/malformed
/// records, oversized/ratio-abusive declared sizes, and unsupported/encrypted
/// entries must all fail with a typed `MiniZipError` before any unsafe allocation
/// or filesystem write, while a real minimal EPUB keeps opening normally.
///
/// Fixtures are hand-assembled raw ZIP byte sequences (not real compressed data)
/// so each hostile shape — truncated name length, declared-vs-actual size
/// mismatch, oversized ratio — can be constructed precisely and independently of
/// the DEFLATE codec.
struct MiniZipHostileTests {
    private struct RawEntry {
        var name: String
        var method: UInt16 = 0
        var flags: UInt16 = 0
        var payload: Data = Data()
        var declaredCompressedSize: Int?
        var declaredUncompressedSize: Int?
        var declaredNameLength: Int?
    }

    /// Assembles a minimal ZIP (local headers + central directory + EOCD) from raw
    /// entry specs, allowing declared sizes/name-lengths to lie about the actual
    /// bytes present — exactly the shape a hostile archive would exploit.
    private func buildArchive(_ entries: [RawEntry]) -> Data {
        var body = Data()
        var centralRecords: [Data] = []
        var offsets: [Int] = []

        for entry in entries {
            offsets.append(body.count)
            let nameBytes = Data(entry.name.utf8)
            let declaredNameLen = entry.declaredNameLength ?? nameBytes.count
            let compressedSize = entry.declaredCompressedSize ?? entry.payload.count
            let uncompressedSize = entry.declaredUncompressedSize ?? entry.payload.count

            var local = Data()
            local.append(le32(0x0403_4B50))
            local.append(le16(20))
            local.append(le16(entry.flags))
            local.append(le16(entry.method))
            local.append(le16(0))
            local.append(le16(0))
            local.append(le32(0))
            local.append(le32(UInt32(truncatingIfNeeded: compressedSize)))
            local.append(le32(UInt32(truncatingIfNeeded: uncompressedSize)))
            local.append(le16(UInt16(truncatingIfNeeded: declaredNameLen)))
            local.append(le16(0))
            local.append(nameBytes)
            local.append(entry.payload)
            body.append(local)

            var central = Data()
            central.append(le32(0x0201_4B50))
            central.append(le16(20))
            central.append(le16(20))
            central.append(le16(entry.flags))
            central.append(le16(entry.method))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(UInt32(truncatingIfNeeded: compressedSize)))
            central.append(le32(UInt32(truncatingIfNeeded: uncompressedSize)))
            central.append(le16(UInt16(truncatingIfNeeded: declaredNameLen)))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(UInt32(truncatingIfNeeded: offsets.last!)))
            central.append(nameBytes)
            centralRecords.append(central)
        }

        let centralStart = body.count
        for record in centralRecords { body.append(record) }
        let centralSize = body.count - centralStart

        var eocd = Data()
        eocd.append(le32(0x0605_4B50))
        eocd.append(le16(0))
        eocd.append(le16(0))
        eocd.append(le16(UInt16(entries.count)))
        eocd.append(le16(UInt16(entries.count)))
        eocd.append(le32(UInt32(centralSize)))
        eocd.append(le32(UInt32(centralStart)))
        eocd.append(le16(0))
        body.append(eocd)
        return body
    }

    private func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)
        ])
    }

    private func freshTempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    // MARK: - 1. Traversal with an outside sentinel unchanged

    @Test func pathTraversalNeverWritesOutsideTheDestinationRoot() throws {
        let archive = buildArchive([
            RawEntry(name: "../../../outside.txt", payload: Data("hostile".utf8))
        ])
        let zip = try MiniZip(data: archive)

        let cachesRoot = freshTempDir()
        defer { try? FileManager.default.removeItem(at: cachesRoot) }
        try FileManager.default.createDirectory(at: cachesRoot, withIntermediateDirectories: true)
        let sentinelPath = cachesRoot.appendingPathComponent("outside.txt")
        try Data("known-good".utf8).write(to: sentinelPath)
        let readerDir = cachesRoot.appendingPathComponent("Reader/\(UUID().uuidString)")

        #expect(throws: MiniZipError.pathTraversal) {
            try zip.unzip(to: readerDir)
        }
        #expect(try Data(contentsOf: sentinelPath) == Data("known-good".utf8))
        #expect(!FileManager.default.fileExists(atPath: readerDir.path))
    }

    // MARK: - 2. Absolute and backslash traversal

    @Test func absolutePathIsRejected() throws {
        let archive = buildArchive([
            RawEntry(name: "/etc/passwd", payload: Data("hostile".utf8))
        ])
        let zip = try MiniZip(data: archive)
        #expect(throws: MiniZipError.pathTraversal) {
            try zip.unzip(to: freshTempDir())
        }
    }

    @Test func backslashTraversalIsRejected() throws {
        let archive = buildArchive([
            RawEntry(name: "..\\..\\outside.txt", payload: Data("hostile".utf8))
        ])
        let zip = try MiniZip(data: archive)
        #expect(throws: MiniZipError.pathTraversal) {
            try zip.unzip(to: freshTempDir())
        }
    }

    @Test func driveLetterPathIsRejected() throws {
        let archive = buildArchive([
            RawEntry(name: "C:evil.txt", payload: Data("hostile".utf8))
        ])
        let zip = try MiniZip(data: archive)
        #expect(throws: MiniZipError.pathTraversal) {
            try zip.unzip(to: freshTempDir())
        }
    }

    // MARK: - 3. Truncated filename/record

    @Test func centralRecordDeclaringANameLengthBeyondTheBufferIsRejected() {
        let archive = buildArchive([
            RawEntry(name: "x", declaredNameLength: 9000)
        ])
        #expect(throws: MiniZipError.truncatedRecord) {
            _ = try MiniZip(data: archive)
        }
    }

    // MARK: - 4. Declared oversized output

    @Test func declaredOversizedUncompressedSizeIsRejectedBeforeAllocation() {
        let archive = buildArchive([
            RawEntry(
                name: "bomb.bin",
                method: 8,
                payload: Data([0x00, 0x01, 0x02, 0x03]),
                declaredCompressedSize: 4,
                declaredUncompressedSize: 1_000_000_000
            )
        ])
        #expect(throws: MiniZipError.entryTooLarge) {
            _ = try MiniZip(data: archive)
        }
    }

    // MARK: - 5. Excessive ratio / cumulative size

    @Test func implausibleCompressionRatioIsRejected() {
        let archive = buildArchive([
            RawEntry(
                name: "ratio.bin",
                method: 8,
                payload: Data([0x00, 0x01, 0x02, 0x03]),
                declaredCompressedSize: 4,
                declaredUncompressedSize: 50_000
            )
        ])
        #expect(throws: MiniZipError.suspiciousCompressionRatio) {
            _ = try MiniZip(data: archive)
        }
    }

    @Test func excessiveCumulativeUncompressedSizeIsRejected() {
        let entry = RawEntry(
            name: "chunk.bin",
            method: 8,
            payload: Data([0x00, 0x01, 0x02, 0x03]),
            declaredCompressedSize: 200_000,
            declaredUncompressedSize: 180_000_000
        )
        var chunk2 = entry; chunk2.name = "chunk2.bin"
        var chunk3 = entry; chunk3.name = "chunk3.bin"
        let archive = buildArchive([entry, chunk2, chunk3])
        #expect(throws: MiniZipError.archiveTooLarge) {
            _ = try MiniZip(data: archive)
        }
    }

    // MARK: - 6. Unsupported / encrypted entry

    @Test func encryptedEntryIsRejected() {
        let archive = buildArchive([
            RawEntry(name: "secret.txt", flags: 0x1, payload: Data("cipher".utf8))
        ])
        #expect(throws: MiniZipError.unsupportedEntry) {
            _ = try MiniZip(data: archive)
        }
    }

    @Test func unsupportedCompressionMethodIsRejected() {
        let archive = buildArchive([
            RawEntry(name: "weird.bin", method: 99, payload: Data([0x00]))
        ])
        #expect(throws: MiniZipError.unsupportedEntry) {
            _ = try MiniZip(data: archive)
        }
    }

    // MARK: - 7. A valid minimal EPUB still opens

    @Test func validMinimalEPUBStillOpensAndExtracts() throws {
        let data = try Data(contentsOf: try EPUBTests.sampleEPUB)
        let zip = try MiniZip(data: data)
        let directory = freshTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }

        try zip.unzip(to: directory)

        let mimetype = try Data(contentsOf: directory.appendingPathComponent("mimetype"))
        #expect(String(decoding: mimetype, as: UTF8.self) == "application/epub+zip")
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("OEBPS/content.opf").path
        ))

        let doc = try EPUBDocument.open(epubURL: try EPUBTests.sampleEPUB, into: freshTempDir())
        #expect(doc.spineURLs.count == 2)
    }
}
