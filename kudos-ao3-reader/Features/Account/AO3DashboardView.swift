import SwiftUI

/// Native **My Dashboard** — AO3's user home (`/users/:login`), not a link dump
/// of every account URL.
///
/// On the website the page shows your header plus Fandoms, Recent works, Recent
/// series, and Recent bookmarks (`users/_contents.html.erb`). In Kudos that is
/// the same surface as your own author profile: fandoms, works, series, and
/// bookmarks, loaded from the same dashboard/header endpoints.
///
/// Sidebar destinations that sit *beside* Dashboard on AO3 (Preferences, Inbox,
/// History, Drafts, challenges, …) stay reachable from Account's Reading /
/// Writing / Activity tabs, Preferences, and **More on AO3** — they are not
/// restated here as a flat menu.
struct AO3DashboardView: View {
    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        if let username = auth.username,
           let route = AO3AuthorRoute(username: username) {
            AuthorProfileView(route: route, navigationTitle: "Dashboard")
        } else {
            ContentUnavailableView {
                Label("Not signed in", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Log in to AO3 to open your dashboard.")
            }
        }
    }
}

/// Full inbox feed as a pushed destination (deep links / Account hub).
/// Same rows and fetch model as Activity › Inbox.
struct AccountInboxListView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @State private var model = AO3InboxModel()
    @State private var threadDestination: AccountInboxThreadDestination?

    var body: some View {
        List {
            AccountInboxRows(model: model, limit: nil, onOpen: openInboxItem)
        }
        .cardList()
        .navigationTitle("Inbox")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .refreshable { await model.refresh(auth: auth) }
        .task { model.activate(auth: auth) }
        .navigationDestination(item: $threadDestination) { destination in
            CommentsView(
                workID: destination.workID,
                context: AO3CommentsWorkContext(title: destination.title, authors: [])
            )
        }
    }

    private func openInboxItem(_ item: AO3InboxItem) {
        if let workID = item.workID {
            threadDestination = AccountInboxThreadDestination(
                workID: workID,
                title: item.subjectTitle
            )
        } else if let url = item.subjectURL {
            router.open(url)
        }
    }
}
