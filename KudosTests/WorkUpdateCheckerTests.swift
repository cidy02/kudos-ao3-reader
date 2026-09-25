import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-255: Home's update sweep runs from a `.task` that SwiftUI cancels on a tab
/// switch. It used to keep looping, stamping every remaining work as checked (and
/// hiding real chapter updates for 6 h) while each pass booked pacer time.
@MainActor
struct WorkUpdateCheckerTests {
    private actor FetchCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    /// `fetchThrows`: the in-flight fetch sees the cancellation (the usual case) or
    /// finishes first. Either way the sweep stops after it, and no work it never
    /// asked AO3 about is stamped.
    @Test(arguments: [true, false])
    func aCancelledSweepStopsAfterTheFetchInFlight(fetchThrows: Bool) async throws {
        let context = try makeContext()
        let works = (1...3).map { id in
            let work = SavedWork(
                title: "WIP \(id)", author: "Someone",
                sourceURL: "https://archiveofourown.org/works/\(id)"
            )
            work.ao3WorkID = id
            work.chapters = "1/?"
            context.insert(work)
            return work
        }
        let counter = FetchCounter()

        await Task {
            await WorkUpdateChecker.checkForUpdates(among: works, in: context) { _ in
                await counter.increment()
                withUnsafeCurrentTask { $0?.cancel() }
                if fetchThrows { throw CancellationError() }
                var groups = AO3WorkTagGroups()
                groups.fandoms = ["A Fandom"]
                groups.chapters = "2/?"
                return groups
            }
        }.value

        #expect(await counter.count == 1)
        #expect((works[0].lastUpdateCheck != nil) == !fetchThrows)
        #expect(works[1].lastUpdateCheck == nil)
        #expect(works[2].lastUpdateCheck == nil)
    }
}
