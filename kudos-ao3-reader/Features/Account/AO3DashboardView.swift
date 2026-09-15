import SwiftUI

/// Native **My Dashboard** — AO3's user home (`/users/:login`), not a link dump
/// of every account URL.
///
/// On the website the page shows your header plus Fandoms, Recent works, Recent
/// series, and Recent bookmarks (`users/_contents.html.erb`). In Kudos that is
/// the dashboard composition of your own author profile: all three recent
/// groups from the one dashboard response, with explicit links to full lists.
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
            AuthorProfileView(route: route, navigationTitle: "Dashboard", showsDashboard: true)
        } else {
            ContentUnavailableView {
                Label("Not signed in", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Log in to AO3 to open your dashboard.")
            }
        }
    }
}
