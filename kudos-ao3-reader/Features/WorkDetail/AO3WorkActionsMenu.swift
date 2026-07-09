import SwiftUI

/// The shared "On AO3" overflow-menu content. Give Kudos, Leave a Comment, Bookmark,
/// Mark for Later, and Subscribe are **native** authenticated actions (the host
/// presents the composers + result via `.ao3WorkActions(…)`); only "Open on AO3"
/// opens the website. Used by Work Detail and the Reader so the two stay consistent.
struct AO3WorkActionsMenu: View {
    let workID: Int
    @Bindable var actions: AO3WorkActionsModel
    /// Context for the native comments screen ("View Comments"); optional so
    /// existing call sites keep working with just an id.
    var workTitle = ""
    var workAuthors: [String] = []

    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        Section("On AO3") {
            Button { actions.giveKudos(workID: workID, auth: auth) } label: {
                Label("Give Kudos", systemImage: "heart")
            }
            .disabled(actions.isWorking)

            Button { actions.startViewingComments(title: workTitle, authors: workAuthors) } label: {
                Label("View Comments", systemImage: "bubble.left.and.bubble.right")
            }

            Button { actions.startComment() } label: {
                Label("Leave a Comment", systemImage: "bubble.left")
            }

            Button { actions.startBookmark() } label: {
                Label("Bookmark on AO3", systemImage: "bookmark")
            }
            Button { actions.markForLater(workID: workID, auth: auth) } label: {
                Label("Mark for Later", systemImage: "clock.badge")
            }
            .disabled(actions.isWorking)

            Button { actions.subscribe(workID: workID, auth: auth) } label: {
                Label("Subscribe", systemImage: "bell")
            }
            .disabled(actions.isWorking)

            // Always available — opens the work on AO3 in the in-app browser.
            Button { openWeb("/works/\(workID)") } label: {
                Label("Open on AO3", systemImage: "safari")
            }
        }
    }

    private func openWeb(_ path: String) {
        if let url = URL(string: "https://archiveofourown.org\(path)") {
            router.open(url)
        }
    }
}
