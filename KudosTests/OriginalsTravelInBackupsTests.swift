import Foundation
import SwiftData
import Testing
@testable import Kudos

/// The document a converted work was made from now travels with the backup.
///
/// `UserDocumentImport.preserveOriginal` keeps the exact file the reader handed
/// over and calls that copy "insurance". Both exporters enumerated works and
/// fonts only, so the insurance was the one thing that did not survive the
/// event it exists for: migrating to a new phone and erasing the old one.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct OriginalsTravelInBackupsTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "OriginalsTravelInBackupsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static let originalBytes = Data("%PDF-1.7 the document they imported".utf8)

    /// A work whose original PDF and conversion record are on disk, exactly as
    /// a real document import leaves them.
    private func workWithOriginal(in context: ModelContext) throws -> SavedWork {
        let work = SavedWork(id: UUID(), title: "Converted", author: "Writer")
        context.insert(work)
        try context.save()
        let original = Storage.originalDocumentURL(for: work.id, fileExtension: "pdf")
        try FileManager.default.createDirectory(
            at: original.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.originalBytes.write(to: original, options: .atomic)
        WorkConversionRecord(format: "pdf", originalFileName: "thesis.pdf").write(for: work.id)
        return work
    }

    private func cleanUp(_ workIDs: [UUID]) {
        for id in workIDs {
            if let url = Storage.existingOriginalDocumentURL(for: id) {
                try? FileManager.default.removeItem(at: url)
            }
            try? FileManager.default.removeItem(at: WorkConversionRecord.url(for: id))
        }
    }

    @Test func anOriginalSurvivesAZipRoundTrip() throws {
        let source = try makeContext()
        let work = try workWithOriginal(in: source)
        let target = try makeContext()
        defer { cleanUp([work.id]) }

        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        // Both the document and the record naming its converter.
        #expect(contents.originalFileNames.count == 2)

        // Through a real archive, not just the in-memory object.
        let reread = try KudosBackupContents(zipData: try contents.zipData())
        #expect(reread.originalFileNames.count == 2)

        // Erase this device's copies, then restore.
        cleanUp([work.id])
        #expect(Storage.existingOriginalDocumentURL(for: work.id) == nil)

        let summary = try KudosBackupService.restore(
            reread, into: target, defaults: try testDefaults(), mode: .merge
        )

        #expect(summary.restoredOriginals == 1)
        let restored = try #require(Storage.existingOriginalDocumentURL(for: work.id))
        #expect(try Data(contentsOf: restored) == Self.originalBytes)
        #expect(WorkConversionRecord.read(for: work.id)?.originalFileName == "thesis.pdf")
    }

    /// Guard: a local original is the file the reader imported on this device.
    /// The archive's copy is at best the same bytes and at worst older, and
    /// re-conversion reads whichever is on disk — so restore must not clobber.
    @Test func restoreDoesNotOverwriteAnOriginalAlreadyHere() throws {
        let source = try makeContext()
        let work = try workWithOriginal(in: source)
        defer { cleanUp([work.id]) }

        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )

        // The device's own copy differs from the archived one.
        let mine = Data("%PDF-1.7 the copy already on this device".utf8)
        let original = try #require(Storage.existingOriginalDocumentURL(for: work.id))
        try mine.write(to: original, options: .atomic)

        let target = try makeContext()
        let summary = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .merge
        )

        #expect(summary.restoredOriginals == 0)
        #expect(try Data(contentsOf: original) == mine)
    }
}
}
