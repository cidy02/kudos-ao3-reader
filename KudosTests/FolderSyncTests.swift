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

    /// A5-F3: folder sync's restore path is the same `KudosBackupService.restore`
    /// used by manual backup import, so a corrupt synced EPUB must be rejected the
    /// same way — never overwriting a valid local copy.
    @Test func syncDownRejectsInvalidEPUBWithoutOverwritingLocalCopy() async throws {
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let sourceDefaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: sourceDefaults) }

        let workID = UUID()
        let sourceWork = SavedWork(id: workID, title: "Corrupt Sync Work", author: "Writer")
        sourceWork.hasEPUB = true
        sourceContext.insert(sourceWork)
        try Data("not-an-epub".utf8).write(to: sourceWork.fileURL)
        try sourceContext.save()
        defer { try? FileManager.default.removeItem(at: sourceWork.fileURL) }

        try FolderSyncService.connect(to: folder, defaults: sourceDefaults)
        _ = try await FolderSyncService.syncUp(in: sourceContext, defaults: sourceDefaults)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let targetWork = SavedWork(id: workID, title: "Corrupt Sync Work", author: "Writer")
        targetWork.hasEPUB = true
        targetContext.insert(targetWork)
        let validEPUB = try Data(contentsOf: EPUBTests.sampleEPUB)
        try validEPUB.write(to: targetWork.fileURL)
        try targetContext.save()
        defer { try? FileManager.default.removeItem(at: targetWork.fileURL) }

        _ = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)

        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.hasEPUB)
        #expect(try Data(contentsOf: restored.fileURL) == validEPUB)
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
        // A gate-rejected attempt must still be visible, not silently dropped, since it
        // isn't a "real" failure like a bad bookmark or a read error.
        #expect(!FolderSyncService.snapshot(defaults: defaults).lastError.isEmpty)
    }

    @Test func dirtyFlagOnlyClearsAfterAnActualWrite() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        try FolderSyncService.connect(to: folder, defaults: defaults)
        FolderSyncService.markDirty(defaults: defaults)
        #expect(FolderSyncService.snapshot(defaults: defaults).isDirty)

        // A pure sync-down (nothing to read yet) must not clear it — dirty means "local
        // changes not yet written out", and no write happened.
        _ = try await FolderSyncService.syncDown(in: context, defaults: defaults)
        #expect(FolderSyncService.snapshot(defaults: defaults).isDirty)

        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        #expect(FolderSyncService.snapshot(defaults: defaults).isDirty == false)
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

    /// A work explicitly removed from a collection must not be silently re-added by a
    /// stale sync file that still lists it — the same resurrection bug class fixed for
    /// deleted works/queues, now closed for collection membership too.
    @Test func removedCollectionMembershipIsNotResurrectedByStaleSync() async throws {
        let defaults = try testDefaults()
        let container = try container()
        let context = container.mainContext

        let work = try insertWork(into: context, title: "Shelved Work", ao3WorkID: 5001)
        let collection = WorkCollection(name: "Comfort Shelf")
        collection.id = UUID(uuidString: "00000000-0000-0000-0000-0000000C0111")!
        collection.markModified(Date(timeIntervalSince1970: 100))
        collection.works.append(work)
        work.collections.append(collection)
        context.insert(collection)
        try context.save()

        // The stale manifest: a snapshot from before the removal, still listing the work.
        let staleDocument = try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [],
            fonts: [],
            collections: [collection],
            readingQueues: [],
            defaults: defaults
        )

        // The user removes the work from the collection at t=150 — after the stale
        // manifest's t=100, so that snapshot must not resurrect it. Constructed directly
        // (rather than via the real-"now"-stamping helper) for a meaningful boundary
        // comparison rather than "any real date dwarfs a synthetic epoch timestamp".
        context.insert(SyncTombstone(
            recordID: SyncTombstone.collectionMembershipID(collectionID: collection.id, workID: work.id),
            recordType: .workCollectionMembership,
            createdAt: Date(timeIntervalSince1970: 150)
        ))
        collection.works.removeAll { $0.id == work.id }
        work.collections.removeAll { $0.id == collection.id }
        collection.markModified(Date(timeIntervalSince1970: 200))
        try context.save()

        _ = try KudosBackupService.restore(staleDocument.contents, into: context, defaults: defaults)

        let restored = try #require(try context.fetch(FetchDescriptor<WorkCollection>()).first)
        #expect(restored.works.isEmpty)
    }

    /// A collection snapshot demonstrably newer than the removal (e.g. the work was
    /// re-added on another device afterward) must still be allowed through.
    @Test func newerCollectionSnapshotRevivesRemovedMembership() async throws {
        let defaults = try testDefaults()
        let container = try container()
        let context = container.mainContext

        let work = try insertWork(into: context, title: "Re-shelved Work", ao3WorkID: 5002)
        let collection = WorkCollection(name: "Comfort Shelf")
        collection.id = UUID(uuidString: "00000000-0000-0000-0000-0000000C0222")!
        collection.markModified(Date(timeIntervalSince1970: 100))
        context.insert(collection)
        try context.save()

        // The user removes the work at t=150 — constructed directly (rather than via
        // SyncTombstones.recordCollectionMembershipRemoval, which stamps real "now") so
        // the timestamp is comparable against the synthetic t=300 archive below.
        context.insert(SyncTombstone(
            recordID: SyncTombstone.collectionMembershipID(collectionID: collection.id, workID: work.id),
            recordType: .workCollectionMembership,
            createdAt: Date(timeIntervalSince1970: 150)
        ))
        try context.save()

        // A newer snapshot (t=300) re-adds the work — newer than the removal, so it wins.
        collection.works.append(work)
        collection.markModified(Date(timeIntervalSince1970: 300))
        let newerDocument = try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [],
            fonts: [],
            collections: [collection],
            readingQueues: [],
            defaults: defaults
        )
        collection.works.removeAll { $0.id == work.id }
        collection.markModified(Date(timeIntervalSince1970: 100))
        try context.save()

        _ = try KudosBackupService.restore(newerDocument.contents, into: context, defaults: defaults)

        let restored = try #require(try context.fetch(FetchDescriptor<WorkCollection>()).first)
        #expect(restored.works.map(\.id) == [work.id])
    }

    /// The queue-conflict path reports suppressed/revived/ambiguous counts to the user;
    /// collections now must too, rather than resolving conflicts invisibly.
    @Test func collectionTombstoneConflictsAreReportedInRestoreSummary() throws {
        let defaults = try testDefaults()

        // Build the stale archived collection in a throwaway source container, mirroring
        // how every other test in this file builds KudosBackup* structs from real models.
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let staleCollection = WorkCollection(name: "Long Gone")
        let suppressedID = UUID(uuidString: "00000000-0000-0000-0000-0000000C0333")!
        staleCollection.id = suppressedID
        staleCollection.markModified(Date(timeIntervalSince1970: 100))
        sourceContext.insert(staleCollection)
        try sourceContext.save()
        let staleDocument = try KudosBackupService.makeDocument(
            works: [],
            bookmarks: [],
            fonts: [],
            collections: [staleCollection],
            readingQueues: [],
            defaults: defaults
        )

        let container = try container()
        let context = container.mainContext
        context.insert(SyncTombstone(
            recordID: suppressedID,
            recordType: .workCollection,
            createdAt: Date(timeIntervalSince1970: 500)
        ))
        try context.save()

        let summary = try KudosBackupService.restore(staleDocument.contents, into: context, defaults: defaults)

        #expect(summary.suppressedCollections == 1)
        #expect(try context.fetch(FetchDescriptor<WorkCollection>()).isEmpty)
        #expect(summary.conflictMessage.contains("previously deleted collection"))
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

    /// A failed sync-up write must never destroy the existing remote package — the
    /// previous copy is the only cloud copy, so other devices must still be able to
    /// restore from it.
    @Test func failedSyncUpWritePreservesExistingRemotePackage() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        try insertWork(into: context, title: "Survivor Work", ao3WorkID: 7001)
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        // A read-only parent makes the swap-into-place step fail after the new package
        // has already been staged — the window where the old copy used to be deleted.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        try insertWork(into: context, title: "Doomed Update", ao3WorkID: 7002)
        await #expect(throws: (any Error).self) {
            _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        }

        let syncFileURL = folder.appendingPathComponent(FolderSyncService.syncFileName)
        let contents = try KudosBackupContents.read(from: syncFileURL)
        #expect(contents.manifest.works.count == 1)
        #expect(contents.manifest.works.first?.title == "Survivor Work")
    }

    @Test func syncDownSkipsUnchangedRemotePackage() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let sourceDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: sourceDefaults) }
        try insertWork(into: sourceContext, title: "Skip Candidate", ao3WorkID: 6001)
        try FolderSyncService.connect(to: folder, defaults: sourceDefaults)
        _ = try await FolderSyncService.syncUp(in: sourceContext, defaults: sourceDefaults)

        // The writing device must not fully re-restore its own just-written file.
        let ownDown = try await FolderSyncService.syncDown(in: sourceContext, defaults: sourceDefaults)
        #expect(ownDown.skippedUnchanged)
        #expect(ownDown.didReadRemoteFile == false)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let first = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(first.didReadRemoteFile)
        #expect(first.skippedUnchanged == false)
        #expect(first.restoredWorks == 1)

        let second = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(second.skippedUnchanged)
        #expect(second.didReadRemoteFile == false)
        #expect(second.restoredWorks == 0)
        #expect(second.foldedConflicts == 0)

        // A genuine remote change makes the next sync-down restore again. The explicit
        // modification-date bump guards against filesystem timestamp granularity.
        try insertWork(into: sourceContext, title: "Second Work", ao3WorkID: 6002)
        _ = try await FolderSyncService.syncUp(in: sourceContext, defaults: sourceDefaults)
        let syncFileURL = folder.appendingPathComponent(FolderSyncService.syncFileName)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: syncFileURL.path
        )

        let third = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(third.skippedUnchanged == false)
        #expect(third.didReadRemoteFile)
        let targetWorks = try targetContext.fetch(FetchDescriptor<SavedWork>())
        #expect(Set(targetWorks.compactMap(\.ao3WorkID)) == [6001, 6002])
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
