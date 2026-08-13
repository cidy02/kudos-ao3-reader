import Foundation
import SwiftData
import Testing
@testable import Kudos

// Nested under PersistenceGateSuites (see its doc comment): every sync call here
// takes PersistenceOperationGate, a process-wide static lock, so this suite must
// serialize against the other gate-taking suites too, not just within itself.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct FolderSyncTests {
    @Test func syncUpWritesReadableSyncDirectory() async throws {
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

        // The live payload is a plain directory (manifest + per-asset files),
        // not an archive — that's what lets iCloud sync per-file deltas. Its
        // layout matches the legacy package's, so the shared reader can verify it.
        let syncDirectoryURL = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: syncDirectoryURL.path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
        let contents = try KudosBackupContents.read(from: syncDirectoryURL)
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

    /// `foldFileProviderConflicts` (the private, `performSyncDown`-only path) folds its
    /// own `FolderSyncResult` into the caller's via this overload rather than discarding
    /// it — regression coverage for the undercount §6.3 of the ponytail audit found:
    /// conflict-restore counts must reach the totals `SettingsView` displays, not just
    /// the raw folded-version count.
    @Test func folderSyncResultAbsorbsAnotherResultsCountsRatherThanDiscardingThem() {
        var total = FolderSyncResult()
        total.restoredWorks = 1
        total.suppressedQueues = 1

        var conflictFold = FolderSyncResult()
        conflictFold.restoredWorks = 2
        conflictFold.suppressedQueues = 3
        conflictFold.revivedQueues = 1
        conflictFold.ambiguousQueueConflicts = 1
        conflictFold.foldedConflicts = 2

        total.absorb(conflictFold)

        #expect(total.restoredWorks == 3)
        #expect(total.suppressedQueues == 4)
        #expect(total.revivedQueues == 1)
        #expect(total.ambiguousQueueConflicts == 1)
        #expect(total.foldedConflicts == 2)
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
        let staleContents = try KudosBackupService.makeContents(
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

        _ = try KudosBackupService.restore(staleContents, into: context, defaults: defaults)

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
        let newerContents = try KudosBackupService.makeContents(
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

        _ = try KudosBackupService.restore(newerContents, into: context, defaults: defaults)

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
        let staleContents = try KudosBackupService.makeContents(
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

        let summary = try KudosBackupService.restore(staleContents, into: context, defaults: defaults)

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

    /// A failed sync-up write must never destroy the existing remote manifest — the
    /// previous copy is the only cloud copy, so other devices must still be able to
    /// restore from it.
    @Test func failedSyncUpWritePreservesExistingRemoteManifest() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        try insertWork(into: context, title: "Survivor Work", ao3WorkID: 7001)
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        // A read-only sync directory makes the manifest's atomic replacement fail
        // mid-write — exactly the window where a non-atomic writer would have
        // already truncated or removed the previous copy.
        let syncDirectoryURL = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: syncDirectoryURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: syncDirectoryURL.path
            )
        }

        try insertWork(into: context, title: "Doomed Update", ao3WorkID: 7002)
        await #expect(throws: (any Error).self) {
            _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        }

        let contents = try KudosBackupContents.read(from: syncDirectoryURL)
        #expect(contents.manifest.works.count == 1)
        #expect(contents.manifest.works.first?.title == "Survivor Work")
    }

    /// Migration: a folder that still holds the pre-archive
    /// `KudosLibrary.kudosbackup` directory package is folded read-only — its
    /// data arrives, the new plain-directory layout is written alongside, and
    /// the legacy package itself is never modified or deleted, so an
    /// old-version device (or an interrupted migration) can still rely on it.
    @Test func legacySyncPackageIsFoldedReadOnlyAndLeftUntouched() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Build the legacy on-disk shape by hand — production code no longer writes it.
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(into: sourceContext, title: "Legacy Survivor", ao3WorkID: 8001)
        let legacyContents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let legacyManifestData = try legacyContents.manifestData()
        let legacyURL = folder.appendingPathComponent(FolderSyncService.legacySyncFileName)
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: legacyManifestData),
            "Works": FileWrapper(directoryWithFileWrappers: [:]),
            "Fonts": FileWrapper(directoryWithFileWrappers: [:])
        ])
        try wrapper.write(to: legacyURL, options: .atomic, originalContentsURL: nil)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let first = try await FolderSyncService.syncNow(in: targetContext, defaults: targetDefaults)
        #expect(first.restoredWorks == 1)
        #expect(first.didReadRemoteFile)
        #expect(first.missingRemoteFile == false)

        // The new layout now exists; the legacy package is byte-identical.
        let newManifestURL = folder
            .appendingPathComponent(FolderSyncService.syncDirectoryName)
            .appendingPathComponent(FolderSyncService.manifestFileName)
        #expect(FileManager.default.fileExists(atPath: newManifestURL.path))
        let legacyManifestAfter = try Data(
            contentsOf: legacyURL.appendingPathComponent("manifest.json")
        )
        #expect(legacyManifestAfter == legacyManifestData)

        // Idempotent: a repeat sync neither duplicates records nor re-reads.
        let second = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(second.skippedUnchanged)
        #expect(try targetContext.fetch(FetchDescriptor<SavedWork>()).count == 1)
    }

    /// The point of the plain-directory payload: an unchanged EPUB is not
    /// rewritten by later sync-ups, so iCloud Drive never re-uploads it.
    @Test func syncUpLeavesUnchangedEPUBFilesAlone() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        let work = try insertWork(into: context, title: "Stable EPUB", ao3WorkID: 9001)
        work.hasEPUB = true
        let epub = try Data(contentsOf: EPUBTests.sampleEPUB)
        try epub.write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }
        try context.save()

        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        let remoteEPUBURL = folder
            .appendingPathComponent(FolderSyncService.syncDirectoryName)
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
            .appendingPathComponent("\(work.id.uuidString).epub")
        #expect(FileManager.default.fileExists(atPath: remoteEPUBURL.path))
        // Backdate the remote copy so any rewrite is detectable.
        let sentinelDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: sentinelDate],
            ofItemAtPath: remoteEPUBURL.path
        )

        try insertWork(into: context, title: "Unrelated Addition", ao3WorkID: 9002)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        let modified = try #require(
            try FileManager.default.attributesOfItem(atPath: remoteEPUBURL.path)[.modificationDate]
                as? Date
        )
        #expect(modified == sentinelDate)
    }

    /// Orphaned asset files (no manifest record references them anymore) are
    /// removed after the manifest commit; a remote EPUB whose work is still in
    /// the manifest survives even when this device holds no local copy, and
    /// unrelated hidden files are left alone.
    @Test func syncUpRemovesOrphanedAssetsButKeepsManifestReferencedOnes() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        let work = try insertWork(into: context, title: "Referenced Work", ao3WorkID: 9101)
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        let worksDirectory = folder
            .appendingPathComponent(FolderSyncService.syncDirectoryName)
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
        let orphanURL = worksDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        try Data("orphan".utf8).write(to: orphanURL)
        // Another device preserved this work's EPUB; this device has no local copy.
        let keptURL = worksDirectory.appendingPathComponent("\(work.id.uuidString).epub")
        try Data("kept-remote-epub".utf8).write(to: keptURL)
        let hiddenURL = worksDirectory.appendingPathComponent(".DS_Store")
        try Data("hidden".utf8).write(to: hiddenURL)

        FolderSyncService.markDirty(defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(FileManager.default.fileExists(atPath: keptURL.path))
        #expect(FileManager.default.fileExists(atPath: hiddenURL.path))
    }

    /// A manifest can sync down while an EPUB is still an undownloaded iCloud
    /// placeholder. The work must still restore (without the EPUB), the skip
    /// stamp must stay withheld, and the EPUB must be fetched by a later sync
    /// even though the manifest never changes again.
    @Test func syncDownRetriesManifestReferencedEPUBOnceItAppears() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Remote state by hand: a manifest listing an EPUB-bearing work, but no
        // EPUB file uploaded yet.
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(into: sourceContext, title: "Late EPUB", ao3WorkID: 9201)
        work.hasEPUB = true
        try sourceContext.save()
        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let syncDirectoryURL = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let worksDirectory = syncDirectoryURL
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
        try FileManager.default.createDirectory(
            at: worksDirectory,
            withIntermediateDirectories: true
        )
        try contents.manifestData().write(
            to: syncDirectoryURL.appendingPathComponent(FolderSyncService.manifestFileName),
            options: .atomic
        )
        // The EPUB itself is still only an iCloud placeholder — present in the
        // listing, contents not yet downloaded.
        let placeholderURL = worksDirectory
            .appendingPathComponent(".\(work.id.uuidString).epub.icloud")
        try Data().write(to: placeholderURL)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let first = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        defer { try? FileManager.default.removeItem(at: restored.fileURL) }
        #expect(first.didReadRemoteFile)
        #expect(restored.hasEPUB == false)

        // The EPUB materializes later, with no manifest change at all.
        let epub = try Data(contentsOf: EPUBTests.sampleEPUB)
        try epub.write(to: worksDirectory.appendingPathComponent("\(work.id.uuidString).epub"))
        try FileManager.default.removeItem(at: placeholderURL)

        let second = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(second.skippedUnchanged == false)
        #expect(second.didReadRemoteFile)
        #expect(restored.hasEPUB)
        #expect(FileManager.default.fileExists(atPath: restored.fileURL.path))

        // Once everything has arrived, the skip stamp finally engages.
        let third = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(third.skippedUnchanged)
    }

    /// A4: a regular sync folder whose EPUB asset is a symlink to a file
    /// outside the folder must not import that file's bytes (M12).
    @Test func syncDownRejectsSymlinkedEPUBAsset() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(into: sourceContext, title: "Symlink Bait", ao3WorkID: 9301)
        work.hasEPUB = true
        try sourceContext.save()
        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let syncDirectoryURL = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let worksDirectory = syncDirectoryURL
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
        try FileManager.default.createDirectory(
            at: worksDirectory,
            withIntermediateDirectories: true
        )
        try contents.manifestData().write(
            to: syncDirectoryURL.appendingPathComponent(FolderSyncService.manifestFileName),
            options: .atomic
        )

        let secretDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: secretDirectory) }
        let secretURL = secretDirectory.appendingPathComponent("secret.epub")
        let secretBytes = Data("SYMLINK-SECRET-SHOULD-NOT-BE-IMPORTED".utf8)
        try secretBytes.write(to: secretURL)
        let remoteEPUB = worksDirectory.appendingPathComponent("\(work.id.uuidString).epub")
        try FileManager.default.createSymbolicLink(at: remoteEPUB, withDestinationURL: secretURL)
        #expect(FolderSyncService.isSymbolicLink(at: remoteEPUB))
        #expect(throws: FolderSyncError.symlinkedAsset) {
            try FolderSyncService.readRegularFileData(from: remoteEPUB)
        }
        #expect(try Data(contentsOf: remoteEPUB) == secretBytes)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        _ = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        defer { try? FileManager.default.removeItem(at: restored.fileURL) }

        #expect(restored.hasEPUB == false)
        if FileManager.default.fileExists(atPath: restored.fileURL.path) {
            let imported = try Data(contentsOf: restored.fileURL)
            #expect(imported != secretBytes)
        }
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
        let manifestURL = folder
            .appendingPathComponent(FolderSyncService.syncDirectoryName)
            .appendingPathComponent(FolderSyncService.manifestFileName)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: manifestURL.path
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
        return try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
    }
}
}
