import Foundation
import SwiftData
import Testing
@testable import Kudos

// Takes PersistenceOperationGate like FolderSyncTests, so it serializes with the other gate suites.
extension PersistenceGateSuites {
/// T-541, end to end through `FolderSyncService`: the paths the direct `apply` tests skip.
@MainActor
@Suite(.serialized)
struct CompleteSnapshotSyncTests {
    private func container() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func defaults() throws -> UserDefaults {
        let name = "CompleteSnapshotSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompleteSnapshotSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The reported bug: a setting changed here was put back by the folder's older copy on
    /// the next sync, then published back out.
    @Test func aSettingChangedHereSurvivesTheNextSyncAndReachesTheOtherDevice() async throws {
        let shared = try folder()
        defer { try? FileManager.default.removeItem(at: shared) }
        let here = try defaults(), there = try defaults()
        let hereStore = try container(), thereStore = try container()
        defer { FolderSyncService.disconnect(defaults: here); FolderSyncService.disconnect(defaults: there) }
        here.set(18.0, forKey: "readerFontPt")
        try FolderSyncService.connect(to: shared, defaults: here)
        _ = try await FolderSyncService.syncNow(in: hereStore.mainContext, defaults: here)
        try FolderSyncService.connect(to: shared, defaults: there)
        _ = try await FolderSyncService.syncNow(in: thereStore.mainContext, defaults: there)
        #expect(there.double(forKey: "readerFontPt") == 18)

        here.set(22.0, forKey: "readerFontPt")
        _ = try await FolderSyncService.syncNow(in: hereStore.mainContext, defaults: here)
        #expect(here.double(forKey: "readerFontPt") == 22)

        _ = try await FolderSyncService.syncNow(in: thereStore.mainContext, defaults: there)
        #expect(there.double(forKey: "readerFontPt") == 22)
    }

    /// Recently Deleted came back empty on another device: the work's own deletion record
    /// suppressed the archive's copy of it.
    @Test func aRecentlyDeletedWorkArrivesInRecentlyDeleted() async throws {
        let shared = try folder()
        defer { try? FileManager.default.removeItem(at: shared) }
        let here = try defaults(), there = try defaults()
        let hereStore = try container(), thereStore = try container()
        defer { FolderSyncService.disconnect(defaults: here); FolderSyncService.disconnect(defaults: there) }
        let work = SavedWork(id: UUID(), title: "Deleted but recoverable", author: "Writer")
        work.sourceURL = "https://archiveofourown.org/works/\(Int.random(in: 10_000_000...99_999_999))"
        hereStore.mainContext.insert(work)
        try hereStore.mainContext.save()
        PreservedWorkService.softDelete(work, in: hereStore.mainContext)
        try FolderSyncService.connect(to: shared, defaults: here)
        _ = try await FolderSyncService.syncNow(in: hereStore.mainContext, defaults: here)

        try FolderSyncService.connect(to: shared, defaults: there)
        _ = try await FolderSyncService.syncNow(in: thereStore.mainContext, defaults: there)

        let arrived = try #require(try thereStore.mainContext.fetch(FetchDescriptor<SavedWork>()).first { $0.id == work.id })
        #expect(arrived.isPendingDeletion)
    }

    /// Fifth review: Recently Deleted collections and queues arrive the same way, and one deleted
    /// for good afterwards does not come back.
    @Test func recentlyDeletedCollectionsAndQueuesArriveAndPermanentDeletesStayGone() async throws {
        let shared = try folder()
        defer { try? FileManager.default.removeItem(at: shared) }
        let here = try defaults(), there = try defaults()
        let hereStore = try container(), thereStore = try container()
        defer { FolderSyncService.disconnect(defaults: here); FolderSyncService.disconnect(defaults: there) }
        let context = hereStore.mainContext
        let shelf = WorkCollection(name: "Recoverable shelf")
        let queue = ReadingQueue(name: "Recoverable queue", kind: .custom)
        let goneShelf = WorkCollection(name: "Gone shelf")
        [shelf, goneShelf].forEach(context.insert)
        context.insert(queue)
        try context.save()
        PreservedWorkService.softDelete(shelf, in: context)
        PreservedWorkService.softDelete(queue, in: context)
        PreservedWorkService.softDelete(goneShelf, in: context)
        PreservedWorkService.deletePermanently(goneShelf, in: context)
        let permanent = try context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.deletionReason == SyncTombstones.collectionPermanentlyDeletedReason }
        #expect(permanent.count == 1)
        try FolderSyncService.connect(to: shared, defaults: here)
        _ = try await FolderSyncService.syncNow(in: context, defaults: here)

        try FolderSyncService.connect(to: shared, defaults: there)
        _ = try await FolderSyncService.syncNow(in: thereStore.mainContext, defaults: there)

        let shelves = try thereStore.mainContext.fetch(FetchDescriptor<WorkCollection>())
        let queues = try thereStore.mainContext.fetch(FetchDescriptor<ReadingQueue>())
        #expect(shelves.first { $0.id == shelf.id }?.isPendingDeletion == true)
        #expect(queues.first { $0.id == queue.id }?.isPendingDeletion == true)
        #expect(!shelves.contains { $0.id == goneShelf.id })
    }
}
}
