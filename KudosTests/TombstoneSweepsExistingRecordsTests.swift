import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Kudos

/// A deletion that could never settle between two devices.
///
/// Saved searches are an immediate-delete class: no Recently Deleted, just a
/// signed tombstone. Restore consulted that tombstone only while walking the
/// *incoming* records, where it declines to add one back. Nothing ever removed
/// a copy already on this device. So A deletes a search and B adopts the
/// tombstone but keeps showing the search — and B republishes it on its next
/// export, where A suppresses it again. The two devices disagree forever.
///
/// The reading-log restorers already had the answer:
/// `applyTombstonesToExisting`, which asks the same question the other way
/// round — not "should this arriving record be suppressed" but "has this record
/// already here been deleted elsewhere". Saved searches now run it too.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct TombstoneSweepsExistingRecordsTests {
    private func schema() -> Schema {
        Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SyncTombstone.self, ReadingAnnotation.self, SavedSearch.self
        ])
    }

    private func context() throws -> ModelContext {
        let schema = schema()
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "TombstoneSweepsExistingRecordsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A peer's key this device has chosen to trust, so its tombstones count.
    private func trustedPeer(_ defaults: UserDefaults) throws -> Curve25519.Signing.PrivateKey {
        let peer = TombstoneSigning.makePrivateKey()
        #expect(TombstoneTrustStore.add(TombstoneSigning.publicKeyHex(of: peer), defaults: defaults))
        return peer
    }

    private func signedSearchTombstone(
        id: UUID, at seconds: TimeInterval, key: Curve25519.Signing.PrivateKey
    ) -> SyncTombstone {
        let tomb = SyncTombstone(
            recordID: id,
            recordType: .savedSearch,
            createdAt: Date(timeIntervalSince1970: seconds)
        )
        TombstoneSigning.sign(tomb, key: key)
        return tomb
    }

    private func localSearch(
        id: UUID, addedAt seconds: TimeInterval, in context: ModelContext
    ) throws -> SavedSearch {
        let search = SavedSearch(name: "Shared search", filters: AO3SearchFilters())
        search.id = id
        search.dateAdded = Date(timeIntervalSince1970: seconds)
        context.insert(search)
        try context.save()
        return search
    }

    @Test func aTrustedTombstoneRemovesASearchThisDeviceStillHas() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let id = UUID()
        _ = try localSearch(id: id, addedAt: 100, in: context)

        // The peer's backup does not list the search — it deleted it — and
        // carries the tombstone that says so.
        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            savedSearches: [],
            tombstones: [signedSearchTombstone(id: id, at: 400, key: peer)],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(
            snapshot, into: context, defaults: defaults, mode: .merge
        )

        #expect(try context.fetch(FetchDescriptor<SavedSearch>()).isEmpty)
    }

    /// Guard: a search created *after* the deletion is a new one the reader
    /// made, and an older tombstone must not eat it.
    @Test func aSearchMadeAfterTheDeletionSurvives() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let id = UUID()
        _ = try localSearch(id: id, addedAt: 900, in: context)

        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            savedSearches: [],
            tombstones: [signedSearchTombstone(id: id, at: 400, key: peer)],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(
            snapshot, into: context, defaults: defaults, mode: .merge
        )

        #expect(try context.fetch(FetchDescriptor<SavedSearch>()).count == 1)
    }

    /// Guard for the lesson written into `applyTombstonesToExisting`: Replace
    /// deliberately bypasses tombstones, or a repeated identical replacement
    /// becomes destructive — the first restores a record the archive holds, and
    /// the second deletes what it had just put back.
    @Test func replaceLibraryDoesNotSweepExistingSearches() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let id = UUID()
        let search = try localSearch(id: id, addedAt: 100, in: context)

        // The archive contains the search *and* a tombstone for it.
        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            savedSearches: [search],
            tombstones: [signedSearchTombstone(id: id, at: 400, key: peer)],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(
            snapshot, into: context, defaults: defaults, mode: .replaceLibrary
        )

        #expect(try context.fetch(FetchDescriptor<SavedSearch>()).count == 1)
    }

    // MARK: T-366: the three kinds that had no second pass (audit A12)

    private func signedTombstone(
        _ type: SyncTombstoneRecordType, id: UUID, at seconds: TimeInterval,
        key: Curve25519.Signing.PrivateKey
    ) -> SyncTombstone {
        let tomb = SyncTombstone(
            recordID: id, recordType: type, createdAt: Date(timeIntervalSince1970: seconds)
        )
        TombstoneSigning.sign(tomb, key: key)
        return tomb
    }

    /// A saved link removed on the other device goes here too; one saved again
    /// after the removal is a new decision and stays.
    @Test func aTrustedTombstoneRemovesASavedLinkButNotOneSavedAgainLater() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let old = Bookmark(title: "Old", urlString: "https://archiveofourown.org/works/1")
        old.dateAdded = Date(timeIntervalSince1970: 100)
        let later = Bookmark(title: "Later", urlString: "https://archiveofourown.org/works/2")
        later.dateAdded = Date(timeIntervalSince1970: 900)
        context.insert(old)
        context.insert(later)
        try context.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            tombstones: [
                signedTombstone(.bookmark, id: old.id, at: 400, key: peer),
                signedTombstone(.bookmark, id: later.id, at: 400, key: peer)
            ],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        #expect(try context.fetch(FetchDescriptor<Bookmark>()).map(\.title) == ["Later"])
    }

    /// A highlight deleted on the other device goes here too, even when the
    /// archive lists no annotations at all; one edited after the deletion stays.
    @Test func aTrustedTombstoneRemovesAHighlightButNotOneEditedLater() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let work = SavedWork(title: "A work", author: "Someone")
        context.insert(work)
        let gone = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: "a",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        gone.lastModifiedAt = Date(timeIntervalSince1970: 100)
        let edited = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: "b", note: "kept",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        edited.lastModifiedAt = Date(timeIntervalSince1970: 900)
        context.insert(gone)
        context.insert(edited)
        try context.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            tombstones: [
                signedTombstone(.readingAnnotation, id: gone.id, at: 400, key: peer),
                signedTombstone(.readingAnnotation, id: edited.id, at: 400, key: peer)
            ],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        #expect(try context.fetch(FetchDescriptor<ReadingAnnotation>()).map(\.note) == ["kept"])
    }

    /// A work taken out of a queue on the other device leaves it here too; a
    /// membership changed after the removal stays.
    @Test func aTrustedTombstoneRemovesAQueueMembershipButNotOneChangedLater() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let queue = ReadingQueue(name: "To read")
        let first = SavedWork(title: "Removed elsewhere", author: "Someone")
        let second = SavedWork(title: "Moved here since", author: "Someone")
        context.insert(queue)
        context.insert(first)
        context.insert(second)
        let gone = ReadingQueueMembership(
            queue: queue, work: first, queuedAt: Date(timeIntervalSince1970: 100)
        )
        let kept = ReadingQueueMembership(
            queue: queue, work: second, queuedAt: Date(timeIntervalSince1970: 100)
        )
        kept.lastModifiedAt = Date(timeIntervalSince1970: 900)
        context.insert(gone)
        context.insert(kept)
        try context.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            tombstones: [
                signedTombstone(.readingQueueMembership, id: gone.id, at: 400, key: peer),
                signedTombstone(.readingQueueMembership, id: kept.id, at: 400, key: peer)
            ],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        let left = try context.fetch(FetchDescriptor<ReadingQueueMembership>())
        #expect(left.compactMap { $0.work?.title } == ["Moved here since"])
    }

    /// The lesson in `applyTombstonesToExisting` holds for the new passes too:
    /// Replace does not sweep.
    @Test func replaceLibraryDoesNotSweepExistingSavedLinks() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let link = Bookmark(title: "Kept by Replace", urlString: "https://archiveofourown.org/works/3")
        link.dateAdded = Date(timeIntervalSince1970: 100)
        context.insert(link)
        try context.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [link], fonts: [], readingQueues: [],
            tombstones: [signedTombstone(.bookmark, id: link.id, at: 400, key: peer)],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .replaceLibrary)

        #expect(try context.fetch(FetchDescriptor<Bookmark>()).count == 1)
    }
}
}
