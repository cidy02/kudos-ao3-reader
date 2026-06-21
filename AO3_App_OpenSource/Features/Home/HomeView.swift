import SwiftUI
import SwiftData

/// The Home tab: a personal, Books-style dashboard. Reading Now is a hero carousel;
/// Favorites and Recently Opened are standard carousels. Tapping a card opens the
/// work in the reader; tapping a section header pushes its full vertical list.
/// (Network sections — Subscriptions, Recently Updated — are added in a later pass.)
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var works: [SavedWork]
    @State private var path = NavigationPath()

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private var readingNow: [SavedWork] { HomeSectionKind.readingNow.works(from: works, visible: passesPrivacy) }
    private var favorites: [SavedWork] { HomeSectionKind.favorites.works(from: works, visible: passesPrivacy) }
    private var recentlyOpened: [SavedWork] { HomeSectionKind.recentlyOpened.works(from: works, visible: passesPrivacy) }

    private var isEmpty: Bool { readingNow.isEmpty && favorites.isEmpty && recentlyOpened.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if !readingNow.isEmpty { heroSection }
                            carousel(.favorites, works: favorites)
                            carousel(.recentlyOpened, works: recentlyOpened)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle("Home")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inlineLarge)
            #endif
            .navigationDestination(for: SavedWork.self) { HomeWorkDestination(work: $0) }
            .navigationDestination(for: HomeSectionKind.self) { HomeSectionListView(kind: $0) }
        }
    }

    // MARK: Sections

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(.readingNow, seeAll: readingNow.count > 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(readingNow.prefix(10)) { work in
                        NavigationLink(value: work) { HeroReadingCard(work: work) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func carousel(_ kind: HomeSectionKind, works: [SavedWork]) -> some View {
        if !works.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header(kind, seeAll: works.count > 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(works.prefix(12)) { work in
                            NavigationLink(value: work) {
                                WorkCoverCard(work: work, footer: footer(kind, work))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    /// A tappable section header (title → full "See all" list) when there's more
    /// than one item; otherwise a plain title.
    @ViewBuilder
    private func header(_ kind: HomeSectionKind, seeAll: Bool) -> some View {
        if seeAll {
            NavigationLink(value: kind) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kind.title).font(.title2.bold()).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        } else {
            Text(kind.title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }

    private func footer(_ kind: HomeSectionKind, _ work: SavedWork) -> String? {
        switch kind {
        case .readingNow, .recentlyOpened:
            return work.lastSpineIndex > 0 ? "Ch \(work.lastSpineIndex + 1)" : nil
        case .favorites:
            return nil
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your dashboard is empty", systemImage: "house")
        } description: {
            Text("Works you read, favorite, and open will show up here as you use the app.")
        } actions: {
            Button("Find Works to Read") { router.selection = .search }
        }
    }
}
