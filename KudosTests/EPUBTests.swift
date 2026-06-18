import Foundation
import Testing
@testable import Kudos

/// Tests the EPUB stack against a minimal hand-built fixture (`sample.epub`):
/// the MiniZip reader, OPF metadata extraction, NCX table-of-contents building,
/// and the typed-error paths.
struct EPUBTests {
    /// Anchors `Bundle(for:)` to the test bundle so the fixture can be found.
    final class BundleAnchor {}

    static var sampleEPUB: URL {
        get throws {
            try #require(Bundle(for: BundleAnchor.self).url(forResource: "sample", withExtension: "epub"))
        }
    }

    private func freshTempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func miniZipReadsAndExtractsEntries() throws {
        let data = try Data(contentsOf: try Self.sampleEPUB)
        let zip = try #require(MiniZip(data: data))
        #expect(zip.names.contains("mimetype"))
        #expect(zip.names.contains("OEBPS/content.opf"))
        let mimetype = try #require(zip.data(named: "mimetype"))
        #expect(String(decoding: mimetype, as: UTF8.self) == "application/epub+zip")
    }

    @Test func miniZipRejectsNonZipData() {
        #expect(MiniZip(data: Data("not a zip".utf8)) == nil)
    }

    @Test func metadataExtraction() throws {
        let meta = try EPUBDocument.metadata(ofEPUBAt: try Self.sampleEPUB)
        #expect(meta.title == "A Test Work")
        #expect(meta.author == "Test Author")
        #expect(meta.language == "en")
        #expect(meta.rating == "Teen And Up Audiences")
        #expect(meta.subjects.contains("Fluff"))
        #expect(meta.subjects.contains("Angst"))
        #expect(meta.seriesTitle == "My Series")
        #expect(meta.seriesIndex == 2)
    }

    @Test func tableOfContentsFromNCX() throws {
        let doc = try EPUBDocument.open(epubURL: try Self.sampleEPUB, into: freshTempDir())
        #expect(doc.spineURLs.count == 2)
        #expect(doc.chapters.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(doc.chapters.map(\.spineIndex) == [0, 1])
    }

    @Test func ratingPickedOutOfSubjects() {
        #expect(EPUBMetadata.rating(in: ["Fluff", "Mature", "Angst"]) == "Mature")
        #expect(EPUBMetadata.rating(in: ["Fluff", "Angst"]).isEmpty)
    }

    @Test func openingNonEPUBThrowsNotAnEPUB() throws {
        let bad = freshTempDir().appendingPathComponent("bad.epub")
        try FileManager.default.createDirectory(at: bad.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not a zip".utf8).write(to: bad)
        do {
            _ = try EPUBDocument.open(epubURL: bad, into: freshTempDir())
            Issue.record("Expected EPUBError.notAnEPUB")
        } catch EPUBError.notAnEPUB {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func metadataOfMissingFileThrowsUnreadable() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).epub")
        do {
            _ = try EPUBDocument.metadata(ofEPUBAt: missing)
            Issue.record("Expected EPUBError.unreadableFile")
        } catch EPUBError.unreadableFile {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
