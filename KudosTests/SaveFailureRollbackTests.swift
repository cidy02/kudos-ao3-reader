import Foundation
import SwiftData
import Testing
@testable import Kudos

/// I11: a sheet whose save fails stays open and rolls its context back, so trying again can't make a
/// duplicate and nothing unsaved lingers to be written later. These hold what that relies on: a
/// refused save reports false, and the rollback takes the half-made object away. (The sheets
/// themselves have no view tests.)
@MainActor
struct SaveFailureRollbackTests {
    private func refusingContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        // An in-memory store can't be opened read-only, so: make a store on disk, then reopen it
        // read-only. That container's saves are refused, as a full disk or a store error would be.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("refused-save-\(UUID().uuidString).store")
        _ = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let readOnly = ModelConfiguration(schema: schema, url: url, allowsSave: false)
        return ModelContext(try ModelContainer(for: schema, configurations: [readOnly]))
    }

    @Test func aRefusedQueueSaveRollsBackWithoutADuplicate() throws {
        let context = try refusingContext()
        _ = ReadingQueueService.createQueue(named: "Slow burns", in: context)
        #expect(!context.saveBestEffort(reason: "test"))
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<ReadingQueue>()).isEmpty)
    }

    @Test func aSeededCreateThatFailsOnTheSecondSaveLeavesNoPrefix() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
        let first = SavedWork(
            title: "First", author: "W", sourceURL: "https://archiveofourown.org/works/1"
        )
        let second = SavedWork(
            title: "Second", author: "W", sourceURL: "https://archiveofourown.org/works/2"
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        // One save is allowed: the old path committed the queue on the first
        // membership and left it behind when the second save failed. Create now
        // saves once; that one save either takes the whole queue or none of it.
        SaveBestEffortTesting.$budget.withValue(SaveBestEffortTesting.SaveBudget(1)) {
            _ = ReadingQueueService.createQueue(
                named: "Seeded",
                seedWorkIDs: [first.id, second.id],
                in: context
            )
            if !context.saveBestEffort(reason: "test") {
                context.rollback()
            }
        }

        let queues = try context.fetch(FetchDescriptor<ReadingQueue>())
            .filter { $0.name == "Seeded" }
        let memberships = try context.fetch(FetchDescriptor<ReadingQueueMembership>())
        #expect(queues.count <= 1)
        if let queue = queues.first {
            #expect(ReadingQueueService.orderedWorks(in: queue).count == 2)
        } else {
            #expect(memberships.isEmpty)
        }
    }

    @Test func aRefusedCollectionSaveRollsBack() throws {
        let context = try refusingContext()
        context.insert(WorkCollection(name: "Comfort reads"))
        #expect(!context.saveBestEffort(reason: "test"))
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<WorkCollection>()).isEmpty)
    }
}
