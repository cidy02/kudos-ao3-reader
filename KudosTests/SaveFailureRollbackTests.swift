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

    @Test func aRefusedCollectionSaveRollsBack() throws {
        let context = try refusingContext()
        context.insert(WorkCollection(name: "Comfort reads"))
        #expect(!context.saveBestEffort(reason: "test"))
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<WorkCollection>()).isEmpty)
    }
}
