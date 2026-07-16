import SwiftUI

/// Long-tail AO3 destinations that open in Browse. These are the sidebar
/// destinations that sit *beside* Dashboard on the website (not the dashboard
/// home itself — that is `AO3DashboardView` / your author profile).
struct AccountMoreOnAO3View: View {
    var body: some View {
        List {
            Section {
                AccountExternalNavCard(
                    title: "Drafts",
                    systemImage: "doc.badge.clock",
                    pathSuffix: "works/drafts"
                )
                AccountExternalNavCard(
                    title: "Pseuds",
                    systemImage: "person.2",
                    pathSuffix: "pseuds"
                )
                AccountExternalNavCard(
                    title: "Skins",
                    systemImage: "paintpalette",
                    pathSuffix: "skins"
                )
                AccountExternalNavCard(
                    title: "Statistics",
                    systemImage: "chart.bar",
                    pathSuffix: "stats"
                )
            } header: {
                Text("Creator tools")
            } footer: {
                Text("These open your AO3 pages in Browse. Native versions can land later. "
                    + "Works, series, bookmarks, history, and inbox live under Account's "
                    + "Reading, Writing, and Activity tabs.")
            }

            Section("Challenges & gifts") {
                AccountExternalNavCard(
                    title: "Co-Creator Requests",
                    systemImage: "person.badge.plus",
                    pathSuffix: "creatorships"
                )
                AccountExternalNavCard(
                    title: "Sign-ups",
                    systemImage: "pencil.and.list.clipboard",
                    pathSuffix: "signups"
                )
                AccountExternalNavCard(
                    title: "Assignments",
                    systemImage: "list.clipboard",
                    pathSuffix: "assignments"
                )
                AccountExternalNavCard(
                    title: "Claims",
                    systemImage: "flag",
                    pathSuffix: "claims"
                )
                AccountExternalNavCard(
                    title: "Related Works",
                    systemImage: "arrow.triangle.branch",
                    pathSuffix: "related_works"
                )
                AccountExternalNavCard(
                    title: "Gifts",
                    systemImage: "gift",
                    pathSuffix: "gifts"
                )
            }
        }
        .cardList()
        .navigationTitle("More on AO3")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
    }
}
