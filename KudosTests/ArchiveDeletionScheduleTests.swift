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
        // Soft-delete still syncs between the user's own devices; only the schedule is refused.
        #expect(survivor.isPendingDeletion)
        let scheduledAt = try #require(survivor.permanentDeletionScheduledAt)
        #expect(scheduledAt > Date(), "the countdown must be this device's own, not the archive's")
    }

    @Test func deletionScheduleStartsAFreshLocalWindow() {
        let state = KudosBackupService.archivedDeletionState(
            incomingIsDeleted: true,
            localIsPendingDeletion: false,
            localScheduledAt: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(state.isPendingDeletion)
        #expect(state.scheduledAt == Date(timeIntervalSince1970: 1_000 + PreservedWorkService.recoveryWindow))
    }

    /// Restarting the countdown every time the flag round-trips through sync would push the
    /// sweep date out forever and the record would never actually be swept.
    @Test func deletionScheduleKeepsAnAlreadyRunningLocalCountdown() {
        let running = Date(timeIntervalSince1970: 500)
        let state = KudosBackupService.archivedDeletionState(
            incomingIsDeleted: true,
            localIsPendingDeletion: true,
            localScheduledAt: running,
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
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(!state.isPendingDeletion)
        #expect(state.scheduledAt == nil)
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
