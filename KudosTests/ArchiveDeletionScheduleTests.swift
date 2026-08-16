import Foundation
import SwiftData
import Testing
@testable import Kudos

// Nested under PersistenceGateSuites (see its doc comment): restore and sweepExpired take
// PersistenceOperationGate, a process-wide static lock, so this must serialize against the
// other gate-taking suites.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ArchiveDeletionScheduleTests {

    /// M1g. The whole-library destruction case: a `manifest.json` in the Library Sync Folder
    /// claiming every record was deleted long ago and is already past its recovery window.
    ///
    /// Before the fix, `permanentDeletionScheduledAt` was copied verbatim from the archive, so
    /// `PreservedWorkService.sweepExpired` — which runs on every launch from `ContentView`,
    /// independent of folder sync — hard-deleted the record immediately, straight through the
    /// 90-day Recently Deleted window. Zero interaction beyond having trusted the folder.
    ///
    /// Note the forged date is only an hour ahead: this survives the M1a decode clamp, which is
    /// the point — M1g is a second, independent hole, not a timestamp-ranking bug.
    @Test func forgedDeletionScheduleCannotHardDeleteAWorkOnTheNextLaunch() throws {
        let container = try container()
        let context = container.mainContext
        let workID = UUID()
        let victim = SavedWork(id: workID, title: "MY IRREPLACEABLE FIC", author: "Writer")
        context.insert(victim)
        try context.save()

        let forged = SavedWork(id: workID, title: "MY IRREPLACEABLE FIC", author: "Writer")
        forged.isPendingDeletion = true
        forged.deletedAt = .distantPast
        forged.permanentDeletionScheduledAt = .distantPast
        forged.lastModifiedAt = Date().addingTimeInterval(60 * 60)

        let contents = KudosBackupContents(manifest: KudosBackupManifest(
            works: [KudosBackupWork(work: forged)],
            bookmarks: [],
            fonts: [],
            settings: .capture(defaults: try testDefaults())
        ))
        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        // Next launch.
        PreservedWorkService.sweepExpired(in: context)

        let survivor = try #require(
            try context.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workID },
            "the forged archive hard-deleted the work — M1g has regressed"
        )
        // D8: unsigned isDeleted still hides, but must not arm the clock.
        #expect(survivor.isPendingDeletion)
        #expect(survivor.permanentDeletionScheduledAt == nil)
    }

    @Test func unsignedIncomingDeletionNeverSetsAScheduleEvenIfOneWasAlreadyRunning() {
        let running = Date(timeIntervalSince1970: 500)
        let state = KudosBackupService.archivedDeletionState(
            incomingIsDeleted: true,
            localIsPendingDeletion: true,
            localScheduledAt: running,
            hasTrustedTombstone: false,
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(state.isPendingDeletion)
        #expect(state.scheduledAt == nil)
    }

    @Test func trustedTombstoneStartsAFreshLocalWindow() {
        let state = KudosBackupService.archivedDeletionState(
            incomingIsDeleted: true,
            localIsPendingDeletion: false,
            localScheduledAt: nil,
            hasTrustedTombstone: true,
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(state.isPendingDeletion)
        #expect(state.scheduledAt == Date(timeIntervalSince1970: 1_000 + PreservedWorkService.recoveryWindow))
    }

    /// Restarting the countdown every time the flag round-trips through sync would push the
    /// sweep date out forever and the record would never actually be swept.
    @Test func trustedTombstoneKeepsAnAlreadyRunningLocalCountdown() {
        let running = Date(timeIntervalSince1970: 500)
        let state = KudosBackupService.archivedDeletionState(
            incomingIsDeleted: true,
            localIsPendingDeletion: true,
            localScheduledAt: running,
            hasTrustedTombstone: true,
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(state.scheduledAt == running)
    }

    /// The clause Grok caught me compressing out of the fix: an incoming *un*-delete must clear
    /// both fields. Recomputing `now + window` here would schedule deletion of an item another
    /// device just restored.
    @Test func incomingUndeleteClearsBothFields() {
        let state = KudosBackupService.archivedDeletionState(
            incomingIsDeleted: false,
            localIsPendingDeletion: true,
            localScheduledAt: Date(timeIntervalSince1970: 500),
            hasTrustedTombstone: true,
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(!state.isPendingDeletion)
        #expect(state.scheduledAt == nil)
    }

    @Test func restoreHidesWithoutSchedulingWhenArchiveHasNoTrustedTombstone() throws {
        UnsignedDeletionReview.shared.resetForTests()
        let container = try container()
        let context = container.mainContext
        let workID = UUID()
        let local = SavedWork(id: workID, title: "Keep Me", author: "Writer")
        local.markModified(Date(timeIntervalSince1970: 100))
        context.insert(local)
        try context.save()

        let incoming = SavedWork(id: workID, title: "Keep Me", author: "Writer")
        incoming.isPendingDeletion = true
        incoming.markModified(Date(timeIntervalSince1970: 200))
        let contents = KudosBackupContents(manifest: KudosBackupManifest(
            works: [KudosBackupWork(work: incoming)],
            bookmarks: [],
            fonts: [],
            settings: .capture(defaults: try testDefaults())
        ))
        let summary = try KudosBackupService.restore(
            contents, into: context, defaults: try testDefaults()
        )

        let stored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(stored.isPendingDeletion)
        #expect(stored.permanentDeletionScheduledAt == nil)
        #expect(summary.unsignedHidesApplied == 1)
        #expect(summary.unsignedHidesHeld == 0)
    }

    @Test func restoreSchedulesWhenArchiveCarriesAMatchingAdoptedTombstone() throws {
        UnsignedDeletionReview.shared.resetForTests()
        let defaults = try testDefaults()
        let peer = TombstoneSigning.makePrivateKey()
        #expect(TombstoneTrustStore.add(TombstoneSigning.publicKeyHex(of: peer), defaults: defaults))

        let container = try container()
        let context = container.mainContext
        let workID = UUID()
        let local = SavedWork(id: workID, title: "Deleted For Real", author: "Writer")
        local.ao3WorkID = 8_001
        local.sourceURL = "https://archiveofourown.org/works/8001"
        local.markModified(Date(timeIntervalSince1970: 100))
        context.insert(local)
        try context.save()

        let incoming = SavedWork(id: workID, title: "Deleted For Real", author: "Writer")
        incoming.ao3WorkID = 8_001
        incoming.sourceURL = "https://archiveofourown.org/works/8001"
        incoming.isPendingDeletion = true
        incoming.markModified(Date(timeIntervalSince1970: 200))
        let tomb = SyncTombstone(
            recordID: workID,
            recordType: .savedWork,
            sourceURL: "https://archiveofourown.org/works/8001",
            ao3WorkID: 8_001,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        TombstoneSigning.sign(tomb, key: peer)
        let contents = try KudosBackupService.makeContents(
            works: [incoming],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            tombstones: [tomb],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(contents, into: context, defaults: defaults)

        let stored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(stored.isPendingDeletion)
        #expect(stored.permanentDeletionScheduledAt != nil)
    }

    @Test func sweepReconcilesPrefixedUnsignedScheduleWithoutClearingHide() throws {
        let container = try container()
        let context = container.mainContext
        let work = SavedWork(title: "Already Hidden", author: "Writer")
        work.ao3WorkID = 8_002
        work.sourceURL = "https://archiveofourown.org/works/8002"
        work.isPendingDeletion = true
        work.deletedAt = Date(timeIntervalSince1970: 50)
        work.permanentDeletionScheduledAt = Date(timeIntervalSinceNow: -1)
        context.insert(work)
        try context.save()

        let removed = PreservedWorkService.sweepExpired(in: context)

        #expect(removed == 0)
        let stored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(stored.permanentDeletionScheduledAt == nil)
        // Hide state is not this test's contract — it must remain whatever it was.
        #expect(stored.isPendingDeletion)
    }

    @Test func sweepKeepsAScheduleBackedByALocalTombstone() throws {
        let container = try container()
        let context = container.mainContext
        let work = SavedWork(title: "User Deleted", author: "Writer")
        work.ao3WorkID = 8_003
        work.sourceURL = "https://archiveofourown.org/works/8003"
        context.insert(work)
        try context.save()
        PreservedWorkService.softDelete(work, in: context)
        work.permanentDeletionScheduledAt = Date(timeIntervalSinceNow: 86_400)
        try context.save()

        let removed = PreservedWorkService.sweepExpired(in: context)

        #expect(removed == 0)
        #expect(work.permanentDeletionScheduledAt != nil)
        #expect(work.isPendingDeletion)
    }

    @Test func restoreHoldsTenUnsignedHidesAndAppliesNone() throws {
        UnsignedDeletionReview.shared.resetForTests()
        let container = try container()
        let context = container.mainContext
        var locals: [SavedWork] = []
        var incoming: [SavedWork] = []
        for index in 0..<10 {
            let id = UUID()
            let local = SavedWork(id: id, title: "Victim \(index)", author: "Writer")
            local.markModified(Date(timeIntervalSince1970: 100))
            context.insert(local)
            locals.append(local)
            let remote = SavedWork(id: id, title: "Victim \(index)", author: "Writer")
            remote.isPendingDeletion = true
            remote.markModified(Date(timeIntervalSince1970: 200))
            incoming.append(remote)
        }
        try context.save()

        let contents = KudosBackupContents(manifest: KudosBackupManifest(
            works: incoming.map(KudosBackupWork.init),
            bookmarks: [],
            fonts: [],
            settings: .capture(defaults: try testDefaults())
        ))
        let summary = try KudosBackupService.restore(
            contents, into: context, defaults: try testDefaults()
        )

        #expect(summary.unsignedHidesHeld == 10)
        #expect(summary.unsignedHidesApplied == 0)
        let stored = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(stored.allSatisfy { !$0.isPendingDeletion })
        #expect(stored.allSatisfy { $0.permanentDeletionScheduledAt == nil })
    }

    @Test func restoreAppliesNineUnsignedHidesWithoutScheduling() throws {
        UnsignedDeletionReview.shared.resetForTests()
        let container = try container()
        let context = container.mainContext
        var incoming: [SavedWork] = []
        for index in 0..<9 {
            let id = UUID()
            let local = SavedWork(id: id, title: "Quiet \(index)", author: "Writer")
            local.markModified(Date(timeIntervalSince1970: 100))
            context.insert(local)
            let remote = SavedWork(id: id, title: "Quiet \(index)", author: "Writer")
            remote.isPendingDeletion = true
            remote.markModified(Date(timeIntervalSince1970: 200))
            incoming.append(remote)
        }
        try context.save()

        let contents = KudosBackupContents(manifest: KudosBackupManifest(
            works: incoming.map(KudosBackupWork.init),
            bookmarks: [],
            fonts: [],
            settings: .capture(defaults: try testDefaults())
        ))
        let summary = try KudosBackupService.restore(
            contents, into: context, defaults: try testDefaults()
        )

        #expect(summary.unsignedHidesApplied == 9)
        #expect(summary.unsignedHidesHeld == 0)
        let stored = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(stored.count == 9)
        #expect(stored.allSatisfy(\.isPendingDeletion))
        #expect(stored.allSatisfy { $0.permanentDeletionScheduledAt == nil })
    }

    @Test func restoreHidesCollectionWithoutSchedulingWhenUnsigned() throws {
        UnsignedDeletionReview.shared.resetForTests()
        let container = try container()
        let context = container.mainContext
        let collectionID = UUID()
        let local = WorkCollection(name: "Shelf")
        local.id = collectionID
        local.markModified(Date(timeIntervalSince1970: 100))
        context.insert(local)
        try context.save()

        let incoming = WorkCollection(name: "Shelf")
        incoming.id = collectionID
        incoming.isPendingDeletion = true
        incoming.markModified(Date(timeIntervalSince1970: 200))
        let contents = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [],
            collections: [incoming],
            readingQueues: [],
            defaults: try testDefaults()
        )
        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let stored = try #require(try context.fetch(FetchDescriptor<WorkCollection>()).first)
        #expect(stored.isPendingDeletion)
        #expect(stored.permanentDeletionScheduledAt == nil)
    }

    private func container() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "ArchiveDeletionScheduleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
}
