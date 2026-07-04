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

    @Test func migrationIsIdempotentAndMarksMissingEPUBRecoverable() throws {
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

        #expect(PersistenceMigrationService.run(in: context, defaults: defaults) == .completed)
        let firstAssetIdentifier = work.assetIdentifier
        #expect(firstAssetIdentifier == "00000000-0000-0000-0000-000000000111.epub")
        #expect(work.ao3WorkID == 111)
        #expect(work.hasEPUB == false)
        #expect(work.epubPreservationStatus == .missingFile)
        #expect(work.syncStatus == .assetsMissing)

        #expect(PersistenceMigrationService.runIfNeeded(in: context, defaults: defaults) == .completed)
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

    private func testDefaults() throws -> UserDefaults {
        let name = "PersistenceSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
