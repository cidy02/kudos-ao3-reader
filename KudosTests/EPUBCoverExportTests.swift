import Foundation
import SwiftData
import Testing
@testable import Kudos

struct EPUBCoverExportTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
    }

    @Test func addsCoverDeclarationAndReadableFirstPage() throws {
        let target = temporaryFile()
        defer { try? FileManager.default.removeItem(at: target) }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try EPUBCoverExport.copy(from: EPUBTests.sampleEPUB, to: target,
                                 includeCover: true, coverJPEG: jpeg)
        let zip = try MiniZip(data: Data(contentsOf: target))
        let opf = try #require(zip.data(named: "OEBPS/content.opf"))
        let before = OPFParser()
        let source = try MiniZip(data: Data(contentsOf: EPUBTests.sampleEPUB))
        #expect(before.parse(try #require(source.data(named: "OEBPS/content.opf"))))
        #expect(before.coverMetaID == nil)
        let after = OPFParser()
        #expect(after.parse(opf))
        #expect(after.coverMetaID == "kudos-export-cover-image")
        #expect(after.manifestProps["kudos-export-cover-image"] == "cover-image")
        #expect(after.spine.first == "kudos-export-cover-page")
        #expect(zip.data(named: "OEBPS/kudos-export-cover.jpg") == jpeg)
        let unpacked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: unpacked) }
        let document = try EPUBDocument.open(epubURL: target, into: unpacked)
        #expect(document.spineURLs.count == before.spine.count + 1)
    }

    @Test func existingDeclaredCoverIsKeptByteForByte() throws {
        let original = try Data(contentsOf: EPUBTests.sampleEPUB)
        let zip = try MiniZip(data: original)
        let opfBytes = try #require(zip.data(named: "OEBPS/content.opf"))
        let opf = try #require(String(data: opfBytes, encoding: .utf8))
        let declared = opf.replacingOccurrences(of: "</metadata>",
            with: "<meta name=\"cover\" content=\"existing\"/></metadata>")
        #expect(declared != opf)
        let entries = try zip.names.map { name -> (name: String, data: Data) in
            (name, name == "OEBPS/content.opf" ? Data(declared.utf8) : try #require(zip.data(named: name)))
        }
        let source = temporaryFile(), target = temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }
        let bytes = try MiniZip.archiveData(entries)
        try bytes.write(to: source)
        try EPUBCoverExport.copy(from: source, to: target, includeCover: true, coverJPEG: Data([1]))
        #expect(try Data(contentsOf: target) == bytes)
    }

    @Test func disabledCoverPreservesOriginalBytes() throws {
        let target = temporaryFile()
        defer { try? FileManager.default.removeItem(at: target) }
        try EPUBCoverExport.copy(from: EPUBTests.sampleEPUB, to: target, includeCover: false)
        #expect(try Data(contentsOf: target) == Data(contentsOf: EPUBTests.sampleEPUB))
    }

    @Test @MainActor func coveredFileImportsAsAWork() async throws {
        let target = temporaryFile()
        defer { try? FileManager.default.removeItem(at: target) }
        try EPUBCoverExport.copy(from: EPUBTests.sampleEPUB, to: target,
                                 includeCover: true, coverJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let outcome = try await importUserEPUB(target, into: container.mainContext)
        switch outcome {
        case .imported(let work):
            #expect(work.title == "A Test Work")
            defer { try? FileManager.default.removeItem(at: work.fileURL) }
        case .restored, .duplicate:
            Issue.record("Expected a covered EPUB to import as a new work")
        }
    }
}
