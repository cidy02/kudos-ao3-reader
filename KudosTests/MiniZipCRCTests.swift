import Foundation
import Testing
@testable import Kudos

/// Regression cover for the CRC-32 a `.kudosbackup` carries but nothing read.
///
/// `ArchiveWriter` computes a real CRC for every entry — reading file-backed
/// payloads twice to do it — and writes it into both the local header and the
/// central directory. The reader then never looked at it: `MiniZip.extract`
/// returns stored payloads verbatim, and every `.kudosbackup` entry is stored,
/// so a flipped byte anywhere in a backup restored silently and `replaceEPUB`
/// wrote the damaged copy over the good local one.
///
/// These tests pin the two things the fix depends on: that the CRC is read from
/// the right place in the central directory, and that a corrupted payload
/// actually fails the comparison. Before the fix `declaredCRC32(named:)` did
/// not exist, so there was no value to compare against at all.
struct MiniZipCRCTests {
    private static let entryName = "Works/9F1C.epub"

    /// Distinctive and long enough to survive as a searchable run of bytes in
    /// the stored archive, so a test can find and corrupt the payload itself
    /// rather than guessing an offset.
    private static func payload() -> Data {
        Data(Array(repeating: Data("kudos-backup-payload-".utf8), count: 64).joined())
    }

    @Test func theDeclaredCRCIsTheRealCRCOfTheStoredPayload() throws {
        let payload = Self.payload()
        let archive = try MiniZip.archiveData([(name: Self.entryName, data: payload)])
        let zip = try MiniZip(data: archive)

        // Fails if the central-directory CRC is read from the wrong offset: any
        // neighbouring field (method, sizes, the timestamps) gives a different
        // number, and +16 is the one place the real checksum lives.
        #expect(zip.declaredCRC32(named: Self.entryName) == MiniZip.crc32(payload))
    }

    @Test func aFlippedPayloadByteNoLongerMatchesTheDeclaredCRC() throws {
        let payload = Self.payload()
        var archive = try MiniZip.archiveData([(name: Self.entryName, data: payload)])

        // Stored entries appear verbatim, so the payload is findable — and this
        // corrupts only the bytes, leaving every declared size intact. That is
        // the case the reader could not see: sizes still agree, the entry still
        // extracts, and the contents are wrong.
        let span = try #require(archive.range(of: payload))
        archive[span.lowerBound + 7] ^= 0x01

        let zip = try MiniZip(data: archive)
        let extracted = try #require(zip.data(named: Self.entryName))
        #expect(extracted.count == payload.count)
        #expect(extracted != payload)

        let declared = try #require(zip.declaredCRC32(named: Self.entryName))
        #expect(MiniZip.crc32(extracted) != declared)
    }

    /// An untouched archive must still pass, or the check would reject every
    /// healthy backup — a failure in the far more damaging direction.
    @Test func anIntactArchiveStillPassesItsOwnCheck() throws {
        let payload = Self.payload()
        let archive = try MiniZip.archiveData([
            (name: Self.entryName, data: payload),
            (name: "manifest.json", data: Data(#"{"version":8}"#.utf8)),
        ])
        let zip = try MiniZip(data: archive)

        for name in [Self.entryName, "manifest.json"] {
            let bytes = try #require(zip.data(named: name))
            #expect(MiniZip.crc32(bytes) == zip.declaredCRC32(named: name))
        }
    }

    @Test func anAbsentEntryDeclaresNoCRC() throws {
        let archive = try MiniZip.archiveData([(name: Self.entryName, data: Self.payload())])
        let zip = try MiniZip(data: archive)
        #expect(zip.declaredCRC32(named: "Works/nothing-here.epub") == nil)
    }
}
