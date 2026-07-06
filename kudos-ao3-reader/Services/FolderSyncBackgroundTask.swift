#if os(iOS)
import BackgroundTasks
import OSLog
import SwiftData

/// Best-effort background refresh for the Library Sync Folder feature. iOS decides
/// if/when this actually runs — it is a freshness improvement on top of the reliable
/// launch/foreground/background/debounced sync already in `FolderSyncService` and
/// `ContentView`, never a replacement for them. Requires only the standard
/// `UIBackgroundModes`/`BGTaskSchedulerPermittedIdentifiers` Info.plist capability —
/// no entitlement, no paid Apple Developer account, consistent with the rest of the
/// no-entitlement folder-sync design.
@MainActor
enum FolderSyncBackgroundTask {
    static let identifier = "devplaceholder.H17TULZJ.AO3_App_OpenSource.folderSyncRefresh"

    /// The system only honors a request roughly this far in the future or later —
    /// requesting sooner just wastes the app's limited submission budget.
    private static let minimumInterval: TimeInterval = 60 * 60

    /// Registers the task handler. Must run during `MyApp.init()`, before the scene
    /// attaches — registering later is a documented no-op/crash risk with
    /// BGTaskScheduler.
    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, container: container)
        }
    }

    /// Pure/testable: whether a background refresh is worth scheduling at all, given
    /// the same connection/auto-sync state the foreground triggers already respect.
    static func shouldSchedule(snapshot: FolderSyncSnapshot) -> Bool {
        snapshot.isConnected && snapshot.autoSyncEnabled
    }

    /// Submits (or re-submits) the next background refresh request. Safe to call
    /// repeatedly — `BGTaskScheduler` replaces any existing pending request for the
    /// same identifier rather than stacking them.
    static func scheduleNext(defaults: UserDefaults = .standard) {
        guard shouldSchedule(snapshot: FolderSyncService.snapshot(defaults: defaults)) else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.library.notice(
                "Could not schedule folder-sync background refresh: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func handle(_ task: BGAppRefreshTask, container: ModelContainer) {
        // Re-arm first, per Apple's documented pattern — a BGAppRefreshTask is
        // one-shot per submission, so the next opportunity must be requested now,
        // not only after this run finishes.
        scheduleNext()

        let context = ModelContext(container)
        let work = Task {
            defer { task.setTaskCompleted(success: true) }
            guard shouldSchedule(snapshot: FolderSyncService.snapshot()) else { return }
            // A rejected sync here (e.g. the gate is held by a foreground sync that
            // started moments ago) is not an error — it completes quietly, same as
            // any other gate-contention rejection, and the next foreground trigger
            // or background window will catch up naturally.
            _ = try? await FolderSyncService.syncNow(in: context)
            // A natural piggyback point for the other local-only housekeeping pass —
            // no reason to wait for the next launch if the app is already awake.
            PreservedWorkService.sweepExpired(in: context)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}
#endif
