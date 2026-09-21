import Foundation
import SwiftData
import Testing
@testable import Kudos

/// A device that has not finished downloading must not tell the others the
/// book is gone.
///
/// `syncNow` is a sync-down followed by a sync-up. If the download met an
/// iCloud placeholder that had not materialised, the work restored with local
/// `hasEPUB = false` — and the upload manifest was built straight from the
/// models, so the *remote* declaration became false too. The download pass is
/// `for work in manifest.works where work.hasEPUB`, so from then on nothing
/// looked for that book again. The remote file itself survived, because the
/// prune keeps assets by manifest work id; what was lost was the only reference
/// to it, which does not heal on its own if the other device is gone.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct PendingAssetIsNotAbsenceTests {
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
        let name = "PendingAssetIsNotAbsenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A manifest that promises an EPUB, with no bytes attached — exactly what
    /// an undownloaded placeholder produces.
    private func promiseWithoutBytes(for id: UUID) throws -> KudosBackupContents {
        let staging = try makeContext()
        let archived = SavedWork(id: id, title: "Late Book", author: "Writer")
        archived.hasEPUB = true
        staging.insert(archived)
        try staging.save()
        return try KudosBackupService.makeContents(
            works: [archived], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
    }

    @Test func aPromisedButUnreceivedEPUBIsNotRepublishedAsAbsent() throws {
        let context = try makeContext()
        let id = UUID()

        let summary = try KudosBackupService.restore(
            try promiseWithoutBytes(for: id),
            into: context, defaults: try testDefaults(), mode: .merge
        )
        #expect(summary.worksMissingPromisedEPUB == 1)

        let work = try #require(
            try context.fetch(FetchDescriptor<SavedWork>()).first { $0.id == id }
        )
        // This device does not have the bytes...
        #expect(!work.hasEPUB)
        #expect(work.remoteEPUBPending)

        // ...but what it publishes still says the library has them, so the
        // other devices keep offering the file and keep looking for it.
        let republished = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        #expect(republished.manifest.works.first?.hasEPUB == true)
    }

    /// The guard, and the line this fix must not cross: a book the reader
    /// really removed still publishes as absent, or freeing space on one device
    /// could never propagate.
    @Test func aWorkThatSimplyHasNoEPUBStillPublishesAsAbsent() throws {
        let context = try makeContext()
        let work = SavedWork(id: UUID(), title: "No Book", author: "Writer")
        work.hasEPUB = false
        work.remoteEPUBPending = false
        context.insert(work)
        try context.save()

        let published = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        #expect(published.manifest.works.first?.hasEPUB == false)
    }

    /// And once the bytes actually arrive, nothing is outstanding any more.
    @Test func receivingTheBytesClearsThePendingFlag() throws {
        let context = try makeContext()
        let id = UUID()
        _ = try KudosBackupService.restore(
            try promiseWithoutBytes(for: id),
            into: context, defaults: try testDefaults(), mode: .merge
        )
        let work = try #require(
            try context.fetch(FetchDescriptor<SavedWork>()).first { $0.id == id }
        )
        #expect(work.remoteEPUBPending)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).epub")
        try EPUBBuilder.archive(
            metadata: .init(title: "Late Book"),
            chapters: [.init(title: "One", bodyXHTML: "<p>Arrived.</p>")],
            modified: Date(timeIntervalSince1970: 0)
        ).write(to: staged, options: .atomic)
        try ReadingQueueService.replaceEPUB(for: work, with: staged)

        #expect(!work.remoteEPUBPending)
        #expect(!work.epubDigest.isEmpty)
    }
}
}
