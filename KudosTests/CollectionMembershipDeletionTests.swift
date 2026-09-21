import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Kudos

/// A work removed from a collection on one device should leave it on the other.
///
/// `suppressesCollectionMembership` was consulted only while walking the
/// archive's own membership list, where it declines to re-add one. Nothing ever
/// took away a membership this device already had — so the removal never
/// settled, and this device republished the membership on its next export.
///
/// The hard part is not the sweep, it is knowing which memberships are safe to
/// drop. Membership has no join model and so no timestamp of its own, which is
/// why `WorkCollection.lastMembershipChangedAt` exists: a membership chosen
/// here after the deletion elsewhere is a deliberate re-add and must survive.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct CollectionMembershipDeletionTests {
    private static let deletedElsewhereAt = Date(timeIntervalSince1970: 5_000)

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
        let name = "CollectionMembershipDeletionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func trustedPeer(_ defaults: UserDefaults) throws -> Curve25519.Signing.PrivateKey {
        let peer = TombstoneSigning.makePrivateKey()
        #expect(TombstoneTrustStore.add(TombstoneSigning.publicKeyHex(of: peer), defaults: defaults))
        return peer
    }

    private struct Local {
        let context: ModelContext
        let collection: WorkCollection
        let work: SavedWork
    }

    /// A collection holding one work, whose membership this device last chose
    /// at `chosenAt`.
    private func local(chosenAt: Date) throws -> Local {
        let context = try makeContext()
        let work = SavedWork(id: UUID(), title: "Shelved", author: "Writer")
        let collection = WorkCollection(name: "Comfort reads")
        context.insert(work)
        context.insert(collection)
        collection.works.append(work)
        work.collections.append(collection)
        collection.markMembershipChanged(chosenAt)
        try context.save()
        return Local(context: context, collection: collection, work: work)
    }

    /// The peer's backup: it still has the collection, and a signed tombstone
    /// saying this work was taken out of it.
    private func peerBackup(
        _ local: Local, key: Curve25519.Signing.PrivateKey, defaults: UserDefaults
    ) throws -> KudosBackupContents {
        let tomb = SyncTombstone(
            recordID: SyncTombstone.collectionMembershipID(
                collectionID: local.collection.id, workID: local.work.id
            ),
            recordType: .workCollectionMembership,
            createdAt: Self.deletedElsewhereAt
        )
        tomb.lastModifiedAt = Self.deletedElsewhereAt
        TombstoneSigning.sign(tomb, key: key)

        let staging = try makeContext()
        let archivedCollection = WorkCollection(name: "Comfort reads")
        archivedCollection.id = local.collection.id
        staging.insert(archivedCollection)
        try staging.save()

        return try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [],
            collections: [archivedCollection], readingQueues: [],
            tombstones: [tomb], defaults: defaults
        )
    }

    @Test func aMembershipDeletedElsewhereIsRemovedHere() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        // Chosen here BEFORE the deletion elsewhere.
        let local = try local(chosenAt: Date(timeIntervalSince1970: 1_000))

        let summary = try KudosBackupService.restore(
            try peerBackup(local, key: peer, defaults: defaults),
            into: local.context, defaults: defaults, mode: .merge
        )

        #expect(summary.removedCollectionMemberships == 1)
        #expect(local.collection.works.isEmpty)
        #expect(local.work.collections.isEmpty)
    }

    /// The guard that matters. Putting the work back here after it was removed
    /// elsewhere is a deliberate choice, and a tombstone older than that choice
    /// must not undo it.
    @Test func aMembershipChosenAfterTheDeletionSurvives() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        // Chosen here AFTER the deletion elsewhere.
        let local = try local(chosenAt: Date(timeIntervalSince1970: 9_000))

        let summary = try KudosBackupService.restore(
            try peerBackup(local, key: peer, defaults: defaults),
            into: local.context, defaults: defaults, mode: .merge
        )

        #expect(summary.removedCollectionMemberships == 0)
        #expect(local.collection.works.count == 1)
    }

    /// Replace bypasses tombstones entirely and has already made memberships
    /// match the snapshot, so the sweep must not run there as well.
    @Test func replaceDoesNotRunTheSweep() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let local = try local(chosenAt: Date(timeIntervalSince1970: 1_000))

        let summary = try KudosBackupService.restore(
            try peerBackup(local, key: peer, defaults: defaults),
            into: local.context, defaults: defaults, mode: .replaceLibrary
        )

        #expect(summary.removedCollectionMemberships == 0)
    }

    /// The archive's own clock is the only one that can see a re-add.
    ///
    /// The other device removed the work, then put it back. Both events are
    /// newer than this device's last membership choice, so the walk over the
    /// archive's list correctly re-added it — and then the sweep, which judges
    /// against the LOCAL clock, deleted it again in the same pass. Every
    /// subsequent sync repeated the deletion, so the re-add could never land.
    @Test func aReAddTheArchiveVouchesForSurvivesTheSweep() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        // This device last chose these contents long before either event.
        let local = try local(chosenAt: Date(timeIntervalSince1970: 1_000))

        let tomb = SyncTombstone(
            recordID: SyncTombstone.collectionMembershipID(
                collectionID: local.collection.id, workID: local.work.id
            ),
            recordType: .workCollectionMembership,
            createdAt: Self.deletedElsewhereAt
        )
        tomb.lastModifiedAt = Self.deletedElsewhereAt
        TombstoneSigning.sign(tomb, key: peer)

        // The archive puts the work back, after the removal it carries.
        let staging = try makeContext()
        let archivedWork = SavedWork(id: local.work.id, title: "Shelved", author: "Writer")
        let archivedCollection = WorkCollection(name: "Comfort reads")
        archivedCollection.id = local.collection.id
        staging.insert(archivedWork)
        staging.insert(archivedCollection)
        archivedCollection.works.append(archivedWork)
        archivedWork.collections.append(archivedCollection)
        archivedCollection.markMembershipChanged(Date(timeIntervalSince1970: 9_000))
        try staging.save()

        let summary = try KudosBackupService.restore(
            try KudosBackupService.makeContents(
                works: [archivedWork], bookmarks: [], fonts: [],
                collections: [archivedCollection], readingQueues: [],
                tombstones: [tomb], defaults: defaults
            ),
            into: local.context, defaults: defaults, mode: .merge
        )

        #expect(summary.removedCollectionMemberships == 0)
        #expect(local.collection.works.count == 1)
    }

    /// `lastMembershipChangedAt` answers "when did this device's reader last
    /// choose what is in this collection". Renaming or recolouring it is not
    /// an answer to that question, and stamping the clock there made a
    /// cosmetic edit outrank a removal made on another device — undoing it,
    /// and republishing the membership so the other device took it back too.
    @Test func renamingACollectionDoesNotOverrideARemovalElsewhere() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let local = try local(chosenAt: Date(timeIntervalSince1970: 1_000))

        // What the rename sheet and the colour picker do, long after the
        // removal the peer's tombstone records. This stands in for the call
        // sites rather than driving them — the guard here is the model
        // contract they depend on: `markModified` must not answer a question
        // only `markMembershipChanged` is entitled to answer.
        let chosenAt = local.collection.lastMembershipChangedAt
        local.collection.name = "Comfort rereads"
        local.collection.markModified(Date(timeIntervalSince1970: 9_000))
        try local.context.save()
        #expect(local.collection.lastMembershipChangedAt == chosenAt)

        let summary = try KudosBackupService.restore(
            try peerBackup(local, key: peer, defaults: defaults),
            into: local.context, defaults: defaults, mode: .merge
        )

        #expect(summary.removedCollectionMemberships == 1)
        #expect(local.collection.works.isEmpty)
    }
}
}
