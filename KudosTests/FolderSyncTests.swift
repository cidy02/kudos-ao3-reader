import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct FolderSyncTests {
    @Test func syncUpWritesReadableBackupPackage() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        let work = SavedWork(
            title: "Folder Sync Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/1001"
        )
        work.ao3WorkID = 1001
        work.isFavorite = true
        context.insert(work)
        try context.save()

        try FolderSyncService.connect(to: folder, defaults: defaults)
        let result = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        let syncFileURL = folder.appendingPathComponent(FolderSyncService.syncFileName)
        let contents = try KudosBackupContents.read(from: syncFileURL)
        #expect(result.didWriteRemoteFile)
        #expect(contents.manifest.works.count == 1)
        #expect(contents.manifest.works.first?.title == "Folder Sync Work")
        #expect(contents.manifest.works.first?.isFavorite == true)
        #expect(FolderSyncService.snapshot(defaults: defaults).lastSyncAt != nil)
    }

    @Test func syncDownRestoresWorkQueueAndCollection() async throws {
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let sourceDefaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: sourceDefaults) }

        let seed = try insertLibraryFixture(into: sourceContext)
        try FolderSyncService.connect(to: folder, defaults: sourceDefaults)
        _ = try await FolderSyncService.syncUp(in: sourceContext, defaults: sourceDefaults)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let result = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)

        let restoredWork = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        let restoredQueue = try #require(try targetContext.fetch(FetchDescriptor<ReadingQueue>())
            .first { $0.id == seed.queueID })
        let restoredCollection = try #require(try targetContext.fetch(FetchDescriptor<WorkCollection>())
            .first { $0.id == seed.collectionID })

        #expect(result.didReadRemoteFile)
        #expect(result.restoredWorks == 1)
        #expect(restoredWork.id == seed.workID)
        #expect(restoredQueue.name == "Weekend Reads")
        #expect(restoredQueue.memberships.count == 1)
        #expect(restoredCollection.name == "Comfort Shelf")
        #expect(restoredCollection.works.map(\.id) == [seed.workID])
    }

    @Test func syncUpThenSyncDownConvergesWithoutDuplicates() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let firstContainer = try container()
        let firstContext = firstContainer.mainContext
        let firstDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: firstDefaults) }
        try insertWork(into: firstContext, title: "Device A Work", ao3WorkID: 2001)
        try FolderSyncService.connect(to: folder, defaults: firstDefaults)
        _ = try await FolderSyncService.syncUp(in: firstContext, defaults: firstDefaults)

        let secondContainer = try container()
        let secondContext = secondContainer.mainContext
        let secondDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: secondDefaults) }
        try FolderSyncService.connect(to: folder, defaults: secondDefaults)
        _ = try await FolderSyncService.syncDown(in: secondContext, defaults: secondDefaults)
        try insertWork(into: secondContext, title: "Device B Work", ao3WorkID: 2002)
        _ = try await FolderSyncService.syncNow(in: secondContext, defaults: secondDefaults)

        _ = try await FolderSyncService.syncDown(in: firstContext, defaults: firstDefaults)

        let firstWorks = try firstContext.fetch(FetchDescriptor<SavedWork>())
        let secondWorks = try secondContext.fetch(FetchDescriptor<SavedWork>())
        #expect(firstWorks.count == 2)
        #expect(secondWorks.count == 2)
        #expect(Set(firstWorks.compactMap(\.ao3WorkID)) == [2001, 2002])
        #expect(Set(secondWorks.compactMap(\.ao3WorkID)) == [2001, 2002])
    }

    @Test func syncDownMissingFileIsNoop() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        try FolderSyncService.connect(to: folder, defaults: defaults)
        let result = try await FolderSyncService.syncDown(in: context, defaults: defaults)

        #expect(result.missingRemoteFile)
        #expect(result.didReadRemoteFile == false)
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
    }

    @Test func operationGatePreventsInterleavedFolderSync() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        try FolderSyncService.connect(to: folder, defaults: defaults)
        #expect(PersistenceOperationGate.begin(.backupImport))
        defer { PersistenceOperationGate.end(.backupImport) }

        do {
            _ = try await FolderSyncService.syncNow(in: context, defaults: defaults)
            Issue.record("Expected folder sync to respect the active backup import gate.")
        } catch let error as FolderSyncError {
            #expect(error == .operationInProgress(PersistenceOperationKind.backupImport.title))
        }
    }

    @Test func foldConflictContentsMergesAllInputs() throws {
        let defaults = try testDefaults()
        let first = try backupContents(title: "Conflict A", ao3WorkID: 3001)
        let second = try backupContents(title: "Conflict B", ao3WorkID: 3002)
        let targetContainer = try container()
        let targetContext = targetContainer.mainContext

        let result = try FolderSyncService.foldConflictContents([first, second], into: targetContext, defaults: defaults)

        let works = try targetContext.fetch(FetchDescriptor<SavedWork>())
        #expect(result.foldedConflicts == 2)
        #expect(result.restoredWorks == 2)
        #expect(Set(works.compactMap(\.ao3WorkID)) == [3001, 3002])
    }

    @Test func syncUpDoesNotChangeLocalModificationDates() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        let modifiedAt = Date(timeIntervalSince1970: 400)
        let work = SavedWork(title: "Stable Work", author: "Writer")
        work.markModified(modifiedAt)
        let collection = WorkCollection(name: "Stable Shelf")
        collection.markModified(modifiedAt)
        context.insert(work)
        context.insert(collection)
        try context.save()

        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        #expect(work.lastModifiedAt == modifiedAt)
        #expect(collection.lastModifiedAt == modifiedAt)
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
            .appendingPathComponent("FolderSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "FolderSyncTests.\(UUID().uuidString)"
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

    private func insertLibraryFixture(into context: ModelContext) throws -> (
        workID: UUID,
        queueID: UUID,
        collectionID: UUID
    ) {
        let work = try insertWork(into: context, title: "Synced Fixture", ao3WorkID: 4001)
        let queue = ReadingQueue(
            name: "Weekend Reads",
            dateCreated: Date(timeIntervalSince1970: 100),
            dateUpdated: Date(timeIntervalSince1970: 100)
        )
        let membership = ReadingQueueMembership(
            queue: queue,
            work: work,
            queuedAt: Date(timeIntervalSince1970: 101),
            sortOrderInQueue: 0
        )
        let collection = WorkCollection(name: "Comfort Shelf")
        collection.works.append(work)
        work.collections.append(collection)
        context.insert(queue)
        context.insert(membership)
        context.insert(collection)
        queue.memberships.append(membership)
        work.queueMemberships.append(membership)
        try context.save()
        return (work.id, queue.id, collection.id)
    }

    private func backupContents(title: String, ao3WorkID: Int) throws -> KudosBackupContents {
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(into: sourceContext, title: title, ao3WorkID: ao3WorkID)
        return try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        ).contents
    }
}
