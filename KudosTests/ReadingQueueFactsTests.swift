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

    /// 1b.5: "7 works · next up 3" — the first work not yet finished.
    @Test func cardFooterNamesTheFirstUnfinishedPlace() {
        let states: [SavedWork.ReadingState] = [.finished, .finished, .inProgress, .unread]
        #expect(ReadingQueueFacts.nextUpPosition(states: states) == 3)
        #expect(ReadingQueueFacts.cardFooter(states: states) == "4 works · next up 3")
        #expect(ReadingQueueFacts.cardFooter(states: [.unread]) == "1 work · next up 1")
        // Nothing left to read, or nothing queued: no "next up".
        #expect(ReadingQueueFacts.cardFooter(states: [.finished, .finished]) == "2 works")
        #expect(ReadingQueueFacts.cardFooter(states: []) == "0 works")
    }

    /// Home's card face and the queue page's Up next row are one rule. For
    /// [finished A, unread B] both are B, and the footer's "next up 2" names
    /// the same work; A stays In line. A fully read queue leads with its first.
    @Test func homeCardAndQueuePageAgreeOnUpNext() throws {
        let context = try makeContext()
        let finished = work(in: context, title: "A")
        finished.isFinished = true
        let unread = work(in: context, title: "B")
        let later = work(in: context, title: "C")

        let split = ReadingQueueFacts.upNext(in: [finished, unread, later])
        #expect(split.upNext?.title == "B")
        #expect(split.inLine.map(\.title) == ["A", "C"])
        let states = [finished, unread, later].map(\.readingState)
        #expect(ReadingQueueFacts.cardFooter(states: states) == "3 works · next up 2")

        later.isFinished = true
        unread.isFinished = true
        let allRead = ReadingQueueFacts.upNext(in: [finished, unread, later])
        #expect(allRead.upNext?.title == "A")
        #expect(allRead.inLine.map(\.title) == ["B", "C"])
        #expect(ReadingQueueFacts.upNext(in: []).upNext == nil)
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
