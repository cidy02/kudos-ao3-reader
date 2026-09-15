import Foundation
import SwiftData
import Testing
@testable import Kudos

/// The History and Favorites sections that moved from the Account tab into the
/// Library dashboard.
///
/// Favorites still matches the partition the old Account list used. History does
/// not, deliberately: artboard 1ah redefines it as the works you have *read*
/// rather than the works whose EPUB was freed, so these pin the reading-evidence
/// rule and the most-recently-read ordering the time buckets depend on.
@MainActor
struct LibrarySectionKindTests {
    @Test func historyMatchesWorksYouHaveRead() throws {
        let context = try makeContext()
        let epoch = Date(timeIntervalSince1970: 0)
        // Read and then freed — the only thing the old `!hasEPUB` rule caught.
        let freed = work(in: context, title: "Freed", dateAdded: epoch)
        freed.hasEPUB = false
        freed.lastReadDate = Date(timeIntervalSince1970: 300)
        // Mid-way with its file on disk: invisible to the old rule, and the state
        // 1ai's Abandoned section is derived from.
        let inProgress = work(in: context, title: "InProgress", dateAdded: epoch)
        inProgress.hasEPUB = true
        inProgress.lastReadDate = Date(timeIntervalSince1970: 400)
        // Finished qualifies on its own, with no other reading evidence recorded —
        // it falls back to `dateAdded` for ordering, hence the fixed date.
        let finished = work(in: context, title: "Finished", dateAdded: Date(timeIntervalSince1970: 100))
        finished.hasEPUB = true
        finished.isFinished = true
        // Downloaded but never opened is not history.
        let unread = work(in: context, title: "Unread", dateAdded: epoch)
        unread.hasEPUB = true
        // A queue entry you never opened is not history either — reading evidence
        // excludes it without needing the old `!isQueuedForLater` guard.
        let queued = work(in: context, title: "Queued", dateAdded: epoch)
        queued.hasEPUB = false
        queued.isQueuedForLater = true

        // Most-recently-read first: the time buckets assume the caller sorted.
        let titles = LibrarySectionKind.history
            .works(from: [freed, inProgress, finished, unread, queued], visible: { _ in true })
            .map(\.title)
        #expect(titles == ["InProgress", "Freed", "Finished"])
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
        visible.lastReadDate = Date(timeIntervalSince1970: 100)
        let hidden = work(in: context, title: "Hidden")
        hidden.isFavorite = true
        hidden.hasEPUB = false
        hidden.lastReadDate = Date(timeIntervalSince1970: 200)

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
