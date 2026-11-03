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
    /// Fired only when this subscribe call actually subscribed (not on the
    /// unsubscribe half of the same toggle). nil at call sites with nothing to
    /// hook, such as the reader.
    var onSubscribeSuccess: (() -> Void)? = nil
    var onKudosSuccess: (() -> Void)? = nil
    var shareURL: URL? = nil
    var hasGivenKudos: Bool = false
    var showsTopRow: Bool = true

    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        if showsTopRow {
            AO3WorkActionsTopRow(
                workID: workID,
                actions: actions,
                onSubscribeSuccess: onSubscribeSuccess,
                onKudosSuccess: onKudosSuccess,
                shareURL: shareURL,
                hasGivenKudos: hasGivenKudos
            )
        }
        Section("On AO3") {
            Button {
                actions.startViewingComments(context: workContext,
                                             initialChapterPosition: commentsInitialChapterPosition)
            } label: {
                Label("Comments", systemImage: "bubble.left.and.bubble.right")
            }

            Button { actions.markForLater(workID: workID, auth: auth) } label: {
                Label("Mark for Later", systemImage: "clock.badge")
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

struct AO3WorkActionsTopRow: View {
    let workID: Int
    @Bindable var actions: AO3WorkActionsModel
    var onSubscribeSuccess: (() -> Void)?
    var onKudosSuccess: (() -> Void)?
    var shareURL: URL?
    var hasGivenKudos: Bool

    @Environment(AO3AuthService.self) private var auth
    @Environment(\.accentFill) private var accentFill

    var body: some View {
        MenuTopRow {
            let isGiven = hasGivenKudos || actions.kudosGivenWorkID == workID
            Button {
                actions.giveKudos(
                    workID: workID,
                    auth: auth,
                    onSuccess: onKudosSuccess
                )
            } label: {
                Label(
                    isGiven ? "Kudos Given" : "Kudos",
                    systemImage: MenuTopRowRules.kudosSymbol(isGiven: isGiven)
                )
            }
            .disabled(actions.isWorking || isGiven)
            .tint(isGiven ? accentFill : Color.primary)
            .accessibilityLabel(isGiven ? "Kudos given" : "Give Kudos")
            .accessibilityAddTraits(isGiven ? [.isSelected] : [])

            let isBookmarked = actions.bookmarkedWorkID == workID
                || actions.workPageStates?.existingBookmark != nil
            Button { actions.startBookmark() } label: {
                Label(
                    isBookmarked ? "Edit Bookmark" : "Bookmark",
                    systemImage: MenuTopRowRules.bookmarkSymbol(isBookmarked: isBookmarked)
                )
            }
            .tint(isBookmarked ? accentFill : Color.primary)
            .accessibilityLabel(
                isBookmarked
                    ? "Edit Bookmark on AO3" : "Bookmark on AO3"
            )
            .accessibilityAddTraits(
                isBookmarked ? [.isSelected] : []
            )

            let isSubscribed = actions.workPageStates?.isSubscribed == true
            Button {
                actions.subscribe(workID: workID, auth: auth, onSubscribed: onSubscribeSuccess)
            } label: {
                Label(
                    isSubscribed ? "Unsubscribe" : "Subscribe",
                    systemImage: MenuTopRowRules.subscribeSymbol(isSubscribed: isSubscribed)
                )
            }
            .disabled(actions.isWorking)
            .tint(isSubscribed ? accentFill : Color.primary)
            .accessibilityLabel(isSubscribed ? "Unsubscribe" : "Subscribe")
            .accessibilityAddTraits(
                isSubscribed ? [.isSelected] : []
            )

            ShareLink(item: shareURL ?? AO3AuthService.workURL(workID)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        // Menu content builds when the menu opens, so this fetch is user-driven.
        .onAppear { actions.refreshWorkPageStates(workID: workID, auth: auth) }
    }
}
