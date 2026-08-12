import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Covers `ReadingQueueWorkPicker` — the eligibility rules behind the in-queue
/// "Add Works" picker (`AddWorksToQueueView`). Adding itself is async service work
/// (`ReadingQueueService.addAndPreserve`) and is covered by `ReadingQueueTests`.
@MainActor
struct ReadingQueueWorkPickerTests {
    // MARK: candidates

    @Test func candidatesExcludeExistingMembers() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "Shelf", in: context)
        let member = try insertWork(into: context, title: "Already In")
        let outsider = try insertWork(into: context, title: "Not In")
        ReadingQueueService.add(member, to: queue, in: context)

        let candidates = ReadingQueueWorkPicker.candidates(from: [member, outsider], notIn: queue)

        #expect(candidates.map(\.id) == [outsider.id])
    }

    @Test func candidatesExcludeQueueOnlyWorks() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "Shelf", in: context)
        let normal = try insertWork(into: context, title: "Normal")
        let queueOnly = try insertWork(into: context, title: "Queue Only")
        // Queued but not saved/favorited → a queue-only preservation record, which
        // the Library hides from normal shelves and the picker must not offer.
        queueOnly.isQueuedForLater = true
        try context.save()

        let candidates = ReadingQueueWorkPicker.candidates(from: [normal, queueOnly], notIn: queue)

        #expect(candidates.map(\.id) == [normal.id])
    }

    @Test func candidatesKeepNonMembersEvenIfQueuedElsewhere() throws {
        let context = try makeContext()
        let target = ReadingQueueService.createQueue(named: "Target", in: context)
        let other = ReadingQueueService.createQueue(named: "Other", in: context)
        let work = try insertWork(into: context, title: "Cross-queue")
        // Saved so it is not queue-only after joining `other`.
        work.isSaved = true
        ReadingQueueService.add(work, to: other, in: context)

        let candidates = ReadingQueueWorkPicker.candidates(from: [work], notIn: target)

        #expect(candidates.map(\.id) == [work.id])
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
