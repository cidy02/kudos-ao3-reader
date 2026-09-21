import Foundation
import SwiftData
import Testing
@testable import Kudos

/// What the Replace screen promises, held to what restore actually does.
///
/// The footer used to say Replace "does not plant deletion records that would
/// block a later Merge of your own backup". True for works — soft-deleted into
/// Recently Deleted with no tombstone, and the code says why. Not true for the
/// immediate-delete classes: Replace hard-deletes saved links, saved searches,
/// reading history, stars and fandom watermarks and mints a signed tombstone
/// for each, which is precisely a deletion record that blocks a later Merge.
///
/// That behaviour is deliberate and pinned
/// (`replaceThenMergeDoesNotResurrectOmittedBookmarkOrSavedSearch`): without the
/// tombstone, merging any older backup would resurrect them. So the sentence
/// changed, not the code — and it now names the recovery that works, because
/// restore skips tombstones entirely in `.replaceLibrary`.
///
/// These tests are what make that new sentence checkable rather than another
/// promise.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ReplaceUndoCopyRecoveryTests {
    private func context() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SyncTombstone.self, ReadingAnnotation.self, SavedSearch.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "ReplaceUndoCopyRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private struct Fixture {
        let context: ModelContext
        let undoCopy: KudosBackupContents
        let incoming: KudosBackupContents
    }

    /// A library holding a link and a search, the undo copy taken before
    /// Replace, and a newer backup that omits both.
    private func fixture() throws -> Fixture {
        let context = try context()
        let keep = SavedWork(id: UUID(), title: "Keep", author: "A")
        let link = Bookmark(title: "Local only", urlString: "https://archiveofourown.org/works/1")
        let search = SavedSearch(name: "Local search", filters: AO3SearchFilters())
        context.insert(keep)
        context.insert(link)
        context.insert(search)
        try context.save()

        // Taken while the records still exist — this is the copy Replace writes.
        let undoCopy = try KudosBackupService.makeContents(
            works: [keep], bookmarks: [link], fonts: [], readingQueues: [],
            savedSearches: [search], defaults: try testDefaults()
        )
        let incoming = try KudosBackupService.makeContents(
            works: [keep], bookmarks: [], fonts: [], readingQueues: [],
            savedSearches: [], defaults: try testDefaults()
        )
        return Fixture(context: context, undoCopy: undoCopy, incoming: incoming)
    }

    private func replace(
        _ contents: KudosBackupContents, into context: ModelContext
    ) throws {
        _ = try KudosBackupService.restore(
            contents, into: context, defaults: try testDefaults(), mode: .replaceLibrary
        )
    }

    /// The claim the footer now makes.
    @Test func importingTheUndoCopyWithReplaceBringsBackWhatReplaceRemoved() throws {
        let fixture = try fixture()
        try replace(fixture.incoming, into: fixture.context)

        // Replace took them, as it is meant to.
        #expect(try fixture.context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<SavedSearch>()).isEmpty)

        try replace(fixture.undoCopy, into: fixture.context)

        // ...and Replacing with the undo copy is a real undo: restore skips
        // tombstones in this mode, so its own deletion records cannot block it.
        #expect(try fixture.context.fetch(FetchDescriptor<Bookmark>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<SavedSearch>()).count == 1)
    }

    /// The reason the footer names Replace and not Merge. If this ever starts
    /// passing with `.merge`, the footer is over-cautious and should be
    /// rewritten — it is wrong either way if these two disagree.
    @Test func importingTheUndoCopyWithMergeDoesNotBringThemBack() throws {
        let fixture = try fixture()
        try replace(fixture.incoming, into: fixture.context)

        _ = try KudosBackupService.restore(
            fixture.undoCopy, into: fixture.context,
            defaults: try testDefaults(), mode: .merge
        )

        #expect(try fixture.context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<SavedSearch>()).isEmpty)
    }
}
}
