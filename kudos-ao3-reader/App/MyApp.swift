import SwiftData
import SwiftUI

@main struct MyApp: App {
    #if os(iOS)
    /// Only reason for a delegate: iOS asks it which interface orientations are
    /// supported, which is how the reader's rotation lock takes effect.
    @UIApplicationDelegateAdaptor(KudosAppDelegate.self) private var appDelegate
    #endif

    /// Built explicitly (rather than via the `.modelContainer(for:)` scene-modifier
    /// convenience) so the same container can also be handed to
    /// `FolderSyncBackgroundTask.register(container:)`, which — per Apple's
    /// documented requirement — must happen during `init()`, before the scene
    /// attaches, not from inside `body`.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        #if os(iOS)
        FolderSyncBackgroundTask.register(container: Self.sharedModelContainer)
        // iOS-only: `Kudos-iOS.entitlements` carries the KVS identifier,
        // `Kudos.entitlements` (macOS) does not. Constructing the real store
        // without that entitlement logs "BUG IN CLIENT OF KVS" and breaks
        // Keychain access in-process — see `TombstoneTrustStore.iCloudStore`.
        TombstoneTrustStore.iCloudStore = NSUbiquitousKeyValueStore.default
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.sharedModelContainer)
    }
}
