import Foundation
import SwiftData
import Testing
@testable import Kudos

/// An older archive may not overwrite a newer book.
///
/// `mayReplaceEPUB` asked only whether there was something worth protecting —
/// a new record, a work with no file, or a `.preserved` one. Any other work
/// had its bytes replaced by whatever the archive supplied, with no comparison
/// of which copy was newer. Ten local chapters became five remote ones and the
/// metadata merge, which got the answer right on the very line above, had no
/// say over the file.
///
/// This had to land with the digest comparison in `readChangedRemoteAssets`:
/// that change hands more bytes to this gate, and more bytes through a gate
/// that does not check freshness is more overwritten books, not fewer.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct StaleArchiveKeepsNewerEPUBTests {
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
        let name = "StaleArchiveKeepsNewerEPUBTests.\(UUID().uuidString)"
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

    private struct Fixture {
        let context: ModelContext
        let work: SavedWork
        let localBytes: Data
        let incomingBytes: Data
    }

    /// A local work with a book on disk, and an archive of the same work
    /// carrying a different book with the given record date.
    private func fixture(archiveModifiedAt: Date, localModifiedAt: Date) throws -> Fixture {
        let localBytes = try epub("Local Copy")
        let incomingBytes = try epub("Incoming Copy")
        #expect(localBytes != incomingBytes)

        let context = try makeContext()
        let work = SavedWork(id: UUID(), title: "Shared", author: "Writer")
        work.hasEPUB = true
        work.markModified(localModifiedAt)
        context.insert(work)
        try context.save()
        try FileManager.default.createDirectory(
            at: work.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try localBytes.write(to: work.fileURL, options: .atomic)
        return Fixture(
            context: context, work: work,
            localBytes: localBytes, incomingBytes: incomingBytes
        )
    }

    private func archive(
        for work: SavedWork, bytes: Data, modifiedAt: Date
    ) throws -> KudosBackupContents {
        let staging = try makeContext()
        let archived = SavedWork(id: work.id, title: "Shared", author: "Writer")
        archived.hasEPUB = true
        archived.markModified(modifiedAt)
        staging.insert(archived)
        try staging.save()
        let manifest = try KudosBackupService.makeContents(
            works: [archived], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        ).manifest
        return KudosBackupContents(manifest: manifest, epubFiles: [work.id: bytes])
    }

    @Test func anOlderArchiveDoesNotReplaceANewerBook() throws {
        let stale = Date(timeIntervalSince1970: 1_000)
        let fresh = Date(timeIntervalSince1970: 9_000)
        let fixture = try fixture(archiveModifiedAt: stale, localModifiedAt: fresh)
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }

        _ = try KudosBackupService.restore(
            try archive(for: fixture.work, bytes: fixture.incomingBytes, modifiedAt: stale),
            into: fixture.context, defaults: try testDefaults(), mode: .reconcile
        )

        #expect(try Data(contentsOf: fixture.work.fileURL) == fixture.localBytes)
    }

    /// The guard, and the reason this is a freshness check rather than a refusal:
    /// a genuinely newer archive must still deliver its book, or sync could
    /// never update one.
    @Test func aNewerArchiveStillReplacesTheBook() throws {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 9_000)
        let fixture = try fixture(archiveModifiedAt: newer, localModifiedAt: older)
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }

        _ = try KudosBackupService.restore(
            try archive(for: fixture.work, bytes: fixture.incomingBytes, modifiedAt: newer),
            into: fixture.context, defaults: try testDefaults(), mode: .reconcile
        )

        #expect(try Data(contentsOf: fixture.work.fileURL) == fixture.incomingBytes)
    }

    /// The gate's own contract, unchanged where it was already right.
    @Test func theGateStillProtectsWhatItAlwaysDid() {
        let preserved = SavedWork(title: "Preserved", author: "Writer")
        preserved.hasEPUB = true
        preserved.epubPreservationStatusRaw = EPUBPreservationStatus.preserved.rawValue
        #expect(!KudosBackupService.mayReplaceEPUB(
            local: preserved, isNewRecord: false, incomingIsNewer: true
        ))

        let fileless = SavedWork(title: "No File", author: "Writer")
        fileless.hasEPUB = false
        #expect(KudosBackupService.mayReplaceEPUB(
            local: fileless, isNewRecord: false, incomingIsNewer: false
        ))

        let ordinary = SavedWork(title: "Ordinary", author: "Writer")
        ordinary.hasEPUB = true
        #expect(KudosBackupService.mayReplaceEPUB(
            local: ordinary, isNewRecord: false, incomingIsNewer: true
        ))
        #expect(!KudosBackupService.mayReplaceEPUB(
            local: ordinary, isNewRecord: false, incomingIsNewer: false
        ))
    }
}
}
