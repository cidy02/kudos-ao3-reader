import SwiftUI
import SwiftData

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self, SavedSearch.self])
    }
}
