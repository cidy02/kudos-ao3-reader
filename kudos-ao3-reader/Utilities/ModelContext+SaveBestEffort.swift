import Foundation
import OSLog
import SwiftData

extension ModelContext {
    /// Saves, logging (not throwing) on failure — the app's convention for
    /// derived/background state changes where a save failure shouldn't block
    /// the user's action or crash the flow that triggered it.
    /// **Skipped entirely when `autosaveEnabled == false`.** That flag is this codebase's
    /// signal that some caller has taken explicit ownership of the commit boundary, and a
    /// best-effort save must not preempt it.
    ///
    /// This is load-bearing for M15a/M20, not a tidiness rule. `KudosBackupService.restore`
    /// runs a whole merge and commits only on success, so that a rejected hostile archive
    /// leaves no trace. But restore calls `ReadingQueueService.ensureSavedForLaterQueue`,
    /// `normalizeAllQueuedWorks` and `replaceEPUB`, and each of those ends in a
    /// `saveBestEffort` — which committed partial merge state mid-restore and defeated the
    /// boundary. Disabling autosave alone did not help: autosave and an explicit `save()`
    /// are different mechanisms, and only the first was switched off. Measured: with the
    /// isolated context in place and this guard absent, a *failed* restore still left the
    /// archive's title, author, tags and a reading queue committed.
    /// Returns whether the change is now persisted, so a caller on a
    /// data-integrity path can tell the reader when it is not.
    ///
    /// `@discardableResult` deliberately: this has 58 call sites and most are
    /// ordinary edits where logging is the right response. Only the destructive
    /// and restore paths need to look — a restore that says "done" and did not
    /// save is how a work stays scheduled for permanent deletion while the
    /// reader believes they rescued it.
    ///
    /// `true` when `autosaveEnabled` is off: that is not a failure, it is a
    /// transaction deliberately holding its one commit point (see above), and
    /// the enclosing `restore` owns the result.
    @MainActor
    @discardableResult
    func saveBestEffort(reason: StaticString) -> Bool {
        guard autosaveEnabled else { return true }
        do {
            try save()
            return true
        } catch {
            Log.library.error(
                "\(String(describing: reason), privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
