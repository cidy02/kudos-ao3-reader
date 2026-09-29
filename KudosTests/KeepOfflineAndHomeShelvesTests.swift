import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-276 items 3–4: what Keep downloaded / Keep downloads does (`KeepOffline`,
/// `SavedWork.isKeptOffline`) and 1bk's Show on Home shelves
/// (`HomeCollectionShelves`). No test here reaches the network: the ON-queue
/// fetch goes through `ReadingQueueService.preserve`, whose own suite stubs it.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct KeepOfflineAndHomeShelvesTests {
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

    /// An AO3 work, as a download would have left it.
    private func ao3Work(_ id: Int, in context: ModelContext, hasEPUB: Bool = true) -> SavedWork {
        let work = SavedWork(id: UUID(), title: "Work \(id)", author: "Writer")
        work.sourceURL = "https://archiveofourown.org/works/\(id)"
        work.ao3WorkID = id
        work.hasEPUB = hasEPUB
        context.insert(work)
        return work
    }

    @Test func aNeverAskedQueueKeepsAndOnlyAnOnCollectionDoes() {
        #expect(KeepOffline.queueKeeps(nil))
        #expect(KeepOffline.queueKeeps(true))
        #expect(!KeepOffline.queueKeeps(false))
        #expect(!KeepOffline.collectionKeeps(nil))
        #expect(KeepOffline.collectionKeeps(true))
        #expect(!KeepOffline.collectionKeeps(false))
    }

    /// The sweep exemption follows the toggles: a work held only by an OFF
    /// queue is freed when finished; one in an ON collection keeps its EPUB.
    @Test func finishingFreesOnlyWhatNoKeepOfflineContainerHolds() throws {
        let context = try makeContext()
        let plain = ReadingQueue(name: "Plain")
        plain.keepsWorksOffline = false
        let kept = WorkCollection(name: "Kept")
        kept.keepsWorksOffline = true
        context.insert(plain)
        context.insert(kept)
        let listed = ao3Work(1, in: context)
        ReadingQueueService.add(listed, to: plain, in: context)
        let collected = ao3Work(2, in: context)
        collected.collections.append(kept)
        try context.save()

        #expect(!listed.isProtected)
        #expect(collected.isProtected)
        WorkLifecycle.markFinished(listed, in: context)
        WorkLifecycle.markFinished(collected, in: context)
        #expect(!listed.hasEPUB)
        #expect(collected.hasEPUB)

        // A never-asked queue keeps its works, as queues always did.
        let legacy = ReadingQueue(name: "Legacy")
        context.insert(legacy)
        let queued = ao3Work(3, in: context)
        ReadingQueueService.add(queued, to: legacy, in: context)
        #expect(queued.isProtected)
    }

    /// OFF is "just a list": adding to it preserves nothing (no fetch).
    @Test func addingToAnOffQueueFetchesNothing() async throws {
        let context = try makeContext()
        let plain = ReadingQueue(name: "Plain")
        plain.keepsWorksOffline = false
        context.insert(plain)
        let work = ao3Work(4, in: context, hasEPUB: false)
        try context.save()

        _ = await ReadingQueueService.addAndPreserve(work, to: plain, in: context)
        // `add` marks a queued work with no file as missing; preserving it would
        // have stamped an attempt and moved it to preserving.
        #expect(work.lastPreservationAttemptAt == nil)
        #expect(work.epubPreservationStatus != .preserving)
    }

    @Test func aKeepDownloadsCollectionFetchesOnlyMissingAO3Works() throws {
        let context = try makeContext()
        let missing = ao3Work(10, in: context, hasEPUB: false)
        // "Present" means the file is on disk, not just the flag.
        let present = ao3Work(11, in: context)
        try FileManager.default.createDirectory(
            at: present.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data([0]).write(to: present.fileURL)
        defer { try? FileManager.default.removeItem(at: present.fileURL) }
        let deleted = ao3Work(12, in: context, hasEPUB: false)
        deleted.isPendingDeletion = true
        let imported = SavedWork(id: UUID(), title: "Import", author: "Me")
        imported.hasEPUB = false
        context.insert(imported)

        let items = KeepOffline.downloadItems(for: [missing, present, deleted, imported])
        #expect(items.map(\.id) == [10])
        #expect(items.first?.sourceURL?.absoluteString == "https://archiveofourown.org/works/10")
    }

    @Test func homeShowsFlaggedCollectionsInLibraryOrderWithTheirVisibleWorks() throws {
        let context = try makeContext()
        let second = WorkCollection(name: "Beta")
        second.showsOnHome = true
        second.sortOrder = 2
        let first = WorkCollection(name: "Alpha")
        first.showsOnHome = true
        first.sortOrder = 1
        let hidden = WorkCollection(name: "Gamma")
        let deleted = WorkCollection(name: "Delta")
        deleted.showsOnHome = true
        deleted.isPendingDeletion = true
        for collection in [second, first, hidden, deleted] { context.insert(collection) }

        #expect(HomeCollectionShelves.shelves([second, first, hidden, deleted]).map(\.name) == ["Alpha", "Beta"])

        let shown = ao3Work(20, in: context)
        let gone = ao3Work(21, in: context)
        gone.isPendingDeletion = true
        let privateWork = ao3Work(22, in: context)
        for work in [shown, gone, privateWork] { work.collections.append(first) }
        try context.save()
        let works = HomeCollectionShelves.works(in: first) { $0.id != privateWork.id }
        #expect(works.map(\.id) == [shown.id])
    }
}
}
