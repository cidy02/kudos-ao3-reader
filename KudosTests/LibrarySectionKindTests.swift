import Foundation
import SwiftData
import Testing
@testable import Kudos

/// The History and Favorites sections that moved from the Account tab into the
/// Library dashboard: their `works(from:visible:)` predicates must match the
/// partitions the old Account lists used, so the move loses nothing.
@MainActor
struct LibrarySectionKindTests {
    @Test func historyMatchesFreedNonQueuedWorks() throws {
        let context = try makeContext()
        let freed = work(in: context, title: "Freed")
        freed.hasEPUB = false
        let downloaded = work(in: context, title: "Downloaded")
        downloaded.hasEPUB = true
        let queued = work(in: context, title: "Queued")
        queued.hasEPUB = false
        queued.isQueuedForLater = true

        let titles = LibrarySectionKind.history
            .works(from: [freed, downloaded, queued], visible: { _ in true })
            .map(\.title)
        #expect(titles == ["Freed"])
    }

    @Test func favoritesMatchesStarredWorksNewestFirst() throws {
        let context = try makeContext()
        let older = work(in: context, title: "OlderFav", dateAdded: Date(timeIntervalSince1970: 100))
        older.isFavorite = true
        let newer = work(in: context, title: "NewerFav", dateAdded: Date(timeIntervalSince1970: 200))
        newer.isFavorite = true
        let plain = work(in: context, title: "Plain")

        let titles = LibrarySectionKind.favorites
            .works(from: [older, newer, plain], visible: { _ in true })
            .map(\.title)
        #expect(titles == ["NewerFav", "OlderFav"])
    }

    @Test func bothSectionsHonorThePrivacyPredicate() throws {
        let context = try makeContext()
        let visible = work(in: context, title: "Visible")
        visible.isFavorite = true
        visible.hasEPUB = false
        let hidden = work(in: context, title: "Hidden")
        hidden.isFavorite = true
        hidden.hasEPUB = false

        let notHidden: (SavedWork) -> Bool = { $0.title != "Hidden" }
        #expect(
            LibrarySectionKind.favorites.works(from: [visible, hidden], visible: notHidden)
                .map(\.title) == ["Visible"]
        )
        #expect(
            LibrarySectionKind.history.works(from: [visible, hidden], visible: notHidden)
                .map(\.title) == ["Visible"]
        )
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
    private func work(in context: ModelContext, title: String, dateAdded: Date = Date()) -> SavedWork {
        let work = SavedWork(title: title, author: "Writer")
        work.dateAdded = dateAdded
        context.insert(work)
        return work
    }
}
