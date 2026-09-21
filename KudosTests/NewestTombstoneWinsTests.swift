import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Kudos

/// A record deleted twice stays deleted for as long as the *later* deletion says.
///
/// Adoption used to key on identity alone: if this device already held a
/// tombstone for a record, an incoming one was dropped without comparing dates.
/// Since `lastModifiedAt` is the suppression key, keeping the earlier tombstone
/// keeps the narrower window — and a snapshot dated between the two deletions
/// walks straight through it and brings the record back.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct NewestTombstoneWinsTests {
    private static let earlier = Date(timeIntervalSince1970: 1_000)
    private static let between = Date(timeIntervalSince1970: 2_000)
    private static let later = Date(timeIntervalSince1970: 3_000)

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "NewestTombstoneWinsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func trustedPeer(_ defaults: UserDefaults) throws -> Curve25519.Signing.PrivateKey {
        let peer = TombstoneSigning.makePrivateKey()
        #expect(TombstoneTrustStore.add(TombstoneSigning.publicKeyHex(of: peer), defaults: defaults))
        return peer
    }

    /// This device's own earlier deletion of `workID`.
    private func localTombstone(for workID: UUID, in context: ModelContext) throws -> SyncTombstone {
        let local = SyncTombstone(
            recordID: workID, recordType: .savedWork, createdAt: Self.earlier
        )
        local.lastModifiedAt = Self.earlier
        context.insert(local)
        try context.save()
        return local
    }

    /// A peer's later deletion of the same record, signed and trusted.
    private func peerBackup(
        for workID: UUID, key: Curve25519.Signing.PrivateKey, defaults: UserDefaults
    ) throws -> KudosBackupContents {
        let peerTomb = SyncTombstone(
            recordID: workID, recordType: .savedWork, createdAt: Self.later
        )
        peerTomb.lastModifiedAt = Self.later
        TombstoneSigning.sign(peerTomb, key: key)
        return try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            tombstones: [peerTomb], defaults: defaults
        )
    }

    @Test func aLaterDeletionReplacesTheEarlierTombstone() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try makeContext()
        let workID = UUID()
        let local = try localTombstone(for: workID, in: context)

        _ = try KudosBackupService.restore(
            try peerBackup(for: workID, key: peer, defaults: defaults),
            into: context, defaults: defaults, mode: .merge
        )

        // One tombstone for the record, carrying the later date.
        let stored = try context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.recordID == workID }
        #expect(stored.count == 1)
        #expect(local.lastModifiedAt == Self.later)
    }

    /// The consequence, and the reason this matters: a snapshot taken between
    /// the two deletions must not bring the work back.
    @Test func aSnapshotBetweenTheTwoDeletionsCannotResurrectTheWork() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try makeContext()
        let workID = UUID()
        _ = try localTombstone(for: workID, in: context)

        _ = try KudosBackupService.restore(
            try peerBackup(for: workID, key: peer, defaults: defaults),
            into: context, defaults: defaults, mode: .merge
        )

        // A stale snapshot that still contains the work, dated between the two
        // deletions. Under the old identity-only rule the device held only the
        // earlier tombstone, so this date cleared it and the work came back.
        let stale = try makeContext()
        let revived = SavedWork(id: workID, title: "Deleted Twice", author: "Writer")
        revived.markModified(Self.between)
        stale.insert(revived)
        try stale.save()
        let staleBackup = try KudosBackupService.makeContents(
            works: [revived], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )

        _ = try KudosBackupService.restore(
            staleBackup, into: context, defaults: defaults, mode: .merge
        )

        let works = try context.fetch(FetchDescriptor<SavedWork>())
            .filter { $0.id == workID && !$0.isPendingDeletion }
        #expect(works.isEmpty)
    }

    /// Guard: an *older* incoming tombstone must not widen anything or replace
    /// the later one already on file.
    @Test func anOlderIncomingTombstoneLeavesTheLaterOneAlone() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try makeContext()
        let workID = UUID()

        let local = SyncTombstone(
            recordID: workID, recordType: .savedWork, createdAt: Self.later
        )
        local.lastModifiedAt = Self.later
        context.insert(local)
        try context.save()

        let olderPeer = SyncTombstone(
            recordID: workID, recordType: .savedWork, createdAt: Self.earlier
        )
        olderPeer.lastModifiedAt = Self.earlier
        TombstoneSigning.sign(olderPeer, key: peer)
        let backup = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            tombstones: [olderPeer], defaults: defaults
        )

        _ = try KudosBackupService.restore(backup, into: context, defaults: defaults, mode: .merge)

        #expect(local.lastModifiedAt == Self.later)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.recordID == workID }.count == 1)
    }
}
}
