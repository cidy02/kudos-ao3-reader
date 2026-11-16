import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct QueueQuickAddTests {
    private func context() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    @Test func resultNamesZeroOneAndManyQueues() {
        func status(_ names: [String]) -> String? {
            AO3WorkRow.statusText(
                readingState: .unread, chapterLabel: nil, isWantToRead: false,
                queueNames: names, isInLibrary: false
            )
        }
        #expect(status([]) == nil)
        #expect(status(["Summer Reading"]) == "In Summer Reading")
        #expect(status(["Summer Reading", "For the Train"]) == "In 2 queues")
        #expect(AO3WorkRow.statusText(
            readingState: .unread, chapterLabel: nil, isWantToRead: true,
            queueNames: ["Want to Read"], isInLibrary: false
        ) == "In Want to Read")
    }

    @Test func currentQueueUsesSourceThenStoredThenWantToRead() throws {
        let fallback = ReadingQueue(name: "Saved for Later", kind: .savedForLater)
        let stored = ReadingQueue(name: "Stored")
        let source = ReadingQueue(name: "Source")
        let queues = [fallback, stored, source]
        #expect(RemoteWorkSelectionController.currentQueue(
            in: queues, sourceID: source.id, storedID: stored.id.uuidString
        )?.id == source.id)
        #expect(RemoteWorkSelectionController.currentQueue(
            in: queues, sourceID: nil, storedID: stored.id.uuidString
        )?.id == stored.id)
        #expect(RemoteWorkSelectionController.currentQueue(
            in: queues, sourceID: nil, storedID: UUID().uuidString
        )?.id == fallback.id)
    }

    @Test func repeatAddDoesNotDuplicateMembershipOrFetchForListOnlyQueue() async throws {
        let context = try context()
        let queue = ReadingQueue(name: "List")
        queue.keepsWorksOffline = false
        let work = SavedWork(
            title: "Remote", author: "Writer", sourceURL: "https://archiveofourown.org/works/123"
        )
        work.ao3WorkID = 123
        context.insert(queue)
        context.insert(work)
        _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
        _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
        #expect(work.queueMemberships.count == 1)
        #expect(!work.hasEPUB)
    }

    @Test func lastQueuePreferenceRoundTripsAndIsOmittedWhenUnset() throws {
        func defaults() throws -> UserDefaults {
            let suite = "QueueQuickAddTests.\(UUID().uuidString)"
            let value = try #require(UserDefaults(suiteName: suite))
            value.removePersistentDomain(forName: suite)
            return value
        }
        let empty = KudosBackupSettings.capture(defaults: try defaults())
        let emptyJSON = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(empty)
        ) as? [String: Any])
        #expect(emptyJSON["lastAddedReadingQueueID"] == nil)

        let source = try defaults()
        let id = UUID()
        source.set(id.uuidString, forKey: "lastAddedReadingQueueID")
        let decoded = try JSONDecoder().decode(
            KudosBackupSettings.self,
            from: JSONEncoder().encode(KudosBackupSettings.capture(defaults: source))
        )
        let destination = try defaults()
        decoded.apply(to: destination)
        #expect(destination.string(forKey: "lastAddedReadingQueueID") == id.uuidString)
        empty.apply(to: destination)
        #expect(destination.string(forKey: "lastAddedReadingQueueID") == id.uuidString)
    }
}
