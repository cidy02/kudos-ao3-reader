import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Covers `CollectionWorkPicker` — the eligibility + add rules behind the
/// in-collection "Add Works" picker (`AddWorksToCollectionView`).
@MainActor
struct CollectionWorkPickerTests {
    // MARK: candidates

    @Test func candidatesExcludeExistingMembers() throws {
        let context = try makeContext()
        let collection = insertCollection(into: context)
        let member = try insertWork(into: context, title: "Already In")
        let outsider = try insertWork(into: context, title: "Not In")
        CollectionWorkPicker.add([member], to: collection, in: context)

        let candidates = CollectionWorkPicker.candidates(from: [member, outsider], notIn: collection)

        #expect(candidates.map(\.id) == [outsider.id])
    }

    @Test func candidatesExcludeQueueOnlyWorks() throws {
        let context = try makeContext()
        let collection = insertCollection(into: context)
        let normal = try insertWork(into: context, title: "Normal")
        let queueOnly = try insertWork(into: context, title: "Queue Only")
        // Queued but not saved/favorited → a queue-only preservation record, which
        // the Library hides from normal shelves and the picker must not offer.
        queueOnly.isQueuedForLater = true
        try context.save()

        let candidates = CollectionWorkPicker.candidates(from: [normal, queueOnly], notIn: collection)

        #expect(candidates.map(\.id) == [normal.id])
    }

    // MARK: add

    @Test func addInsertsMembershipOnBothSides() throws {
        let context = try makeContext()
        let collection = insertCollection(into: context)
        let work = try insertWork(into: context, title: "New Member")

        CollectionWorkPicker.add([work], to: collection, in: context)

        #expect(work.collections.contains { $0.id == collection.id })
        #expect(collection.works.contains { $0.id == work.id })
    }

    @Test func addIsIdempotentForExistingMembers() throws {
        let context = try makeContext()
        let collection = insertCollection(into: context)
        let work = try insertWork(into: context, title: "Member")

        CollectionWorkPicker.add([work], to: collection, in: context)
        CollectionWorkPicker.add([work], to: collection, in: context)

        // No duplicate membership from adding the same work twice.
        #expect(work.collections.count(where: { $0.id == collection.id }) == 1)
    }

    @Test func addStampsBothSidesModified() throws {
        let context = try makeContext()
        let collection = insertCollection(into: context)
        let work = try insertWork(into: context, title: "Stamp Me")
        let stampedAt = Date(timeIntervalSince1970: 1_000_000)

        CollectionWorkPicker.add([work], to: collection, in: context, now: stampedAt)

        #expect(work.lastModifiedAt == stampedAt)
        #expect(collection.lastModifiedAt == stampedAt)
    }

    // MARK: helpers

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func insertCollection(into context: ModelContext) -> WorkCollection {
        let collection = WorkCollection(name: "Shelf")
        context.insert(collection)
        return collection
    }

    private func insertWork(into context: ModelContext, title: String) throws -> SavedWork {
        let work = SavedWork(
            title: title,
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/\(abs(title.hashValue))"
        )
        context.insert(work)
        try context.save()
        return work
    }
}
