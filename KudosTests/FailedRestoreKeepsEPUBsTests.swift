import Foundation
import SwiftData
import Testing
@testable import Kudos

/// A restore that fails must not have changed the reader's books.
///
/// `restore` discards its database work on failure, but the filesystem has no
/// rollback — and `ReadingQueueService.replaceEPUB` replaces with
/// `backupItemName: nil`, which *discards* the file it displaces. Right for a
/// download, wrong for a restore. So a restore that threw partway through had
/// already permanently swapped every EPUB it had reached and thrown the
/// originals away, while reporting an error as though nothing had happened.
///
/// The failure used here is the real one that makes this reachable: fonts are
/// validated after the works are written, and one unreadable font rejects the
/// whole package.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct FailedRestoreKeepsEPUBsTests {
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
        let name = "FailedRestoreKeepsEPUBsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func epub(_ title: String) throws -> Data {
        try EPUBBuilder.archive(
            metadata: .init(title: title),
            chapters: [.init(title: "One", bodyXHTML: "<p>\(title)</p>")],
            modified: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func aRestoreThatFailsLeavesTheExistingEPUBUntouched() throws {
        let defaults = try testDefaults()
        let localBytes = try epub("Local Copy")
        let incomingBytes = try epub("Incoming Copy")
        #expect(localBytes != incomingBytes)

        // The reader's device: one work with its book already on disk.
        let context = try makeContext()
        let work = SavedWork(id: UUID(), title: "Kept", author: "Writer")
        work.hasEPUB = true
        context.insert(work)
        try context.save()
        try FileManager.default.createDirectory(
            at: work.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try localBytes.write(to: work.fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        // A backup carrying a different copy of the same work, and a font that
        // will fail validation — which happens after the works are written.
        let staging = try makeContext()
        let archivedWork = SavedWork(id: work.id, title: "Kept", author: "Writer")
        archivedWork.hasEPUB = true
        let badFont = CustomFont(name: "Broken", fileName: "broken.ttf")
        staging.insert(archivedWork)
        staging.insert(badFont)
        try staging.save()
        let manifest = try KudosBackupService.makeContents(
            works: [archivedWork], bookmarks: [], fonts: [badFont], readingQueues: [],
            defaults: try testDefaults()
        ).manifest
        let contents = KudosBackupContents(
            manifest: manifest,
            epubFiles: [work.id: incomingBytes],
            fontFiles: ["broken.ttf": Data("this is not a font".utf8)]
        )

        // `.replaceLibrary`, not `.merge`: merge leaves an active work's local
        // state alone entirely, so nothing would be replaced and the assertion
        // below would hold for the wrong reason. The sibling test is what
        // caught that.
        #expect(throws: (any Error).self) {
            _ = try KudosBackupService.restore(
                contents, into: context, defaults: defaults, mode: .replaceLibrary
            )
        }

        // The book on disk is still the reader's.
        #expect(try Data(contentsOf: work.fileURL) == localBytes)
    }

    /// The other half: when the restore succeeds, the incoming copy is kept and
    /// the parked original is not put back over it.
    @Test func aRestoreThatSucceedsKeepsTheIncomingEPUB() throws {
        let defaults = try testDefaults()
        let localBytes = try epub("Local Copy")
        let incomingBytes = try epub("Incoming Copy")

        let context = try makeContext()
        let work = SavedWork(id: UUID(), title: "Replaced", author: "Writer")
        work.hasEPUB = true
        context.insert(work)
        try context.save()
        try FileManager.default.createDirectory(
            at: work.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try localBytes.write(to: work.fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        let staging = try makeContext()
        let archivedWork = SavedWork(id: work.id, title: "Replaced", author: "Writer")
        archivedWork.hasEPUB = true
        staging.insert(archivedWork)
        try staging.save()
        let manifest = try KudosBackupService.makeContents(
            works: [archivedWork], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        ).manifest
        let contents = KudosBackupContents(
            manifest: manifest, epubFiles: [work.id: incomingBytes]
        )

        _ = try KudosBackupService.restore(
            contents, into: context, defaults: defaults, mode: .replaceLibrary
        )

        #expect(try Data(contentsOf: work.fileURL) == incomingBytes)
    }
}
}
