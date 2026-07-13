import Foundation

/// Hand-assembled raw ZIP byte sequences for hostile-archive test fixtures —
/// not real compressed data, so each hostile shape (truncated name length,
/// declared-vs-actual size mismatch, oversized ratio, unsafe entry name) can
/// be constructed precisely and independently of the DEFLATE codec. Shared by
/// `MiniZipHostileTests` and `KudosBackupTests` (A5-F2/A5-F3 coverage).
enum HostileZipFixture {
    struct Entry {
        var name: String
        var method: UInt16 = 0
        var flags: UInt16 = 0
        var payload: Data = Data()
        var declaredCompressedSize: Int?
        var declaredUncompressedSize: Int?
        var declaredNameLength: Int?
    }

    /// Assembles a minimal ZIP (local headers + central directory + EOCD) from
    /// raw entry specs, allowing declared sizes/name-lengths to lie about the
    /// actual bytes present — exactly the shape a hostile archive would exploit.
    static func build(_ entries: [Entry]) -> Data {
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

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)
        ])
    }

    /// Entries for a minimal but structurally valid EPUB — real container.xml,
    /// a real OPF with one manifest item and matching spine entry, and that
    /// chapter's content. `EPUBDocument.inspectPackage` (and full `unzip`)
    /// both succeed on `build(minimalValidEPUBEntries)` alone. Used as the base
    /// for tests that append one additional, unreferenced hostile entry to
    /// prove validation covers every entry, not just the ones a manifest
    /// happens to name.
    static let minimalValidEPUBEntries: [Entry] = [
        Entry(name: "mimetype", payload: Data("application/epub+zip".utf8)),
        Entry(name: "META-INF/container.xml", payload: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.utf8)),
        Entry(name: "OEBPS/content.opf", payload: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Minimal Fixture</dc:title>
          </metadata>
          <manifest>
            <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)),
        Entry(name: "OEBPS/ch1.xhtml", payload: Data("<html><body><p>Hello.</p></body></html>".utf8))
    ]
}
