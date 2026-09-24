import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Artboard 1h's queue page and Queue details: the strip's buckets, the quick
/// filter counts, "Last read", the kicker path, and 1j's tags on create.
@MainActor
struct ReadingQueueFactsTests {
    @Test func stripBucketsSumToTheQueueWithFreedCopiesAsUnread() {
        let progress = ReadingQueueFacts.progress(of: [.finished, .finished, .inProgress, .unread, .freedHistory])
        #expect(progress == ReadingQueueFacts.Progress(finished: 2, inProgress: 1, unread: 2))
        #expect(progress.total == 5)
    }

    @Test func lastReadIsTheLatestDateIgnoringUnread() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 900)
        #expect(ReadingQueueFacts.lastRead([early, nil, late]) == late)
        #expect(ReadingQueueFacts.lastRead([nil, nil]) == nil)
    }

    @Test func kickerNamesTheOriginTab() {
        #expect(ReadingQueueFacts.kicker(origin: "Home") == "Home › Queues")
        #expect(ReadingQueueFacts.kicker(origin: "Library") == "Library › Queues")
        #expect(ReadingQueueFacts.kicker(origin: "Home", isDetails: true) == "Home › Queues › Queue details")
    }

    @Test func quickFilterCountsAgreeWithTheStripAndTheOfflineSet() throws {
        let context = try makeContext()
        let unread = work(in: context, title: "Unread")
        let reading = work(in: context, title: "Reading")
        reading.lastReadDate = Date(timeIntervalSince1970: 50)
        let finished = work(in: context, title: "Finished")
        finished.isFinished = true
        finished.isComplete = true
        let freed = work(in: context, title: "Freed")
        freed.hasEPUB = false
        freed.isComplete = true
        let works = [unread, reading, finished, freed]

        let counts = QueueQuickFilter.counts(in: works, preservedIDs: [unread.id, reading.id])
        #expect(counts == [.all: 4, .unread: 2, .offline: 2, .wip: 2])
        // Unread is exactly the strip's unread bucket.
        #expect(counts[.unread] == ReadingQueueFacts.progress(of: works.map(\.readingState)).unread)
    }

    @Test func createQueueTagsReuseAnExistingTagIgnoringCase() throws {
        let context = try makeContext()
        let existing = Kudos.Tag(name: "Rereads")
        context.insert(existing)

        let queue = ReadingQueueService.createQueue(
            named: "Neon", tagNames: ["rereads", "Long fic", "long fic"], in: context
        )

        #expect(queue.tags.map(\.name).sorted() == ["Long fic", "Rereads"])
        #expect(queue.tags.contains { $0.persistentModelID == existing.persistentModelID })
        #expect(try context.fetch(FetchDescriptor<Kudos.Tag>()).count == 2)
    }

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

    private func work(in context: ModelContext, title: String) -> SavedWork {
        let work = SavedWork(title: title, author: "Writer")
        context.insert(work)
        return work
    }
}
