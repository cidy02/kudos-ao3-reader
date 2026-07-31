import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Tests converter versioning and rebuilding a work from its archived original.
@MainActor
struct WorkReconversionTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func write(_ contents: String, _ ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reconv-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func cleanUp(_ work: SavedWork) {
        try? FileManager.default.removeItem(at: work.fileURL)
        if let original = Storage.existingOriginalDocumentURL(for: work.id) {
            try? FileManager.default.removeItem(at: original)
        }
        WorkConversionRecord.delete(for: work.id)
    }

    // MARK: - The record

    @Test func aConvertedImportRecordsTheConverterVersion() async throws {
        let context = try makeContext()
        let source = try write("Chapter 1: Start\n\nSome prose to convert.", "txt")
        defer { try? FileManager.default.removeItem(at: source) }

        let result = try await UserDocumentImport.perform(source, into: context)
        let work = result.outcome.work
        defer { cleanUp(work) }

        let record = try #require(WorkConversionRecord.read(for: work.id))
        #expect(record.converterVersion == ImportedDocumentConverter.converterVersion)
        #expect(record.format == ImportedFileFormat.plainText.rawValue)
        #expect(record.originalFileName == source.lastPathComponent)
        #expect(!record.isStale)
    }

    @Test func theRecordSidecarIsNotMistakenForTheOriginalFile() async throws {
        // Both are named after the work id and live in the same directory. Returning the
        // JSON here would make re-conversion try to convert its own bookkeeping.
        let context = try makeContext()
        let source = try write("Prose for the original file.", "txt")
        defer { try? FileManager.default.removeItem(at: source) }

        let work = try await UserDocumentImport.perform(source, into: context).outcome.work
        defer { cleanUp(work) }

        let original = try #require(Storage.existingOriginalDocumentURL(for: work.id))
        #expect(original.pathExtension == "txt")
        #expect(!original.lastPathComponent.hasSuffix(".conversion.json"))
    }

    // MARK: - Staleness

    @Test func anOlderVersionIsReportedAsStaleAndOffersARebuild() async throws {
        let context = try makeContext()
        let source = try write("Chapter 1: One\n\nFirst.\n\nChapter 2: Two\n\nSecond.", "txt")
        defer { try? FileManager.default.removeItem(at: source) }

        let work = try await UserDocumentImport.perform(source, into: context).outcome.work
        defer { cleanUp(work) }

        // Pretend it was imported by an earlier converter.
        WorkConversionRecord(
            converterVersion: ImportedDocumentConverter.converterVersion - 1,
            format: ImportedFileFormat.plainText.rawValue,
            originalFileName: source.lastPathComponent
        ).write(for: work.id)

        let candidate = try #require(WorkReconversion.candidate(for: work))
        #expect(candidate.isStale)
        #expect(WorkReconversion.staleWorks(in: context).count == 1)
    }

    @Test func aWorkAtTheCurrentVersionIsNotStale() async throws {
        let context = try makeContext()
        let source = try write("Just prose.", "txt")
        defer { try? FileManager.default.removeItem(at: source) }

        let work = try await UserDocumentImport.perform(source, into: context).outcome.work
        defer { cleanUp(work) }

        #expect(WorkReconversion.candidate(for: work)?.isStale == false)
        #expect(WorkReconversion.staleWorks(in: context).isEmpty)
    }

    @Test func aPlainEPUBImportOffersNoRebuild() async throws {
        // Nothing was converted, so there is no original archived and nothing to redo.
        let context = try makeContext()
        let epub = try EPUBBuilder.archive(
            metadata: .init(title: "Already An EPUB"),
            chapters: [.init(title: "One", bodyXHTML: "<p>Text.</p>")]
        )
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString).epub")
        try epub.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let work = try await UserDocumentImport.perform(source, into: context).outcome.work
        defer { cleanUp(work) }

        #expect(WorkConversionRecord.read(for: work.id) == nil)
        #expect(WorkReconversion.candidate(for: work) == nil)
    }

    // MARK: - Rebuilding

    @Test func rebuildingReplacesTheEPUBAndKeepsTheWorksIdentity() async throws {
        let context = try makeContext()
        let source = try write("Chapter 1: One\n\nFirst chapter.\n\nChapter 2: Two\n\nSecond chapter.", "txt")
        defer { try? FileManager.default.removeItem(at: source) }

        let work = try await UserDocumentImport.perform(source, into: context).outcome.work
        defer { cleanUp(work) }

        // Things that must survive a rebuild: the record, and the reading position.
        let id = work.id
        work.isFavorite = true
        work.readiumLocator = "{\"href\":\"chapter-2.xhtml\"}"
        WorkConversionRecord(
            converterVersion: 1,
            format: ImportedFileFormat.plainText.rawValue,
            originalFileName: source.lastPathComponent
        ).write(for: work.id)

        try await WorkReconversion.reconvert(work, in: context)

        #expect(work.id == id, "a rebuild must not create a new work")
        #expect(work.isFavorite, "library state must survive")
        #expect(work.readiumLocator == "{\"href\":\"chapter-2.xhtml\"}", "progress must survive")
        #expect(work.hasEPUB)
        #expect(try EPUBDocument.inspectPackage(ofEPUBAt: work.fileURL).readableItemCount == 2)
        // And the record now says it is current, so it stops offering a rebuild.
        #expect(WorkConversionRecord.read(for: work.id)?.isStale == false)
        #expect(WorkReconversion.staleWorks(in: context).isEmpty)
    }

    @Test func rebuildingWithoutAnOriginalFailsWithAnActionableMessage() async throws {
        let context = try makeContext()
        let work = SavedWork(title: "No Original", author: "A")
        context.insert(work)

        await #expect(throws: WorkReconversion.ReconversionError.noOriginalAvailable) {
            try await WorkReconversion.reconvert(work, in: context)
        }
        let message = WorkReconversion.ReconversionError.noOriginalAvailable.errorDescription ?? ""
        #expect(message.lowercased().contains("import the file again"))
    }

    @Test func permanentDeletionRemovesTheConversionRecordToo() async throws {
        let context = try makeContext()
        let source = try write("Prose.", "txt")
        defer { try? FileManager.default.removeItem(at: source) }

        let work = try await UserDocumentImport.perform(source, into: context).outcome.work
        let id = work.id
        #expect(WorkConversionRecord.read(for: id) != nil)

        WorkLifecycle.hardDelete(work, in: context)
        #expect(WorkConversionRecord.read(for: id) == nil)
        #expect(Storage.existingOriginalDocumentURL(for: id) == nil)
    }
}
