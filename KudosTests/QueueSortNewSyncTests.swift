import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Kudos

// Nested under PersistenceGateSuites: `KudosBackupService.restore` acquires
// `PersistenceOperationGate`, so two-device reconcile tests serialize here.
extension PersistenceGateSuites {
    @MainActor
    @Suite(.serialized)
    struct QueueSortNewSyncTests {
        private func makeContext() throws -> ModelContext {
            let schema = Schema([
                SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
                ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
                QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
                ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
            ])
            return ModelContext(try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            ))
        }

        private func makeDefaults() throws -> UserDefaults {
            let suite = "QueueSortNewSyncTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.removePersistentDomain(forName: suite)
            return defaults
        }

        private func exportSnapshot(
            from context: ModelContext,
            defaults: UserDefaults
        ) throws -> KudosBackupContents {
            try KudosBackupService.makeContents(
                works: try context.fetch(FetchDescriptor<SavedWork>()),
                bookmarks: [],
                fonts: [],
                readingQueues: try context.fetch(FetchDescriptor<ReadingQueue>()),
                savedSearches: [],
                tombstones: try context.fetch(FetchDescriptor<SyncTombstone>()),
                defaults: defaults
            )
        }

        private struct SeededQueue {
            let queue: ReadingQueue
            let work: SavedWork
            let membership: ReadingQueueMembership
        }

        private func seedInitialQueue(
            in context: ModelContext,
            saved: Bool,
            at stamp: Date
        ) throws -> SeededQueue {
            let queue = ReadingQueue(name: "Sync Queue", dateCreated: stamp, dateUpdated: stamp)
            context.insert(queue)
            let work = SavedWork(title: "Synced Work", author: "Author")
            work.sourceURL = "https://archiveofourown.org/works/52901"
            work.ao3WorkID = 52901
            work.chapters = "1/1"
            work.isComplete = true
            work.isSaved = saved
            work.dateAdded = stamp
            work.createdAt = stamp
            work.lastModifiedAt = stamp
            context.insert(work)
            let origin = ReadingQueueMembershipOrigin(kind: .search, searchID: UUID(), label: "Sync search")
            let membership = ReadingQueueService.add(work, to: queue, state: .new, origin: origin, in: context)
            membership.queuedAt = stamp
            membership.lastModifiedAt = stamp
            queue.dateUpdated = stamp
            queue.lastMembershipChangedAt = stamp
            work.lastModifiedAt = stamp
            try context.save()
            return SeededQueue(queue: queue, work: work, membership: membership)
        }

        @Test func dropThenReconcileThenUndoThenReconcileRevivesAcrossDevices() throws {
            let previousNow = TombstoneSigning.now
            defer { TombstoneSigning.now = previousNow }

            let t0 = Date().addingTimeInterval(-180)
            let t1 = Date().addingTimeInterval(-60)
            let defaultsA = try makeDefaults()
            let defaultsB = try makeDefaults()
            let deviceA = try makeContext()
            let deviceB = try makeContext()

            let seeded = try seedInitialQueue(in: deviceA, saved: false, at: t0)
            let queueA = seeded.queue
            let workA = seeded.work
            let membershipA = seeded.membership
            let initialBackup = try exportSnapshot(from: deviceA, defaults: defaultsA)
            _ = try KudosBackupService.restore(initialBackup, into: deviceB, defaults: defaultsB, mode: .reconcile)

            var session = QueueSortSession(queueID: queueA.id, membershipIDs: [membershipA.id])
            TombstoneSigning.now = { t1 }
            #expect(QueueSortNew.apply(.drop, session: &session, queue: queueA, context: deviceA))
            #expect(FolderSyncService.snapshot().isDirty)
            TombstoneSigning.now = previousNow

            let afterDrop = try exportSnapshot(from: deviceA, defaults: defaultsA)
            _ = try KudosBackupService.restore(afterDrop, into: deviceB, defaults: defaultsB, mode: .reconcile)

            let workB = try #require(try deviceB.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workA.id })
            #expect(workB.isPendingDeletion)
            #expect(workB.queueMemberships.isEmpty)

            // Undo on A, then reconcile onto B: both work and membership revive.
            let undoResult = QueueSortNew.undo(session: &session, queue: queueA, context: deviceA)
            #expect(undoResult.undoneRecord?.action == .drop)

            let afterUndo = try exportSnapshot(from: deviceA, defaults: defaultsA)
            _ = try KudosBackupService.restore(afterUndo, into: deviceB, defaults: defaultsB, mode: .reconcile)

            let revivedWorkB = try #require(
                try deviceB.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workA.id }
            )
            #expect(!revivedWorkB.isPendingDeletion)
            let revivedMembershipB = try #require(
                revivedWorkB.queueMemberships.first { $0.id == membershipA.id }
            )
            #expect(revivedMembershipB.state == .new)
            #expect(revivedMembershipB.origin?.label == "Sync search")
        }

        @Test func undoDropRefusesAndNeverResurrectsWhenPeerDeletesLibraryWork() throws {
            let previousNow = TombstoneSigning.now
            defer { TombstoneSigning.now = previousNow }

            let t0 = Date().addingTimeInterval(-180)
            let t1 = Date().addingTimeInterval(-60)
            let defaultsA = try makeDefaults()
            let defaultsB = try makeDefaults()
            let peerKey = TombstoneSigning.makePrivateKey()
            #expect(TombstoneTrustStore.add(TombstoneSigning.publicKeyHex(of: peerKey), defaults: defaultsA))

            let deviceA = try makeContext()
            let deviceB = try makeContext()
            let seeded = try seedInitialQueue(in: deviceA, saved: true, at: t0)
            let queueA = seeded.queue
            let workA = seeded.work
            let membershipA = seeded.membership
            let initial = try exportSnapshot(from: deviceA, defaults: defaultsA)
            _ = try KudosBackupService.restore(initial, into: deviceB, defaults: defaultsB, mode: .reconcile)

            // A drops the Library work at t1 (work stays live on A).
            var session = QueueSortSession(queueID: queueA.id, membershipIDs: [membershipA.id])
            TombstoneSigning.now = { t1 }
            #expect(QueueSortNew.apply(.drop, session: &session, queue: queueA, context: deviceA))
            workA.lastModifiedAt = t1
            try deviceA.save()
            TombstoneSigning.now = previousNow

            // Peer B explicitly deletes the Library work at t2 > t1 (signed by peerKey).
            let t2 = Date()
            let workB = try #require(try deviceB.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workA.id })
            workB.isPendingDeletion = true
            workB.deletedAt = t2
            workB.permanentDeletionScheduledAt = t2.addingTimeInterval(PreservedWorkService.recoveryWindow)
            workB.markModified(t2)
            let peerTombstone = SyncTombstone(
                recordID: workB.id,
                recordType: .savedWork,
                sourceURL: WorkTags.canonicalAO3WorkURL(from: workB.sourceURL) ?? workB.sourceURL,
                ao3WorkID: workB.ao3WorkID,
                createdAt: t2,
                deletedOnDeviceID: "peer-device",
                deletionReason: "workDeleted"
            )
            TombstoneSigning.sign(peerTombstone, key: peerKey)
            deviceB.insert(peerTombstone)
            try deviceB.save()

            // A reconciles B's deletion, then attempts Undo of Drop -> must be blocked.
            let peerBackup = try exportSnapshot(from: deviceB, defaults: defaultsB)
            _ = try KudosBackupService.restore(peerBackup, into: deviceA, defaults: defaultsA, mode: .reconcile)
            #expect(workA.isPendingDeletion)
            let modifiedAfterSync = workA.lastModifiedAt

            let outcome = QueueSortNew.undo(session: &session, queue: queueA, context: deviceA)
            if case .blocked = outcome {} else { Issue.record("Expected blocked Undo after peer work deletion") }
            #expect(workA.isPendingDeletion)
            #expect(workA.lastModifiedAt == modifiedAfterSync)
            #expect(workA.queueMemberships.isEmpty)

            // Syncing A back to B (even after B hard-deletes) must never resurrect workB.
            PreservedWorkService.deletePermanently(workB, in: deviceB)
            let afterRefusedUndo = try exportSnapshot(from: deviceA, defaults: defaultsA)
            _ = try KudosBackupService.restore(afterRefusedUndo, into: deviceB, defaults: defaultsB, mode: .reconcile)
            let liveOnB = try deviceB.fetch(FetchDescriptor<SavedWork>())
                .filter { $0.id == workA.id && !$0.isPendingDeletion }
            #expect(liveOnB.isEmpty)
        }

        @Test func undoDropRefusesWhenPeerRestoresAndReDeletesQueueOnlyWork() throws {
            let previousNow = TombstoneSigning.now
            defer { TombstoneSigning.now = previousNow }

            let t0 = Date().addingTimeInterval(-180)
            let t1 = Date().addingTimeInterval(-60)
            let defaultsA = try makeDefaults()
            let defaultsB = try makeDefaults()
            let peerKey = TombstoneSigning.makePrivateKey()
            let peerPub = TombstoneSigning.publicKeyHex(of: peerKey)
            #expect(TombstoneTrustStore.add(peerPub, defaults: defaultsA))

            let deviceA = try makeContext()
            let deviceB = try makeContext()
            let seeded = try seedInitialQueue(in: deviceA, saved: false, at: t0)
            let queueA = seeded.queue
            let workA = seeded.work
            let membershipA = seeded.membership
            let initial = try exportSnapshot(from: deviceA, defaults: defaultsA)
            _ = try KudosBackupService.restore(initial, into: deviceB, defaults: defaultsB, mode: .reconcile)

            // A drops queue-only work at t1 (sentWorkToRecentlyDeleted == true).
            var session = QueueSortSession(queueID: queueA.id, membershipIDs: [membershipA.id])
            TombstoneSigning.now = { t1 }
            #expect(QueueSortNew.apply(.drop, session: &session, queue: queueA, context: deviceA))
            TombstoneSigning.now = previousNow

            // Sync A's drop to B.
            let dropBackup = try exportSnapshot(from: deviceA, defaults: defaultsA)
            _ = try KudosBackupService.restore(dropBackup, into: deviceB, defaults: defaultsB, mode: .reconcile)

            // B restores then explicitly deletes the work at t2 > t1 with peerKey.
            let workB = try #require(try deviceB.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workA.id })
            PreservedWorkService.restore(workB, in: deviceB)
            let t2 = Date()
            workB.isPendingDeletion = true
            workB.deletedAt = t2
            workB.permanentDeletionScheduledAt = t2.addingTimeInterval(PreservedWorkService.recoveryWindow)
            workB.markModified(t2)
            let peerWorkTombstone = SyncTombstone(
                recordID: workB.id,
                recordType: .savedWork,
                sourceURL: WorkTags.canonicalAO3WorkURL(from: workB.sourceURL) ?? workB.sourceURL,
                ao3WorkID: workB.ao3WorkID,
                createdAt: t2,
                deletedOnDeviceID: "peer-device",
                deletionReason: "workDeleted"
            )
            TombstoneSigning.sign(peerWorkTombstone, key: peerKey)
            deviceB.insert(peerWorkTombstone)
            try deviceB.save()

            // A reconciles B's newer delete (updates A's tombstone in place).
            let peerDeleteBackup = try exportSnapshot(from: deviceB, defaults: defaultsB)
            _ = try KudosBackupService.restore(peerDeleteBackup, into: deviceA, defaults: defaultsA, mode: .reconcile)

            // Undo on A must refuse and leave peer's tombstone intact.
            let outcome = QueueSortNew.undo(session: &session, queue: queueA, context: deviceA)
            if case .blocked = outcome {} else { Issue.record("Expected blocked Undo after peer re-delete") }
            #expect(workA.isPendingDeletion)
            #expect(workA.queueMemberships.isEmpty)
            let remainingWorkTombstones = try deviceA.fetch(FetchDescriptor<SyncTombstone>())
                .filter { $0.recordType == .savedWork && $0.recordID == workA.id }
            #expect(remainingWorkTombstones.count == 1)
            #expect(remainingWorkTombstones.first?.signerPublicKey == peerPub)

            // Syncing A back to B must not resurrect workB.
            let afterRefusedUndo = try exportSnapshot(from: deviceA, defaults: defaultsA)
            _ = try KudosBackupService.restore(afterRefusedUndo, into: deviceB, defaults: defaultsB, mode: .reconcile)
            #expect(workB.isPendingDeletion)
        }

        @Test func undoDropRefusesWhenForeignMembershipTombstoneSupersedesDrop() throws {
            let previousNow = TombstoneSigning.now
            defer { TombstoneSigning.now = previousNow }

            let t0 = Date().addingTimeInterval(-180)
            let t1 = Date().addingTimeInterval(-60)
            let defaultsA = try makeDefaults()
            let defaultsB = try makeDefaults()
            let peerKey = TombstoneSigning.makePrivateKey()
            let peerPub = TombstoneSigning.publicKeyHex(of: peerKey)
            #expect(TombstoneTrustStore.add(peerPub, defaults: defaultsA))

            let deviceA = try makeContext()
            let deviceB = try makeContext()
            let seeded = try seedInitialQueue(in: deviceA, saved: true, at: t0)
            let queueA = seeded.queue
            let membershipA = seeded.membership
            let initial = try exportSnapshot(from: deviceA, defaults: defaultsA)
            _ = try KudosBackupService.restore(initial, into: deviceB, defaults: defaultsB, mode: .reconcile)

            var session = QueueSortSession(queueID: queueA.id, membershipIDs: [membershipA.id])
            TombstoneSigning.now = { t1 }
            #expect(QueueSortNew.apply(.drop, session: &session, queue: queueA, context: deviceA))
            TombstoneSigning.now = previousNow

            // Peer B also removed the same membership id at t2 > t1.
            let t2 = Date()
            let peerMembershipTombstone = SyncTombstone(
                recordID: membershipA.id,
                recordType: .readingQueueMembership,
                createdAt: t2,
                deletedOnDeviceID: "peer-device",
                deletionReason: "queueMembershipRemoved"
            )
            TombstoneSigning.sign(peerMembershipTombstone, key: peerKey)
            deviceB.insert(peerMembershipTombstone)
            try deviceB.save()

            let peerBackup = try exportSnapshot(from: deviceB, defaults: defaultsB)
            _ = try KudosBackupService.restore(peerBackup, into: deviceA, defaults: defaultsA, mode: .reconcile)

            let outcome = QueueSortNew.undo(session: &session, queue: queueA, context: deviceA)
            if case .blocked = outcome {} else {
                Issue.record("Expected blocked Undo when foreign membership tombstone superseded Drop")
            }
            #expect(QueueSortNew.membership(membershipA.id, in: queueA) == nil)
            let tombstones = try deviceA.fetch(FetchDescriptor<SyncTombstone>())
                .filter { $0.recordType == .readingQueueMembership && $0.recordID == membershipA.id }
            #expect(tombstones.count == 1)
            #expect(tombstones.first?.signerPublicKey == peerPub)
        }
    }
}
