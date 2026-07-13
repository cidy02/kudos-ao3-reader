import Foundation
import SwiftData
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
        let zip = try MiniZip(data: data)
        #expect(zip.names.contains("mimetype"))
        #expect(zip.names.contains("OEBPS/content.opf"))
        let mimetype = try #require(zip.data(named: "mimetype"))
        #expect(String(decoding: mimetype, as: UTF8.self) == "application/epub+zip")
    }

    @Test func miniZipRejectsNonZipData() {
        #expect(throws: MiniZipError.malformedArchive) {
            _ = try MiniZip(data: Data("not a zip".utf8))
        }
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

    @Test func packageInspectionReportsReadableItems() throws {
        let package = try EPUBDocument.inspectPackage(ofEPUBAt: try Self.sampleEPUB)
        #expect(package.readableItemCount == 2)
        #expect(package.metadata.title == "A Test Work")
    }

    @Test func canonicalAO3WorkURLNormalizesWorkAndDownloadLinks() {
        let workText = "Source: https://archiveofourown.org/works/12345?view_full_work=true"
        let downloadText = "https://archiveofourown.org/downloads/98765/example.epub"
        #expect(EPUBMetadata.canonicalAO3WorkURL(in: workText) == "https://archiveofourown.org/works/12345")
        #expect(EPUBMetadata.canonicalAO3WorkURL(in: downloadText) == "https://archiveofourown.org/works/98765")
    }

    @Test @MainActor func userImportCreatesSavedWorkAndDetectsDuplicate() async throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        var copiedEPUB: URL?
        defer {
            if let copiedEPUB {
                try? FileManager.default.removeItem(at: copiedEPUB)
            }
        }

        let importedOutcome = try await importUserEPUB(try Self.sampleEPUB, into: context)
        let imported: SavedWork
        switch importedOutcome {
        case .imported(let work):
            imported = work
        case .restored, .duplicate:
            Issue.record("Expected a new EPUB import")
            return
        }
        copiedEPUB = imported.fileURL

        #expect(imported.title == "A Test Work")
        #expect(imported.author == "Test Author")
        #expect(imported.rating == "Teen And Up Audiences")
        #expect(imported.workTags == ["Fluff", "Angst"])
        #expect(imported.chapters == "2/2")
        #expect(imported.hasEPUB)
        #expect(FileManager.default.fileExists(atPath: imported.fileURL.path))

        // A plain import must not be marked isSaved — that flag (plus !isQueuedForLater)
        // is what LibrarySectionKind.savedForLater treats as "belongs in Saved for
        // Later", a legacy carve-out for pre-queue saves that a fresh import should
        // never fall into. It still lands in Downloaded via hasEPUB, matching
        // importEPUB's (the AO3-download path) existing, unaffected convention.
        #expect(!imported.isSaved)
        #expect(!LibrarySectionKind.savedForLater.works(from: [imported], visible: { _ in true }).contains(imported))
        #expect(LibrarySectionKind.downloaded.works(from: [imported], visible: { _ in true }).contains(imported))

        // Removing isSaved must not remove protection from a plain (non-AO3) import:
        // with no ao3WorkID, freeing the EPUB would make it permanently unrecoverable.
        // isProtected has to stay true through some other path when isSaved is false.
        #expect(imported.ao3WorkID == nil)
        #expect(imported.isProtected)

        let duplicateOutcome = try await importUserEPUB(try Self.sampleEPUB, into: context)
        switch duplicateOutcome {
        case .duplicate(let duplicate):
            #expect(duplicate.id == imported.id)
        case .imported, .restored:
            Issue.record("Expected the second import to be treated as a duplicate")
        }
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).count == 1)
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

    /// A plain local file (the overwhelmingly common import case — "On My iPhone",
    /// or any non-iCloud source) is not a ubiquitous item, so the iCloud-download
    /// wait must no-op immediately rather than adding any latency or hanging.
    @Test func waitForUbiquitousDownloadNoOpsOnAPlainLocalFile() async throws {
        let local = try Self.sampleEPUB
        let start = Date()
        try await waitForUbiquitousDownload(of: local, pollInterval: 5, timeout: 30)
        // If this fell through to the poll loop it would take at least one
        // `pollInterval` (5s) — asserting well under that proves the early return.
        #expect(Date().timeIntervalSince(start) < 1)
    }
}
