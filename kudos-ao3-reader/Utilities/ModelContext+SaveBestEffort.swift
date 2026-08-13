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
    @MainActor
    func saveBestEffort(reason: StaticString) {
        guard autosaveEnabled else { return }
        do {
            try save()
        } catch {
            Log.library.error(
                "\(String(describing: reason), privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
