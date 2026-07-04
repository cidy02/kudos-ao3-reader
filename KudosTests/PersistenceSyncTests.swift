import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct PersistenceSyncTests {
    private func container() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test func migrationIsIdempotentAndMarksMissingEPUBRecoverable() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let work = SavedWork(id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
                             title: "Missing File",
                             author: "Writer",
                             sourceURL: "https://archiveofourown.org/works/111")
        work.assetIdentifier = ""
        work.hasEPUB = true
        work.epubPreservationStatus = .preserved
        context.insert(work)

        let firstRun = await PersistenceMigrationService.run(in: context, defaults: defaults)
        #expect(firstRun == .completed)
        let firstAssetIdentifier = work.assetIdentifier
        #expect(firstAssetIdentifier == "00000000-0000-0000-0000-000000000111.epub")
        #expect(work.ao3WorkID == 111)
        #expect(work.hasEPUB == false)
        #expect(work.epubPreservationStatus == .missingFile)
        #expect(work.syncStatus == .assetsMissing)

        let secondRun = await PersistenceMigrationService.runIfNeeded(in: context, defaults: defaults)
        #expect(secondRun == .completed)
        #expect(work.assetIdentifier == firstAssetIdentifier)
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).count == 1)
    }

    @Test func progressMergeDoesNotRegressToOlderSnapshot() throws {
        let work = SavedWork(title: "Progress", author: "Writer")
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        work.lastSpineIndex = 4
        work.lastScrollFraction = 0.8
        work.markProgressModified(newDate)

        SyncMerge.applyProgress(
            SyncMerge.ProgressSnapshot(
                lastSpineIndex: 1,
                lastScrollFraction: 0.1,
                readiumLocator: "",
                lastReadDate: oldDate,
                modifiedAt: oldDate
            ),
            to: work
        )
        #expect(work.lastSpineIndex == 4)
        #expect(work.lastScrollFraction == 0.8)

        SyncMerge.applyProgress(
            SyncMerge.ProgressSnapshot(
                lastSpineIndex: 6,
                lastScrollFraction: 0.95,
                readiumLocator: "{\"locations\":{\"totalProgression\":0.95}}",
                lastReadDate: newDate.addingTimeInterval(10),
                modifiedAt: newDate.addingTimeInterval(10)
            ),
            to: work
        )
        #expect(work.lastSpineIndex == 6)
        #expect(work.lastScrollFraction == 0.95)
    }

    @Test func backupRestoreKeepsNewerLocalProgress() throws {
        let defaults = try testDefaults()
        let archived = SavedWork(title: "Shared Work",
                                 author: "Writer",
                                 sourceURL: "https://archiveofourown.org/works/222")
        archived.ao3WorkID = 222
        archived.lastSpineIndex = 1
        archived.lastScrollFraction = 0.2
        archived.markProgressModified(Date(timeIntervalSince1970: 100))
        let document = try KudosBackupService.makeDocument(
            works: [archived],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )

        let container = try container()
        let context = container.mainContext
        let local = SavedWork(title: "Shared Work",
                              author: "Writer",
                              sourceURL: "https://archiveofourown.org/works/222")
        local.ao3WorkID = 222
        local.lastSpineIndex = 5
        local.lastScrollFraction = 0.9
        local.markProgressModified(Date(timeIntervalSince1970: 200))
        context.insert(local)

        _ = try KudosBackupService.restore(document.contents, into: context, defaults: defaults)

        let restored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.lastSpineIndex == 5)
        #expect(restored.lastScrollFraction == 0.9)
    }

    @Test func queueOrderingFallsBackDeterministically() throws {
        let container = try container()
        let context = container.mainContext
        let queue = ReadingQueue(name: "Queue")
        let first = SavedWork(title: "A", author: "Writer")
        let second = SavedWork(title: "B", author: "Writer")
        let early = ReadingQueueMembership(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            queue: queue,
            work: first,
            queuedAt: Date(timeIntervalSince1970: 100),
            sortOrderInQueue: 0
        )
        let late = ReadingQueueMembership(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            queue: queue,
            work: second,
            queuedAt: Date(timeIntervalSince1970: 200),
            sortOrderInQueue: 0
        )
        context.insert(queue)
        context.insert(first)
        context.insert(second)
        context.insert(late)
        context.insert(early)

        #expect(SyncMerge.deterministicMembershipOrder([late, early]).map(\.id) == [early.id, late.id])
    }

    @Test func deletingWorkCreatesTombstone() throws {
        let container = try container()
        let context = container.mainContext
        let work = SavedWork(title: "Deleted", author: "Writer", sourceURL: "https://archiveofourown.org/works/333")
        context.insert(work)

        WorkLifecycle.delete(work, in: context)

        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(tombstones.count == 1)
        #expect(tombstones.first?.recordType == .savedWork)
        #expect(tombstones.first?.ao3WorkID == 333)
    }

    @Test func deletingWorkThenImportingOlderBackupDoesNotResurrectIt() throws {
        let defaults = try testDefaults()
        let container = try container()
        let context = container.mainContext

        let work = SavedWork(title: "Deleted Work", author: "Writer",
                             sourceURL: "https://archiveofourown.org/works/444")
        context.insert(work)
        WorkLifecycle.delete(work, in: context)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).count == 1)

        // An older snapshot of the same work, from before it was deleted.
        let archived = SavedWork(title: "Deleted Work", author: "Writer",
                                 sourceURL: "https://archiveofourown.org/works/444")
        archived.ao3WorkID = 444
        archived.markModified(Date(timeIntervalSince1970: 100))
        let document = try KudosBackupService.makeDocument(
            works: [archived],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )

        _ = try KudosBackupService.restore(document.contents, into: context, defaults: defaults)

        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
    }

    @Test func backupImportDoesNotResurrectExplicitlyUnfavoritedWork() throws {
        let defaults = try testDefaults()
        let container = try container()
        let context = container.mainContext

        let local = SavedWork(title: "Shared Work", author: "Writer",
                              sourceURL: "https://archiveofourown.org/works/555")
        local.ao3WorkID = 555
        local.isFavorite = true
        local.markModified(Date(timeIntervalSince1970: 100))
        context.insert(local)

        // Backup captured while the work was still favorited...
        let archived = SavedWork(title: "Shared Work", author: "Writer",
                                 sourceURL: "https://archiveofourown.org/works/555")
        archived.ao3WorkID = 555
        archived.isFavorite = true
        archived.markModified(Date(timeIntervalSince1970: 100))
        let document = try KudosBackupService.makeDocument(
            works: [archived],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )

        // ...but the user unfavorited it locally afterward, making local strictly newer.
        local.isFavorite = false
        local.markModified(Date(timeIntervalSince1970: 200))

        _ = try KudosBackupService.restore(document.contents, into: context, defaults: defaults)

        let restored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.isFavorite == false)
    }

    /// A fresh install (or any restore into a database with no matching local record) has
    /// no prior state to protect — the archived flags must come through untouched, even
    /// though a freshly-created placeholder's own lastModifiedAt is "now" and so would
    /// otherwise always look newer than the archive.
    @Test func freshInstallRestoreAdoptsArchivedFlagsWithNoExistingLocalRecord() throws {
        let defaults = try testDefaults()
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext

        let archived = SavedWork(title: "Brand New To This Device", author: "Writer",
                                 sourceURL: "https://archiveofourown.org/works/666")
        archived.ao3WorkID = 666
        archived.isFavorite = true
        archived.isSaved = true
        archived.isFinished = true
        archived.isComplete = true
        archived.markModified(Date(timeIntervalSince1970: 100))
        sourceContext.insert(archived)
        let document = try KudosBackupService.makeDocument(
            works: [archived],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext

        _ = try KudosBackupService.restore(document.contents, into: targetContext, defaults: defaults)

        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.isFavorite == true)
        #expect(restored.isSaved == true)
        #expect(restored.isFinished == true)
        #expect(restored.isComplete == true)
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "PersistenceSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
