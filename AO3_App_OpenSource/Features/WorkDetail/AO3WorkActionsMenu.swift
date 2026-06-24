import SwiftUI

/// The shared "On AO3" overflow-menu content: Give Kudos, Leave a Comment, Bookmark
/// on AO3, Mark for Later, Subscribe, Open on AO3. Native AO3 *write* actions need
/// the per-page CSRF token and aren't implemented yet, so each opens the work on AO3
/// (via the Browse web fallback) — an honest fallback, never a faked success; the
/// user completes the action there (logging in on AO3 if needed). Used by Work
/// Detail and the Reader so the two surfaces stay consistent.
struct AO3WorkActionsMenu: View {
    let workID: Int

    @Environment(AppRouter.self) private var router

    var body: some View {
        Section("On AO3 (opens website)") {
            Button { open("/works/\(workID)") } label: {
                Label("Give Kudos", systemImage: "heart")
            }
            Button { open("/works/\(workID)#comments") } label: {
                Label("Leave a Comment", systemImage: "bubble.left")
            }
            Button { open("/works/\(workID)/bookmarks/new") } label: {
                Label("Bookmark on AO3", systemImage: "bookmark")
            }
            Button { open("/works/\(workID)") } label: {
                Label("Mark for Later", systemImage: "clock.badge")
            }
            Button { open("/works/\(workID)") } label: {
                Label("Subscribe", systemImage: "bell")
            }
            Button { open("/works/\(workID)") } label: {
                Label("Open on AO3", systemImage: "safari")
            }
        }
    }

    private func open(_ path: String) {
        if let url = URL(string: "https://archiveofourown.org\(path)") {
            router.open(url)
        }
    }
}
