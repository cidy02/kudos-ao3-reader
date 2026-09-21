import Foundation
import SwiftData
import Testing
@testable import Kudos

/// A device that knows less must not delete what another device uploaded.
///
/// `FolderSyncObserver.scheduleFolderSyncUp` calls `syncUp` **alone**, seven
/// seconds after any local change — there is no sync-down first. So a device
/// still holding an older library publishes a manifest that omits another
/// device's new work, and the orphan prune after the manifest commit deletes
/// that work's remote EPUB. The other device's local copy survives; the backup
/// copy does not, and the folder was the backup.
///
/// Pruning by manifest membership is right — it is how a permanent deletion
/// frees remote bytes — but only when the manifest being published is
/// informed. Pruning is now skipped when this device's view of the folder is
/// stale, which fails by leaving bytes behind rather than by destroying them.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct StaleSyncUpKeepsRemoteAssetsTests {
    private func container() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StaleSyncUpTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "StaleSyncUpKeepsRemoteAssetsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func insertWork(
        into context: ModelContext, title: String, ao3WorkID: Int
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

    @Test func aStaleSyncUpKeepsAnotherDevicesRemoteEPUB() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: defaults) }

        // This device: one work, connected, and up to date with the folder.
        let localContainer = try container()
        let context = localContainer.mainContext
        _ = try insertWork(into: context, title: "Mine", ao3WorkID: 4101)
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        let syncDirectoryURL = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let manifestURL = syncDirectoryURL
            .appendingPathComponent(FolderSyncService.manifestFileName)
        let worksDirectory = syncDirectoryURL
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)

        // Another device publishes a work this one has never heard of, EPUB and
        // all. Its manifest replaces ours, so our stored stamp is now stale.
        let otherContainer = try container()
        let otherContext = otherContainer.mainContext
        let otherWork = try insertWork(into: otherContext, title: "Theirs", ao3WorkID: 4202)
        otherWork.hasEPUB = true
        try otherContext.save()
        let otherContents = try KudosBackupService.makeContents(
            works: [otherWork], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        try otherContents.manifestData().write(to: manifestURL, options: .atomic)

        let theirEPUB = worksDirectory.appendingPathComponent("\(otherWork.id.uuidString).epub")
        try Data("their-only-backup-copy".utf8).write(to: theirEPUB)

        // Pinned rather than left to clock resolution: what matters is only that
        // the remote manifest has moved since we last restored or wrote one.
        let staleStamp = (defaults.object(forKey: "folderSyncLastRestoredRemoteStamp") as? Date)
            ?? Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes(
            [.modificationDate: staleStamp.addingTimeInterval(60)],
            ofItemAtPath: manifestURL.path
        )

        // Our device edits something and the automatic uploader fires.
        FolderSyncService.markDirty(defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        // Our manifest does not list their work — but their backup copy stays.
        #expect(FileManager.default.fileExists(atPath: theirEPUB.path))
        #expect(try Data(contentsOf: theirEPUB) == Data("their-only-backup-copy".utf8))
    }
}
}
