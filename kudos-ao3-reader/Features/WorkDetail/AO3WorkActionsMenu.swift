import SwiftUI

/// The shared "On AO3" overflow-menu content. Comments always opens the unified
/// native read/write screen; Bookmark and the other authenticated actions remain
/// native. Only "Open on AO3" opens the website.
struct AO3WorkActionsMenu: View {
    let workID: Int
    @Bindable var actions: AO3WorkActionsModel
    /// Context for the native comments screen ("Comments"); optional so
    /// existing call sites keep working with just an id.
    var workContext = AO3CommentsWorkContext(title: "", authors: [])
    /// When shown from a reader, the AO3 story chapter to open comments on so the
    /// user lands on the chapter they're reading. nil (Work Detail) → All comments.
    var commentsInitialChapterPosition: Int?

    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        Section("On AO3") {
            Button { actions.giveKudos(workID: workID, auth: auth) } label: {
                Label("Give Kudos", systemImage: "heart")
            }
            .disabled(actions.isWorking)

            Button {
                actions.startViewingComments(context: workContext,
                                             initialChapterPosition: commentsInitialChapterPosition)
            } label: {
                Label("Comments", systemImage: "bubble.left.and.bubble.right")
            }

            Button { actions.startBookmark() } label: {
                if actions.workPageStates?.existingBookmark != nil {
                    Label("Edit Bookmark on AO3", systemImage: "bookmark.fill")
                } else {
                    Label("Bookmark on AO3", systemImage: "bookmark")
                }
            }
            Button { actions.markForLater(workID: workID, auth: auth) } label: {
                Label("Mark for Later", systemImage: "clock.badge")
            }
            .disabled(actions.isWorking)

            Button { actions.subscribe(workID: workID, auth: auth) } label: {
                if actions.workPageStates?.isSubscribed == true {
                    Label("Unsubscribe", systemImage: "bell.slash")
                } else {
                    Label("Subscribe", systemImage: "bell")
                }
            }
            .disabled(actions.isWorking)

            // Always available — opens the work on AO3 in the in-app browser.
            Button { openWeb("/works/\(workID)") } label: {
                Label("Open on AO3", systemImage: "safari")
            }
        }
        // Menu content builds when the menu opens — fetch the subscribed/
        // bookmarked state then (never on plain work-detail views), so the
        // labels above reflect AO3 instead of always reading "Subscribe" /
        // "Bookmark on AO3".
        .onAppear { actions.refreshWorkPageStates(workID: workID, auth: auth) }
    }

    private func openWeb(_ path: String) {
        if let url = URL(string: "https://archiveofourown.org\(path)") {
            router.open(url)
        }
    }
}
