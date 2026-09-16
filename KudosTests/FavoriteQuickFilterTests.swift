import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Artboard 1aj's All / Rereads / Offline / WIP rail. Each case is a claim about
/// which works belong, and two of them are easy to get backwards — "WIP" is the
/// work's posted status rather than your progress, and a reread is a *second
/// finish* rather than a second visit.
@MainActor
struct FavoriteQuickFilterTests {
    @Test func allKeepsEverything() throws {
        let context = try makeContext()
        let works = [work(in: context, title: "A"), work(in: context, title: "B")]
        #expect(FavoriteQuickFilter.all.apply(to: works, finishCounts: [:]).count == 2)
    }

    @Test func rereadsNeedsASecondFinishNotASecondVisit() throws {
        let context = try makeContext()
        let onceRead = work(in: context, title: "Once")
        let reread = work(in: context, title: "Reread")
        let never = work(in: context, title: "Never")
        // One finish is a read, not a reread — the boundary this chip is easiest
        // to get wrong at.
        let counts = [onceRead.id: 1, reread.id: 3]

        let titles = FavoriteQuickFilter.rereads
            .apply(to: [onceRead, reread, never], finishCounts: counts)
            .map(\.title)
        #expect(titles == ["Reread"])
    }

    @Test func offlineIsTheFileOnDisk() throws {
        let context = try makeContext()
        let downloaded = work(in: context, title: "Downloaded")
        downloaded.hasEPUB = true
        let freed = work(in: context, title: "Freed")
        freed.hasEPUB = false

        let titles = FavoriteQuickFilter.offline
            .apply(to: [downloaded, freed], finishCounts: [:])
            .map(\.title)
        #expect(titles == ["Downloaded"])
    }

    @Test func wipIsAO3PostedStatusNotReadingProgress() throws {
        let context = try makeContext()
        let ongoing = work(in: context, title: "Ongoing")
        ongoing.isComplete = false
        // Complete on AO3 but only part-read locally: still not a WIP.
        let completeButUnfinished = work(in: context, title: "CompleteButUnfinished")
        completeButUnfinished.isComplete = true
        completeButUnfinished.lastReadDate = Date(timeIntervalSince1970: 100)

        let titles = FavoriteQuickFilter.wip
            .apply(to: [ongoing, completeButUnfinished], finishCounts: [:])
            .map(\.title)
        #expect(titles == ["Ongoing"])
    }

    @Test func authorNewWorkNeedsAFetchedUnreadAccount() {
        let unread = remoteWork(id: 1)
        let alreadyRead = remoteWork(id: 2)
        let rows = [
            authorRow("Unread", username: "unread"),
            authorRow("Already read", username: "seen"),
            authorRow("No visible works", username: "empty"),
            authorRow("Not fetched", username: "missing"),
            authorRow("Anonymous", username: nil)
        ]
        let newestWorks: [String: AO3WorkSummary?] = [
            "unread": unread,
            "seen": alreadyRead,
            "empty": Optional<AO3WorkSummary>.none
        ]

        let filtered = FavoriteAuthorQuickFilter.withNewWork.apply(
            to: rows,
            newestWorkForUsername: { newestWorks[$0] },
            readWorkIDs: [alreadyRead.id]
        )

        // A cache miss is unknown rather than new, and an author without a
        // registered account has no AO3 works page to inspect.
        #expect(filtered.map(\.name) == ["Unread"])
    }

    private func authorRow(_ name: String, username: String?) -> ReadingAffinities.Row {
        ReadingAffinities.Row(
            name: name,
            worksRead: 1,
            totalSeconds: 0,
            lastRead: nil,
            username: username,
            unreadInLibrary: 0,
            downloadedInLibrary: 0,
            savedForLater: 0
        )
    }

    private func remoteWork(id: Int) -> AO3WorkSummary {
        AO3WorkSummary.subscription(id: id, title: "Work \(id)", authors: [])
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

    @discardableResult
    private func work(in context: ModelContext, title: String) -> SavedWork {
        let work = SavedWork(title: title, author: "Writer")
        context.insert(work)
        return work
    }
}
