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

    /// Audit A27-3. The copy here was deleted on the other device, which has since made
    /// its own mark on the same passage. Swept after the dedupe, the copy here first won
    /// the passage (the other device's mark was deleted and tombstoned as a duplicate)
    /// and was then removed itself: both marks gone, on both devices.
    @Test func aDeletedCopyDoesNotTakeTheOtherDevicesMarkOnTheSamePassageWithIt() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let workID = UUID()
        let work = SavedWork(id: workID, title: "A work", author: "Someone")
        work.isSaved = true
        context.insert(work)
        let local = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: "passage", note: "deleted elsewhere",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        local.lastModifiedAt = Date(timeIntervalSince1970: 300)
        context.insert(local)
        try context.save()

        let donor = try self.context()
        let donorWork = SavedWork(id: workID, title: "A work", author: "Someone")
        donorWork.isSaved = true
        donorWork.hasEPUB = false
        donor.insert(donorWork)
        let remote = ReadingAnnotation(
            work: donorWork, kind: .highlight, locatorString: "passage", note: "made since",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        remote.lastModifiedAt = Date(timeIntervalSince1970: 100)
        donor.insert(remote)
        try donor.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [donorWork], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [remote],
            tombstones: [signedTombstone(.readingAnnotation, id: local.id, at: 400, key: peer)],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        let live = try context.fetch(FetchDescriptor<ReadingAnnotation>())
            .filter { !$0.isPendingDeletion && $0.deletedAt == nil }
        #expect(live.map(\.note) == ["made since"])
    }

    private func work(_ id: UUID, in context: ModelContext) -> SavedWork {
        let work = SavedWork(id: id, title: "A work", author: "Someone")
        work.isSaved = true
        work.hasEPUB = false
        context.insert(work)
        return work
    }

    private func mark(
        _ id: UUID = UUID(), on work: SavedWork, note: String, modifiedAt: TimeInterval, in context: ModelContext
    ) -> ReadingAnnotation {
        let mark = ReadingAnnotation(
            id: id, work: work, kind: .highlight, locatorString: "passage", note: note,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        mark.lastModifiedAt = Date(timeIntervalSince1970: modifiedAt)
        context.insert(mark)
        return mark
    }

    private func liveNotes(_ context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<ReadingAnnotation>())
            .filter { !$0.isPendingDeletion && $0.deletedAt == nil }
            .map(\.note)
    }

    /// Audit A30-3. Replace keeps the snapshot's mark. A newer mark here on the same
    /// passage, which the snapshot does not list and Replace is about to hide, used to
    /// win the passage first: the snapshot's mark was deleted as its duplicate and then
    /// the winner was hidden, so no mark was left.
    @Test func replaceKeepsTheSnapshotsMarkAgainstANewerLocalOneOnTheSamePassage() throws {
        let defaults = try testDefaults()
        let context = try context()
        let workID = UUID()
        _ = mark(on: work(workID, in: context), note: "only here", modifiedAt: 300, in: context)
        try context.save()

        let donor = try self.context()
        let donorWork = work(workID, in: donor)
        let remote = mark(on: donorWork, note: "in the snapshot", modifiedAt: 100, in: donor)
        try donor.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [donorWork], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [remote], defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .replaceLibrary)

        #expect(try liveNotes(context) == ["in the snapshot"])
        // The mark Replace hid is still stored, and nothing says the snapshot's was deleted.
        let stored = try context.fetch(FetchDescriptor<ReadingAnnotation>()).map(\.note)
        let deletions = try context.fetch(FetchDescriptor<SyncTombstone>()).map(\.recordID)
        #expect(stored.contains("only here"))
        #expect(!deletions.contains(remote.id))
    }

    /// Audit A30-4. The mark was deleted on the other device and then brought back
    /// there, newer than the deletion. Merge skipped it because this device still had
    /// the old copy, then swept the old copy as deleted: neither was left.
    @Test func mergeTakesAMarkBroughtBackAfterItsDeletionWhenTheCopyHereIsTheDeletedOne() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let workID = UUID()
        let markID = UUID()
        _ = mark(markID, on: work(workID, in: context), note: "before the deletion", modifiedAt: 300, in: context)
        try context.save()

        let donor = try self.context()
        let donorWork = work(workID, in: donor)
        let revived = mark(markID, on: donorWork, note: "brought back", modifiedAt: 500, in: donor)
        try donor.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [donorWork], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [revived],
            tombstones: [signedTombstone(.readingAnnotation, id: markID, at: 400, key: peer)],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        #expect(try liveNotes(context) == ["brought back"])
        // The text it replaced is parked on a hidden row, not destroyed.
        let hidden = try context.fetch(FetchDescriptor<ReadingAnnotation>())
            .filter { $0.isPendingDeletion || $0.deletedAt != nil }
        #expect(hidden.map(\.note) == ["before the deletion"])
    }

    /// Merge stays add-only for a mark nobody deleted: the copy here is not overwritten.
    /// A guardrail on the exception above, not a test of a fault: it passed before A30-4's
    /// fix too (review A32-13).
    @Test func mergeStillLeavesALiveMarkHereAlone() throws {
        let defaults = try testDefaults()
        let context = try context()
        let workID = UUID()
        let markID = UUID()
        _ = mark(markID, on: work(workID, in: context), note: "mine", modifiedAt: 300, in: context)
        try context.save()

        let donor = try self.context()
        let donorWork = work(workID, in: donor)
        let other = mark(markID, on: donorWork, note: "theirs, newer", modifiedAt: 500, in: donor)
        try donor.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [donorWork], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [other], defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        #expect(try liveNotes(context) == ["mine"])
    }

    /// Audit A27-11. Removing every Account shortcut is a choice and stays one; only a
    /// value never written means the defaults. (Here because it needs no file of its own.)
    @Test func choosingNoAccountShortcutsStaysEmpty() {
        #expect(AccountShortcutStore.decode(AccountShortcutStore.encode([])).isEmpty)
        #expect(AccountShortcutStore.decode("") == AccountShortcut.defaults)
        #expect(AccountShortcutStore.decode("nothing-known") == AccountShortcut.defaults)
        #expect(AccountShortcutStore.decode(AccountShortcutStore.encode([.inbox, .works])) == [.inbox, .works])
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
