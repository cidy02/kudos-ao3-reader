import SwiftData
import SwiftUI

/// Owns the folder-sync dirty tracking and automatic up/down sync.
///
/// Kept out of `ContentView` on purpose: seven live `@Query`s there re-rendered
/// the entire `TabView` on every library mutation, which froze the tab bar's
/// Liquid Glass morph mid-flight. This view is an invisible sibling — its
/// queries only invalidate *this* observer, not the tab chrome.
struct FolderSyncObserver: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query private var folderSyncWorks: [SavedWork]
    @Query private var folderSyncBookmarks: [Bookmark]
    @Query private var folderSyncFonts: [CustomFont]
    @Query private var folderSyncCollections: [WorkCollection]
    @Query private var folderSyncQueues: [ReadingQueue]
    @Query private var folderSyncMemberships: [ReadingQueueMembership]
    @Query private var folderSyncTombstones: [SyncTombstone]

    @State private var folderSyncUpTask: Task<Void, Never>?
    @State private var lastForegroundFolderSyncAt: Date?

    /// Automatic sync triggers only run more than once a minute when the scene keeps
    /// flipping active (Control Center, quick app-switches); an explicit dirty change
    /// or a manual Sync Now still goes through immediately regardless of this gate.
    private static let foregroundSyncThrottle: TimeInterval = 60

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                await Task.yield()
                guard FolderSyncService.snapshot().autoSyncEnabled else { return }
                lastForegroundFolderSyncAt = Date()
                _ = try? await FolderSyncService.syncDown(in: modelContext)
                // Catches up anything a prior session's debounce lost to a force-quit —
                // the dirty flag is durable across launches, unlike the debounce Task.
                if FolderSyncService.snapshot().isDirty {
                    _ = try? await FolderSyncService.syncUp(in: modelContext)
                }
                #if os(iOS)
                FolderSyncBackgroundTask.scheduleNext()
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                guard FolderSyncService.snapshot().autoSyncEnabled else { return }
                switch phase {
                case .active:
                    let now = Date()
                    if let last = lastForegroundFolderSyncAt,
                       now.timeIntervalSince(last) < Self.foregroundSyncThrottle,
                       !FolderSyncService.snapshot().isDirty {
                        return
                    }
                    lastForegroundFolderSyncAt = now
                    Task { @MainActor in
                        _ = try? await FolderSyncService.syncDown(in: modelContext)
                    }
                case .inactive, .background:
                    folderSyncUpTask?.cancel()
                    #if os(iOS)
                    // Submitting right before backgrounding is the pattern most
                    // likely to actually get honored by the OS soon.
                    FolderSyncBackgroundTask.scheduleNext()
                    #endif
                    guard FolderSyncService.snapshot().isDirty else { return }
                    Task { @MainActor in
                        _ = try? await FolderSyncService.syncUp(in: modelContext)
                    }
                @unknown default:
                    break
                }
            }
            .onChange(of: folderSyncChangeToken) { _, _ in
                FolderSyncService.markDirty()
                scheduleFolderSyncUp()
            }
            // Settings that ship in the backup manifest (reader/privacy prefs) live in
            // SettingsView's own @AppStorage bindings — it marks sync dirty itself via
            // NotificationCenter since it isn't always mounted while ContentView is.
            .onReceive(NotificationCenter.default.publisher(for: .kudosSyncRelevantSettingChanged)) { _ in
                FolderSyncService.markDirty()
                scheduleFolderSyncUp()
            }
    }

    /// Fingerprint of library content that should mark the sync folder dirty.
    ///
    /// Quantizes timestamps to whole seconds so high-frequency progress stamps
    /// (if any path still advances `lastModifiedAt` mid-read) cannot reschedule
    /// a full package `syncUp` many times per second. Debounced Readium writes
    /// deliberately leave `lastModifiedAt` alone; this is a second line of defense.
    private var folderSyncChangeToken: String {
        [
            "\(folderSyncWorks.count):\(newestDate(folderSyncWorks.map(\.lastModifiedAt)))",
            "\(folderSyncBookmarks.count):\(newestDate(folderSyncBookmarks.map(\.dateAdded)))",
            "\(folderSyncFonts.count):\(newestDate(folderSyncFonts.map(\.dateAdded)))",
            "\(folderSyncCollections.count):\(newestDate(folderSyncCollections.map(\.lastModifiedAt)))",
            "\(folderSyncQueues.count):\(newestDate(folderSyncQueues.map(\.dateUpdated)))",
            "\(folderSyncMemberships.count):\(newestDate(folderSyncMemberships.map(\.lastModifiedAt)))",
            "\(folderSyncTombstones.count):\(newestDate(folderSyncTombstones.map(\.lastModifiedAt)))"
        ].joined(separator: "|")
    }

    private func newestDate(_ dates: [Date]) -> TimeInterval {
        // Floor to whole seconds: sub-second stamp churn is never a distinct
        // sync-worthy event for the full-package uploader.
        floor(dates.max()?.timeIntervalSince1970 ?? 0)
    }

    private func scheduleFolderSyncUp() {
        let snapshot = FolderSyncService.snapshot()
        guard snapshot.isConnected, snapshot.autoSyncEnabled else { return }
        folderSyncUpTask?.cancel()
        folderSyncUpTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await FolderSyncService.syncUp(in: modelContext)
        }
    }
}
