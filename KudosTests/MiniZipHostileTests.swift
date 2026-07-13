import Foundation
import Testing
@testable import Kudos

/// A5-F2 hostile-input coverage for `MiniZip`: path traversal, truncated/malformed
/// records, oversized/ratio-abusive declared sizes, and unsupported/encrypted
/// entries must all fail with a typed `MiniZipError` before any unsafe allocation
/// or filesystem write, while a real minimal EPUB keeps opening normally.
///
/// Fixtures are hand-assembled raw ZIP byte sequences (`HostileZipFixture`, not
/// real compressed data) so each hostile shape — truncated name length,
/// declared-vs-actual size mismatch, oversized ratio — can be constructed
/// precisely and independently of the DEFLATE codec.
struct MiniZipHostileTests {
    private typealias RawEntry = HostileZipFixture.Entry

    private func buildArchive(_ entries: [RawEntry]) -> Data {
        HostileZipFixture.build(entries)
    }

    private func freshTempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    // MARK: - 1. Traversal with an outside sentinel unchanged

    @Test func pathTraversalNeverWritesOutsideTheDestinationRoot() throws {
        let archive = buildArchive([
            RawEntry(name: "../../../outside.txt", payload: Data("hostile".utf8))
        ])

        let cachesRoot = freshTempDir()
        defer { try? FileManager.default.removeItem(at: cachesRoot) }
        try FileManager.default.createDirectory(at: cachesRoot, withIntermediateDirectories: true)
        let sentinelPath = cachesRoot.appendingPathComponent("outside.txt")
        try Data("known-good".utf8).write(to: sentinelPath)
        let readerDir = cachesRoot.appendingPathComponent("Reader/\(UUID().uuidString)")

        // The unsafe name is rejected at construction, before a MiniZip even
        // exists to call `unzip` on — extraction is never attempted at all.
        #expect(throws: MiniZipError.pathTraversal) {
            _ = try MiniZip(data: archive)
        }
        #expect(try Data(contentsOf: sentinelPath) == Data("known-good".utf8))
        #expect(!FileManager.default.fileExists(atPath: readerDir.path))
    }

    // MARK: - 2. Absolute and backslash traversal

    @Test func absolutePathIsRejected() {
        let archive = buildArchive([
            RawEntry(name: "/etc/passwd", payload: Data("hostile".utf8))
        ])
        #expect(throws: MiniZipError.pathTraversal) {
            _ = try MiniZip(data: archive)
        }
    }

    @Test func backslashTraversalIsRejected() {
        let archive = buildArchive([
            RawEntry(name: "..\\..\\outside.txt", payload: Data("hostile".utf8))
        ])
        #expect(throws: MiniZipError.pathTraversal) {
            _ = try MiniZip(data: archive)
        }
    }

    @Test func driveLetterPathIsRejected() {
        let archive = buildArchive([
            RawEntry(name: "C:evil.txt", payload: Data("hostile".utf8))
        ])
        #expect(throws: MiniZipError.pathTraversal) {
            _ = try MiniZip(data: archive)
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

    // MARK: - 8. An unreferenced hostile entry still fails validation, not just extraction

    /// A backup EPUB can be structurally valid — readable container/OPF/spine —
    /// while carrying one extra entry, unsafely named, that the OPF never
    /// references. `EPUBDocument.inspectPackage` (the A5-F3 backup-restore
    /// preflight) only reads container.xml/OPF/spine by exact name; if entry
    /// names were only checked during `unzip`, this archive would pass
    /// preflight and only fail later, at real extraction/open time — after a
    /// valid local EPUB had already been overwritten. Name validation now runs
    /// for every entry while `MiniZip` parses the central directory, so the
    /// whole archive is rejected regardless of which entries a caller reads.
    @Test func structurallyValidEPUBWithUnreferencedHostileEntryIsRejected() throws {
        // Sanity check first: the base fixture alone is genuinely readable
        // through the full package-inspection pipeline, so the rejection
        // below is caused specifically by the added entry, not by some
        // incidental invalidity in the minimal OPF/container.
        let validArchive = buildArchive(HostileZipFixture.minimalValidEPUBEntries)
        let validURL = freshTempDir().appendingPathComponent("valid.epub")
        try FileManager.default.createDirectory(
            at: validURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try validArchive.write(to: validURL)
        defer { try? FileManager.default.removeItem(at: validURL.deletingLastPathComponent()) }
        #expect(try EPUBDocument.inspectPackage(ofEPUBAt: validURL).readableItemCount == 1)

        let hostileArchive = buildArchive(HostileZipFixture.minimalValidEPUBEntries + [
            RawEntry(name: "../evil.txt", payload: Data("hostile".utf8))
        ])
        #expect(throws: MiniZipError.pathTraversal) {
            _ = try MiniZip(data: hostileArchive)
        }
    }

    // MARK: - 9. Duplicate entry names

    /// Two entries sharing one name would otherwise let `data(named:)` (first
    /// match) and `unzip` (last entry wins on disk) disagree about which
    /// bytes a given name actually resolves to. Rejected as inconsistent
    /// metadata rather than left ambiguous.
    @Test func duplicateEntryNameIsRejected() {
        let archive = buildArchive([
            RawEntry(name: "dupe.txt", payload: Data("first".utf8)),
            RawEntry(name: "dupe.txt", payload: Data("second".utf8))
        ])
        #expect(throws: MiniZipError.malformedArchive) {
            _ = try MiniZip(data: archive)
        }
    }
}
