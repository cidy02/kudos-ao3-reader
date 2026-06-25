import SwiftUI

/// The shared "On AO3" overflow-menu content. Give Kudos and Leave a Comment are now
/// **native** authenticated actions (the host presents the composer + result via
/// `.ao3WorkActions(…)`); Bookmark / Mark for Later / Subscribe remain honest web
/// fallbacks for now (they open the work on AO3 so the user completes them there).
/// Used by Work Detail and the Reader so the two surfaces stay consistent.
struct AO3WorkActionsMenu: View {
    let workID: Int
    @Bindable var actions: AO3WorkActionsModel

    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        Section("On AO3") {
            Button { actions.giveKudos(workID: workID, auth: auth) } label: {
                Label("Give Kudos", systemImage: "heart")
            }
            .disabled(actions.isWorking)

            Button { actions.startComment() } label: {
                Label("Leave a Comment", systemImage: "bubble.left")
            }

            // Still honest web fallbacks (a later pass can make these native).
            Button { openWeb("/works/\(workID)/bookmarks/new") } label: {
                Label("Bookmark on AO3", systemImage: "bookmark")
            }
            Button { openWeb("/works/\(workID)") } label: {
                Label("Mark for Later", systemImage: "clock.badge")
            }
            Button { openWeb("/works/\(workID)") } label: {
                Label("Subscribe", systemImage: "bell")
            }
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
