import SwiftUI

/// Long-tail AO3 dashboard destinations that stay on the website until they
/// earn a native surface. Grouped by job so Overview stays dense.
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
                Text("These open your AO3 pages in Browse. Native versions can land later.")
            }

            Section("Challenges & gifts") {
                externalCard(
                    title: "Sign-ups",
                    systemImage: "person.badge.plus",
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

            Section {
                externalCard(
                    title: "Dashboard",
                    systemImage: "square.grid.2x2",
                    pathSuffix: nil
                )
            } header: {
                Text("On AO3")
            } footer: {
                Text("Your full AO3 control panel on the website.")
            }
        }
        .cardList()
        .navigationTitle("More on AO3")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
    }

    /// `pathSuffix` nil → user root dashboard (`/users/:login`).
    @ViewBuilder
    private func externalCard(
        title: String,
        systemImage: String,
        pathSuffix: String?
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

    private func openUserPath(_ suffix: String?) {
        guard let username = auth.username else { return }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? username
        let path: String
        if let suffix, !suffix.isEmpty {
            path = "/users/\(encoded)/\(suffix)"
        } else {
            path = "/users/\(encoded)"
        }
        guard let url = URL(string: "https://archiveofourown.org\(path)") else { return }
        router.open(url)
    }
}
