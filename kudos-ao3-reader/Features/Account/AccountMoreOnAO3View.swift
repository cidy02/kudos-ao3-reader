import SwiftUI

/// Long-tail AO3 destinations that open in Browse. These are the sidebar
/// destinations that sit *beside* Dashboard on the website (not the dashboard
/// home itself — that is `AO3DashboardView` / your author profile).
struct AccountMoreOnAO3View: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            Section {
                externalCard(
                    title: "Drafts",
                    systemImage: "doc.badge.clock",
                    pathSuffix: "works/drafts"
                )
                externalCard(
                    title: "Pseuds",
                    systemImage: "person.2",
                    pathSuffix: "pseuds"
                )
                externalCard(
                    title: "Skins",
                    systemImage: "paintpalette",
                    pathSuffix: "skins"
                )
                externalCard(
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
                externalCard(
                    title: "Co-Creator Requests",
                    systemImage: "person.badge.plus",
                    pathSuffix: "creatorships"
                )
                externalCard(
                    title: "Sign-ups",
                    systemImage: "pencil.and.list.clipboard",
                    pathSuffix: "signups"
                )
                externalCard(
                    title: "Assignments",
                    systemImage: "list.clipboard",
                    pathSuffix: "assignments"
                )
                externalCard(
                    title: "Claims",
                    systemImage: "flag",
                    pathSuffix: "claims"
                )
                externalCard(
                    title: "Related Works",
                    systemImage: "arrow.triangle.branch",
                    pathSuffix: "related_works"
                )
                externalCard(
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

    @ViewBuilder
    private func externalCard(
        title: String,
        systemImage: String,
        pathSuffix: String
    ) -> some View {
        Button {
            openUserPath(pathSuffix)
        } label: {
            AccountNavCardLabel(
                title: title,
                systemImage: systemImage,
                opensExternally: true
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.username == nil)
        .cardRow()
    }

    private func openUserPath(_ suffix: String) {
        guard let username = auth.username else { return }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? username
        let path = "/users/\(encoded)/\(suffix)"
        guard let url = URL(string: "https://archiveofourown.org\(path)") else { return }
        router.open(url)
    }
}
