import Foundation
import SwiftData
import Testing
@testable import Kudos

// Serialized for the same reason as FolderSyncTests/KudosBackupTests/PersistenceSyncTests:
// PersistenceOperationGate is a process-wide static lock that can spuriously contend
// across concurrently-running test suites.
@MainActor
@Suite(.serialized)
struct PreservedWorkTests {
    @Test func softDeleteSetsFieldsAndKeepsEPUBOnDisk() throws {
        let container = try container()
        let context = container.mainContext
        let work = SavedWork(title: "Kept Work", author: "Writer")
        let epub = Data("epub-data".utf8)
        try epub.write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }
        context.insert(work)
        try context.save()

        PreservedWorkService.softDelete(work, in: context)

        #expect(work.isPendingDeletion)
        #expect(work.deletedAt != nil)
        #expect(work.permanentDeletionScheduledAt != nil)
        #expect(FileManager.default.fileExists(atPath: work.fileURL.path))
    }

    @Test func restoreClearsFieldsAndRetractsTombstone() throws {
        let container = try container()
        let context = container.mainContext
        let work = SavedWork(title: "Restorable Work", author: "Writer")
        context.insert(work)
        try context.save()

        PreservedWorkService.softDelete(work, in: context)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).contains { $0.recordID == work.id })

        PreservedWorkService.restore(work, in: context)

        #expect(!work.isPendingDeletion)
        #expect(work.deletedAt == nil)
        #expect(work.permanentDeletionScheduledAt == nil)
        #expect(!(try context.fetch(FetchDescriptor<SyncTombstone>()).contains { $0.recordID == work.id }))
    }

    @Test func softDeletedQueuePreservesMembershipsForRestore() throws {
        let container = try container()
        let context = container.mainContext
        let work = try insertWork(into: context, title: "Queued Work", ao3WorkID: 9001)
        let queue = ReadingQueue(name: "Weekend Reads")
        let membership = ReadingQueueMembership(queue: queue, work: work)
        context.insert(queue)
        context.insert(membership)
        queue.memberships.append(membership)
        work.queueMemberships.append(membership)
        work.isQueuedForLater = true
        try context.save()

        PreservedWorkService.softDelete(queue, in: context)

        #expect(queue.isPendingDeletion)
        #expect(queue.memberships.count == 1)
        #expect(work.isQueuedForLater)

        PreservedWorkService.restore(queue, in: context)

        #expect(!queue.isPendingDeletion)
        #expect(queue.memberships.count == 1)
        #expect(queue.memberships.first?.work?.id == work.id)
    }

    @Test func sweepExpiredOnlyTouchesRecordsPastTheirSchedule() throws {
        let container = try container()
        let context = container.mainContext
        let expiredWork = SavedWork(title: "Long Gone", author: "Writer")
        let pendingWork = SavedWork(title: "Still Pending", author: "Writer")
        context.insert(expiredWork)
        context.insert(pendingWork)
        try context.save()

        PreservedWorkService.softDelete(expiredWork, in: context)
        expiredWork.permanentDeletionScheduledAt = Date(timeIntervalSinceNow: -1)
        PreservedWorkService.softDelete(pendingWork, in: context)
        try context.save()

        let removed = PreservedWorkService.sweepExpired(in: context)

        #expect(removed == 1)
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).map(\.title) == ["Still Pending"])
    }

    @Test func sweepExpiredIsANoOpWhileTheOperationGateIsHeld() throws {
        let container = try container()
        let context = container.mainContext
        let expiredWork = SavedWork(title: "Long Gone", author: "Writer")
        context.insert(expiredWork)
        try context.save()
        PreservedWorkService.softDelete(expiredWork, in: context)
        expiredWork.permanentDeletionScheduledAt = Date(timeIntervalSinceNow: -1)
        try context.save()

        #expect(PersistenceOperationGate.begin(.migration))
        defer { PersistenceOperationGate.end(.migration) }

        let removed = PreservedWorkService.sweepExpired(in: context)

        #expect(removed == 0)
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).count == 1)
    }

    @Test func sweepExpiredHardDeletingAQueueTombstonesMembershipsAndUpdatesWork() throws {
        let container = try container()
        let context = container.mainContext
        let work = try insertWork(into: context, title: "Queued Work", ao3WorkID: 9002)
        let queue = ReadingQueue(name: "Weekend Reads")
        let membership = ReadingQueueMembership(queue: queue, work: work)
        context.insert(queue)
        context.insert(membership)
        queue.memberships.append(membership)
        work.queueMemberships.append(membership)
        work.isQueuedForLater = true
        try context.save()

        PreservedWorkService.softDelete(queue, in: context)
        queue.permanentDeletionScheduledAt = Date(timeIntervalSinceNow: -1)
        try context.save()

        let removed = PreservedWorkService.sweepExpired(in: context)

        #expect(removed == 1)
        #expect(try context.fetch(FetchDescriptor<ReadingQueue>()).isEmpty)
        #expect(!work.isQueuedForLater)
        #expect(work.queueMemberships.isEmpty)
        #expect(
            try context.fetch(FetchDescriptor<SyncTombstone>())
                .contains { $0.recordID == membership.id && $0.recordType == .readingQueueMembership }
        )
    }

    @Test func deleteConfirmationMessageEscalatesWhenAO3Unavailable() {
        let available = SavedWork(title: "Available Work", author: "Writer")
        let unavailable = SavedWork(title: "Gone Work", author: "Writer")
        unavailable.ao3Unavailable = true

        #expect(PreservedWorkService.deleteConfirmationMessage(for: available).contains("Recently Deleted"))
        #expect(PreservedWorkService.deleteConfirmationMessage(for: unavailable).contains("no longer available"))
    }

    @Test func manifestV7RoundTripsPermanentDeletionScheduledAt() throws {
        let container = try container()
        let context = container.mainContext
        let work = try insertWork(into: context, title: "Archived Work", ao3WorkID: 9003)
        PreservedWorkService.softDelete(work, in: context)
        let scheduledAt = try #require(work.permanentDeletionScheduledAt)

        let document = try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )

        #expect(document.contents.manifest.version == KudosBackupManifest.currentVersion)
        let archivedWork = try #require(document.contents.manifest.works.first)
        #expect(archivedWork.permanentDeletionScheduledAt == scheduledAt)
    }

    @Test func incomingWinsGatesPermanentDeletionScheduledAtMerge() throws {
        let defaults = try testDefaults()
        let container = try container()
        let context = container.mainContext
        let work = try insertWork(into: context, title: "Restored Elsewhere", ao3WorkID: 9004)
        PreservedWorkService.softDelete(work, in: context)
        work.markModified(Date(timeIntervalSince1970: 1000))
        try context.save()

        // A stale archive still shows the old soft-delete state.
        let staleDocument = try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )

        // This device already restored the work — newer than the stale snapshot.
        PreservedWorkService.restore(work, in: context)
        work.markModified(Date(timeIntervalSince1970: 2000))
        try context.save()

        _ = try KudosBackupService.restore(staleDocument.contents, into: context, defaults: defaults)

        let restored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(!restored.isPendingDeletion)
        #expect(restored.permanentDeletionScheduledAt == nil)
    }

    @Test func twoDeviceConvergenceThroughSoftDeleteAndRestore() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let deviceAContainer = try container()
        let deviceAContext = deviceAContainer.mainContext
        let deviceADefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: deviceADefaults) }
        let work = try insertWork(into: deviceAContext, title: "Shared Work", ao3WorkID: 9005)
        try FolderSyncService.connect(to: folder, defaults: deviceADefaults)
        _ = try await FolderSyncService.syncUp(in: deviceAContext, defaults: deviceADefaults)

        let deviceBContainer = try container()
        let deviceBContext = deviceBContainer.mainContext
        let deviceBDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: deviceBDefaults) }
        try FolderSyncService.connect(to: folder, defaults: deviceBDefaults)
        _ = try await FolderSyncService.syncDown(in: deviceBContext, defaults: deviceBDefaults)

        // Device A soft-deletes and syncs up.
        PreservedWorkService.softDelete(work, in: deviceAContext)
        _ = try await FolderSyncService.syncUp(in: deviceAContext, defaults: deviceADefaults)

        // Device B syncs down: the work is in Recently Deleted, not gone.
        _ = try await FolderSyncService.syncDown(in: deviceBContext, defaults: deviceBDefaults)
        let deviceBWork = try #require(try deviceBContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(deviceBWork.isPendingDeletion)
        #expect(deviceBWork.permanentDeletionScheduledAt != nil)

        // Device B restores and syncs up.
        PreservedWorkService.restore(deviceBWork, in: deviceBContext)
        _ = try await FolderSyncService.syncUp(in: deviceBContext, defaults: deviceBDefaults)

        // Device A syncs down: the work is back in the normal Library.
        _ = try await FolderSyncService.syncDown(in: deviceAContext, defaults: deviceADefaults)
        let deviceAWork = try #require(try deviceAContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(!deviceAWork.isPendingDeletion)
        #expect(deviceAWork.permanentDeletionScheduledAt == nil)
    }

    private func container() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreservedWorkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "PreservedWorkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @discardableResult
    private func insertWork(
        into context: ModelContext,
        title: String,
        ao3WorkID: Int
    ) throws -> SavedWork {
        let work = SavedWork(
            title: title,
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/\(ao3WorkID)"
        )
        work.ao3WorkID = ao3WorkID
        work.markModified(Date(timeIntervalSince1970: TimeInterval(ao3WorkID)))
        context.insert(work)
        try context.save()
        return work
    }
}
