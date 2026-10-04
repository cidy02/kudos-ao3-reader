import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-276's two new optional fields: `SavedWork.hiddenFromHistoryAt` (1ah's Remove
/// from history) and `ReadingQueue.notes` (1h's queue description) — History
/// membership, un-hiding on read, and the backup / folder-sync round trip,
/// including an archive written before either key existed.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct HistoryHideAndQueueNotesTests {
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
        let name = "HistoryHideAndQueueNotesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func history(_ works: [SavedWork]) -> [UUID] {
        LibrarySectionKind.history.works(from: works, visible: { _ in true }).map(\.id)
    }

    /// A read work with a queue holding it, both stamped at `modifiedAt`.
    private func fixture(
        workID: UUID = UUID(), queueID: UUID = UUID(), modifiedAt: Date, in context: ModelContext
    ) throws -> (work: SavedWork, queue: ReadingQueue) {
        let work = SavedWork(id: workID, title: "Read Once", author: "Writer")
        work.hasEPUB = false
        work.lastReadDate = modifiedAt
        work.markModified(modifiedAt)
        let queue = ReadingQueue(id: queueID, name: "Rereads", dateCreated: modifiedAt, dateUpdated: modifiedAt)
        let membership = ReadingQueueMembership(queue: queue, work: work, queuedAt: modifiedAt)
        context.insert(work)
        context.insert(queue)
        context.insert(membership)
        try context.save()
        return (work, queue)
    }

    private func contents(_ work: SavedWork, _ queue: ReadingQueue) throws -> KudosBackupContents {
        try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [queue], defaults: try testDefaults()
        )
    }

    /// `contents` with the named keys removed from every work and queue — the
    /// shape an older build, or Android, writes.
    private func stripping(
        _ workKey: String, _ queueKey: String, from contents: KudosBackupContents
    ) throws -> KudosBackupContents {
        var root = try #require(
            try JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
        )
        var works = try #require(root["works"] as? [[String: Any]])
        for index in works.indices { works[index].removeValue(forKey: workKey) }
        var queues = try #require(root["readingQueues"] as? [[String: Any]])
        for index in queues.indices { queues[index].removeValue(forKey: queueKey) }
        root["works"] = works
        root["readingQueues"] = queues
        let stripped = try JSONSerialization.data(withJSONObject: root)
        return KudosBackupContents(manifest: try KudosBackupContents.decodeManifest(stripped))
    }

    // MARK: History membership

    /// Removing from History hides the row and nothing else: the record, its
    /// progress and its queue place all survive, and it is not in Recently Deleted.
    @Test func removeFromHistoryHidesTheRowWithoutDeletingTheWork() throws {
        let context = try makeContext()
        let (work, _) = try fixture(modifiedAt: Date(timeIntervalSince1970: 1_000), in: context)
        #expect(history([work]) == [work.id])

        WorkLifecycle.removeFromHistory(work, in: context, at: Date(timeIntervalSince1970: 2_000))

        #expect(history([work]).isEmpty)
        #expect(work.hiddenFromHistoryAt == Date(timeIntervalSince1970: 2_000))
        #expect(!work.isPendingDeletion)
        #expect(work.lastReadDate == Date(timeIntervalSince1970: 1_000))
        #expect(work.activeQueueMemberships.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<SavedWork>()) == 1)
    }

    /// Reading it again is the way back: the reader's own progress stamp clears
    /// the marker.
    @Test func readingTheWorkAgainReturnsItToHistory() throws {
        let context = try makeContext()
        let (work, _) = try fixture(modifiedAt: Date(timeIntervalSince1970: 1_000), in: context)
        WorkLifecycle.removeFromHistory(work, in: context, at: Date(timeIntervalSince1970: 2_000))

        work.markProgressModified(Date(timeIntervalSince1970: 3_000))

        #expect(work.hiddenFromHistoryAt == nil)
        #expect(history([work]) == [work.id])
    }

    // MARK: Backup and sync

    /// A `.kudosbackup` written and read back carries both fields.
    @Test func bothFieldsSurviveAnArchiveRoundTrip() throws {
        let source = try makeContext()
        let (work, queue) = try fixture(modifiedAt: Date(timeIntervalSince1970: 1_000), in: source)
        WorkLifecycle.removeFromHistory(work, in: source, at: Date(timeIntervalSince1970: 2_000))
        queue.notes = "Everything before the sequel lands."
        try source.save()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("kudosbackup")
        try contents(work, queue).zipData().write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try KudosBackupContents.read(from: url)

        let target = try makeContext()
        _ = try KudosBackupService.restore(decoded, into: target, defaults: try testDefaults(), mode: .replaceLibrary)

        let restoredWork = try #require(try target.fetch(FetchDescriptor<SavedWork>()).first)
        // By id: a restore also creates Saved for Later, so `.first` may be that queue instead.
        let restoredQueue = try #require(
            try target.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == queue.id }
        )
        #expect(restoredWork.hiddenFromHistoryAt == Date(timeIntervalSince1970: 2_000))
        #expect(restoredQueue.notes == "Everything before the sequel lands.")
    }

    /// Folder sync (`.reconcile`): reading the work on another device writes a
    /// newer snapshot whose marker is JSON null, and that brings it back here;
    /// a newer "" clears the description here too.
    @Test func aNewerSnapshotClearsBothFieldsThroughSync() throws {
        let workID = UUID(), queueID = UUID()
        let remote = try makeContext()
        let (remoteWork, remoteQueue) = try fixture(
            workID: workID, queueID: queueID, modifiedAt: Date(timeIntervalSince1970: 9_000), in: remote
        )
        remoteQueue.notes = ""
        try remote.save()
        let archive = try contents(remoteWork, remoteQueue)

        let local = try makeContext()
        let (work, queue) = try fixture(
            workID: workID, queueID: queueID, modifiedAt: Date(timeIntervalSince1970: 1_000), in: local
        )
        work.hiddenFromHistoryAt = Date(timeIntervalSince1970: 1_000)
        queue.notes = "Old note"
        try local.save()

        _ = try KudosBackupService.restore(archive, into: local, defaults: try testDefaults(), mode: .reconcile)

        #expect(work.hiddenFromHistoryAt == nil)
        #expect(queue.notes == "")
    }

    /// An archive from before T-276 — neither key present — restores unchanged:
    /// it leaves a local marker and note alone even when it wins on recency, and
    /// a fresh restore of it reads as shown and undescribed.
    @Test func anOldBackupWithoutTheKeysRestoresUnchanged() throws {
        let workID = UUID(), queueID = UUID()
        let old = try makeContext()
        let (oldWork, oldQueue) = try fixture(
            workID: workID, queueID: queueID, modifiedAt: Date(timeIntervalSince1970: 9_000), in: old
        )
        let archive = try stripping("hiddenFromHistoryAt", "notes", from: try contents(oldWork, oldQueue))
        let archivedWork = try #require(archive.manifest.works.first)
        let archivedQueue = try #require(archive.manifest.readingQueues.first)
        #expect(archivedWork.hiddenFromHistoryAt == nil, "absent key, not a present null")
        #expect(archivedQueue.notes == nil)

        let local = try makeContext()
        let (work, queue) = try fixture(
            workID: workID, queueID: queueID, modifiedAt: Date(timeIntervalSince1970: 1_000), in: local
        )
        work.hiddenFromHistoryAt = Date(timeIntervalSince1970: 1_000)
        queue.notes = "Kept"
        try local.save()
        _ = try KudosBackupService.restore(archive, into: local, defaults: try testDefaults(), mode: .reconcile)
        #expect(work.hiddenFromHistoryAt == Date(timeIntervalSince1970: 1_000))
        #expect(queue.notes == "Kept")

        let fresh = try makeContext()
        _ = try KudosBackupService.restore(archive, into: fresh, defaults: try testDefaults(), mode: .replaceLibrary)
        let restoredWork = try #require(try fresh.fetch(FetchDescriptor<SavedWork>()).first)
        let restoredQueue = try #require(
            try fresh.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == queueID }
        )
        #expect(restoredWork.hiddenFromHistoryAt == nil)
        #expect(restoredQueue.notes == nil)
        #expect(history([restoredWork]) == [restoredWork.id])
    }
}
}
