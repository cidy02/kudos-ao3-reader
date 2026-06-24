import SwiftUI
import SwiftData

/// The full, vertically scrolling list behind a Home section's header ("See all").
/// Reuses the Library's privacy-aware `SensitiveWorkRow`; rows open works the same
/// way the dashboard cards do (via Home's `SavedWork` navigation destination).
struct HomeSectionListView: View {
    let kind: HomeSectionKind

    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var works: [SavedWork]

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private var items: [SavedWork] { kind.works(from: works, visible: passesPrivacy) }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "books.vertical")
            } else {
                List {
                    ForEach(items) { work in
                        SensitiveWorkRow(work: work)
                    }
                    .cardRow()
                }
                .cardList()
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle(kind.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
