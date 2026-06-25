import SwiftUI

/// A native "My Dashboard" — a hub to the signed-in user's AO3 areas, all of which
/// are themselves native in-app screens. Replaces the old web fallback. Links route
/// through the host `AccountView`'s `Route` navigation destination.
struct AO3DashboardView: View {
    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        Form {
            Group {
                Section {
                    NavigationLink(value: AccountView.Route.myWorks) {
                        Label("My Works", systemImage: "doc.text")
                    }
                    NavigationLink(value: AccountView.Route.myCollections) {
                        Label("My Collections", systemImage: "square.stack")
                    }
                    NavigationLink(value: AccountView.Route.ao3Bookmarks) {
                        Label("My Bookmarks", systemImage: "bookmark")
                    }
                    NavigationLink(value: AccountView.Route.subscriptions) {
                        Label("My Subscriptions", systemImage: "bell")
                    }
                    NavigationLink(value: AccountView.Route.markedForLater) {
                        Label("Marked for Later", systemImage: "clock.badge")
                    }
                    NavigationLink(value: AccountView.Route.ao3History) {
                        Label("My History", systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text(auth.username.map { "Signed in as \($0)" } ?? "My AO3")
                } footer: {
                    Text("Your AO3 works, bookmarks, collections, subscriptions, reading "
                         + "list, and history — all in the app.")
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle("My Dashboard")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .hidesFloatingTabBar()
    }
}
