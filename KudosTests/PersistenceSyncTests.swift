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

        let works = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(works.count == 1)
        let restored = try #require(works.first)
        #expect(restored.isFavorite == false)
    }

    /// Delete → re-download → delete leaves several tombstones sharing one AO3 identity.
    /// The newest deletion must decide suppression regardless of tombstone fetch order —
    /// here the archived snapshot (t=200) falls between a stale tombstone (t=50) and the
    /// latest deletion (t=300), so it must stay suppressed.
    @Test func newestTombstoneDecidesSuppressionWhenSeveralShareAO3Identity() throws {
        let defaults = try testDefaults()
        let container = try container()
        let context = container.mainContext

        context.insert(SyncTombstone(
            recordID: UUID(),
            recordType: .savedWork,
            sourceURL: "https://archiveofourown.org/works/777",
            ao3WorkID: 777,
            createdAt: Date(timeIntervalSince1970: 300)
        ))
        context.insert(SyncTombstone(
            recordID: UUID(),
            recordType: .savedWork,
            sourceURL: "https://archiveofourown.org/works/777",
            ao3WorkID: 777,
            createdAt: Date(timeIntervalSince1970: 50)
        ))
        try context.save()

        let archived = SavedWork(title: "Twice Deleted", author: "Writer",
                                 sourceURL: "https://archiveofourown.org/works/777")
        archived.ao3WorkID = 777
        archived.markModified(Date(timeIntervalSince1970: 200))
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

    /// A membership whose queue was tombstoned locally must be dropped with the queue —
    /// never silently re-homed into Saved for Later — even when the membership's own
    /// UUID was never seen on this device (second device / shared backup file).
    @Test func suppressedQueueMembershipsAreNotRehomedIntoSavedForLater() throws {
        let defaults = try testDefaults()
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext

        let queueID = UUID(uuidString: "00000000-0000-0000-0000-00000000AAAA")!
        let work = SavedWork(title: "Queued Elsewhere", author: "Writer",
                             sourceURL: "https://archiveofourown.org/works/888")
        work.ao3WorkID = 888
        let queue = ReadingQueue(id: queueID, name: "Deleted Queue", kind: .custom,
                                 sortOrder: 0, dateCreated: Date(timeIntervalSince1970: 100),
                                 dateUpdated: Date(timeIntervalSince1970: 100))
        sourceContext.insert(work)
        sourceContext.insert(queue)
        let membership = ReadingQueueMembership(
            queue: queue,
            work: work,
            queuedAt: Date(timeIntervalSince1970: 100),
            sortOrderInQueue: 0
        )
        sourceContext.insert(membership)
        queue.memberships.append(membership)
        work.queueMemberships.append(membership)
        try sourceContext.save()

        let document = try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [queue],
            defaults: defaults
        )

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        // The user deleted this queue on the target device; the membership's UUID is
        // foreign here (created on the source device), so only the queue is tombstoned.
        targetContext.insert(SyncTombstone(recordID: queueID, recordType: .readingQueue))
        try targetContext.save()

        let summary = try KudosBackupService.restore(document.contents, into: targetContext, defaults: defaults)

        let queues = try targetContext.fetch(FetchDescriptor<ReadingQueue>())
        #expect(queues.allSatisfy { $0.kind == .savedForLater })
        #expect(queues.flatMap(\.memberships).isEmpty)
        let restoredWork = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restoredWork.isQueuedForLater == false)
        #expect(summary.suppressedQueues == 1)
        #expect(summary.suppressedQueueMemberships == 1)
        #expect(summary.revivedQueues == 0)
    }

    @Test func newerMembershipChangeRevivesOlderQueueTombstone() throws {
        let tombstoneDate = Date(timeIntervalSince1970: 100)
        let membershipDate = Date(timeIntervalSince1970: 200)
        let queueID = UUID(uuidString: "00000000-0000-0000-0000-00000000BBBB")!
        let contents = try backupWithQueuedWork(
            queueID: queueID,
            queueName: "Edited Elsewhere",
            queueDateUpdated: Date(timeIntervalSince1970: 50),
            lastMembershipChangedAt: membershipDate,
            membershipModifiedAt: membershipDate,
            exportedAt: Date(timeIntervalSince1970: 50)
        )

        let targetContainer = try container()
        let context = targetContainer.mainContext
        context.insert(SyncTombstone(
            recordID: queueID,
            recordType: .readingQueue,
            createdAt: tombstoneDate
        ))

        let summary = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let queues = try context.fetch(FetchDescriptor<ReadingQueue>())
        let revived = try #require(queues.first { $0.id == queueID })
        #expect(revived.displayName == "Edited Elsewhere")
        #expect(revived.memberships.count == 1)
        #expect(summary.revivedQueues == 1)
        #expect(summary.restoredRevivedQueueMemberships == 1)
        #expect(summary.suppressedQueues == 0)
    }

    @Test func newerQueueMetadataRevivesOlderQueueTombstone() throws {
        let tombstoneDate = Date(timeIntervalSince1970: 100)
        let queueDate = Date(timeIntervalSince1970: 250)
        let queueID = UUID(uuidString: "00000000-0000-0000-0000-00000000CCCC")!
        let contents = try backupWithQueuedWork(
            queueID: queueID,
            queueName: "Renamed Elsewhere",
            queueDateUpdated: queueDate,
            lastMembershipChangedAt: Date(timeIntervalSince1970: 50),
            membershipModifiedAt: Date(timeIntervalSince1970: 50),
            exportedAt: Date(timeIntervalSince1970: 50)
        )

        let targetContainer = try container()
        let context = targetContainer.mainContext
        context.insert(SyncTombstone(
            recordID: queueID,
            recordType: .readingQueue,
            createdAt: tombstoneDate
        ))

        let summary = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let revived = try #require(try context.fetch(FetchDescriptor<ReadingQueue>())
            .first { $0.id == queueID })
        #expect(revived.name == "Renamed Elsewhere")
        #expect(summary.revivedQueues == 1)
        #expect(summary.restoredRevivedQueueMemberships == 1)
    }

    @Test func ambiguousQueueTimestampsPreserveDataForSafety() throws {
        let resolution = SyncMerge.tombstoneResolution(
            incomingModifiedAt: nil,
            tombstoneDeletedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(resolution == .preserveAmbiguous)
    }

    @Test func newestQueueTombstoneSuppressesDeterministically() throws {
        let queueID = UUID(uuidString: "00000000-0000-0000-0000-00000000DDDD")!
        let contents = try backupWithQueuedWork(
            queueID: queueID,
            queueName: "Between Deletes",
            queueDateUpdated: Date(timeIntervalSince1970: 200),
            lastMembershipChangedAt: Date(timeIntervalSince1970: 200),
            membershipModifiedAt: Date(timeIntervalSince1970: 200),
            exportedAt: Date(timeIntervalSince1970: 200)
        )

        let targetContainer = try container()
        let context = targetContainer.mainContext
        context.insert(SyncTombstone(
            recordID: queueID,
            recordType: .readingQueue,
            createdAt: Date(timeIntervalSince1970: 50)
        ))
        context.insert(SyncTombstone(
            recordID: queueID,
            recordType: .readingQueue,
            createdAt: Date(timeIntervalSince1970: 300)
        ))

        let summary = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let queues = try context.fetch(FetchDescriptor<ReadingQueue>())
        #expect(queues.allSatisfy { $0.kind == .savedForLater })
        #expect(summary.suppressedQueues == 1)
        #expect(summary.suppressedQueueMemberships == 1)
    }

    @Test func oldQueueTombstoneDoesNotSuppressFreshQueueID() throws {
        let oldQueueID = UUID(uuidString: "00000000-0000-0000-0000-00000000EEEE")!
        let newQueueID = UUID(uuidString: "00000000-0000-0000-0000-00000000EEEF")!
        let contents = try backupWithQueuedWork(
            queueID: newQueueID,
            queueName: "Fresh Queue",
            queueDateUpdated: Date(timeIntervalSince1970: 200),
            lastMembershipChangedAt: Date(timeIntervalSince1970: 200),
            membershipModifiedAt: Date(timeIntervalSince1970: 200),
            exportedAt: Date(timeIntervalSince1970: 200)
        )

        let targetContainer = try container()
        let context = targetContainer.mainContext
        context.insert(SyncTombstone(
            recordID: oldQueueID,
            recordType: .readingQueue,
            createdAt: Date(timeIntervalSince1970: 300)
        ))

        let summary = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let restored = try #require(try context.fetch(FetchDescriptor<ReadingQueue>())
            .first { $0.id == newQueueID })
        #expect(restored.name == "Fresh Queue")
        #expect(summary.suppressedQueues == 0)
    }

    @Test func membershipChangesUpdateQueueFreshnessSignal() throws {
        let container = try container()
        let context = container.mainContext
        let queue = ReadingQueue(name: "Freshness")
        let work = SavedWork(title: "Queued", author: "Writer")
        context.insert(queue)
        context.insert(work)

        let originalFreshness = queue.lastMembershipChangedAt
        let membership = ReadingQueueService.add(work, to: queue, in: context)
        #expect(queue.lastMembershipChangedAt >= membership.lastModifiedAt)
        #expect(queue.lastMembershipChangedAt >= originalFreshness)
        let afterAdd = queue.lastMembershipChangedAt

        ReadingQueueService.removeFromQueue(work, from: queue, in: context)
        #expect(queue.lastMembershipChangedAt >= afterAdd)
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

    /// A backup file's own export wall-clock time has no bearing on whether the queue's
    /// content actually changed. A queue whose real content (dateUpdated/membership
    /// activity) predates the tombstone must stay suppressed even if the file it's
    /// bundled in was written long after the deletion.
    @Test func exportedAtAloneDoesNotReviveContentStaleQueue() throws {
        let queueID = UUID(uuidString: "00000000-0000-0000-0000-00000000FFFF")!
        let contents = try backupWithQueuedWork(
            queueID: queueID,
            queueName: "Stale Content",
            queueDateUpdated: Date(timeIntervalSince1970: 50),
            lastMembershipChangedAt: Date(timeIntervalSince1970: 50),
            membershipModifiedAt: Date(timeIntervalSince1970: 50),
            exportedAt: Date(timeIntervalSince1970: 100_000)
        )

        let targetContainer = try container()
        let context = targetContainer.mainContext
        context.insert(SyncTombstone(
            recordID: queueID,
            recordType: .readingQueue,
            createdAt: Date(timeIntervalSince1970: 500)
        ))

        let summary = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let queues = try context.fetch(FetchDescriptor<ReadingQueue>())
        #expect(queues.allSatisfy { $0.kind == .savedForLater })
        #expect(summary.suppressedQueues == 1)
        #expect(summary.revivedQueues == 0)
    }

    /// Tombstones must travel with a backup so a fresh install/reinstall inherits the
    /// source device's deletion history — otherwise a later import of an older backup
    /// (made before the deletion) would resurrect the deleted work with zero local
    /// tombstone history to stop it.
    @Test func tombstoneSurvivesBackupRoundTripIntoFreshInstall() throws {
        let defaults = try testDefaults()
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext

        let work = SavedWork(title: "Deleted Before Reinstall", author: "Writer",
                             sourceURL: "https://archiveofourown.org/works/909")
        sourceContext.insert(work)
        WorkLifecycle.delete(work, in: sourceContext)
        let sourceTombstones = try sourceContext.fetch(FetchDescriptor<SyncTombstone>())
        #expect(sourceTombstones.count == 1)

        // The source device's current backup: the work is already gone, but the
        // tombstone recording its deletion is included.
        let carrierDocument = try KudosBackupService.makeDocument(
            works: [],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            tombstones: sourceTombstones,
            defaults: defaults
        )

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        _ = try KudosBackupService.restore(carrierDocument.contents, into: targetContext, defaults: defaults)
        // The fresh install now has the tombstone, though it never deleted anything itself.
        #expect(try targetContext.fetch(FetchDescriptor<SyncTombstone>()).count == 1)

        // A separate, older backup still contains the work as it was before deletion.
        let staleArchive = SavedWork(title: "Deleted Before Reinstall", author: "Writer",
                                     sourceURL: "https://archiveofourown.org/works/909")
        staleArchive.markModified(Date(timeIntervalSince1970: 100))
        let staleDocument = try KudosBackupService.makeDocument(
            works: [staleArchive],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )

        _ = try KudosBackupService.restore(staleDocument.contents, into: targetContext, defaults: defaults)

        #expect(try targetContext.fetch(FetchDescriptor<SavedWork>()).isEmpty)
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "PersistenceSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func backupWithQueuedWork(
        queueID: UUID,
        queueName: String,
        queueDateUpdated: Date,
        lastMembershipChangedAt: Date,
        membershipModifiedAt: Date,
        exportedAt: Date
    ) throws -> KudosBackupContents {
        let sourceContainer = try container()
        let context = sourceContainer.mainContext
        let workID = 424_242
        let work = SavedWork(
            title: "Queued Conflict Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/\(workID)"
        )
        work.ao3WorkID = workID
        work.markModified(queueDateUpdated)
        let queue = ReadingQueue(
            id: queueID,
            name: queueName,
            kind: .custom,
            sortOrder: 0,
            dateCreated: Date(timeIntervalSince1970: 10),
            dateUpdated: queueDateUpdated
        )
        queue.lastMembershipChangedAt = lastMembershipChangedAt
        let membership = ReadingQueueMembership(
            queue: queue,
            work: work,
            queuedAt: Date(timeIntervalSince1970: 20),
            sortOrderInQueue: 0
        )
        membership.lastModifiedAt = membershipModifiedAt
        context.insert(work)
        context.insert(queue)
        context.insert(membership)
        queue.memberships.append(membership)
        work.queueMemberships.append(membership)
        try context.save()

        let queueArchive = KudosBackupReadingQueue(queue: queue)
        let membershipArchive = try #require(KudosBackupReadingQueueMembership(membership: membership))
        return KudosBackupContents(manifest: KudosBackupManifest(
            exportedAt: exportedAt,
            works: [KudosBackupWork(work: work)],
            bookmarks: [],
            fonts: [],
            readingQueues: [queueArchive],
            readingQueueMemberships: [membershipArchive],
            settings: .capture(defaults: try testDefaults())
        ))
    }
}
