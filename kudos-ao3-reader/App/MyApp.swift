import SwiftData
import SwiftUI

@main struct MyApp: App {
    /// Built explicitly (rather than via the `.modelContainer(for:)` scene-modifier
    /// convenience) so the same container can also be handed to
    /// `FolderSyncBackgroundTask.register(container:)`, which — per Apple's
    /// documented requirement — must happen during `init()`, before the scene
    /// attaches, not from inside `body`.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
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
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.sharedModelContainer)
    }
}
