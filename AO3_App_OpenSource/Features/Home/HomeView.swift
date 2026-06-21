import SwiftUI
import SwiftData

/// The Home tab: a personal, Books-style dashboard. Every section is a collapsible
/// horizontal card carousel with a `>` chevron that opens its full vertical list.
/// Tapping a card opens the work (reader if downloaded, else its detail page).
/// Sections, in order: Reading Now, Recently Updated, Subscriptions, Favorites,
/// Recently Opened.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var works: [SavedWork]
    @State private var path = NavigationPath()
    @State private var subscriptions: [AO3WorkSummary] = []

    /// Route marker so the Subscriptions header can push the full AO3 list.
    private struct SubscriptionsRoute: Hashable {}

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private func section(_ kind: HomeSectionKind) -> [SavedWork] {
        kind.works(from: works, visible: passesPrivacy)
    }
    private var readingNow: [SavedWork] { section(.readingNow) }
    private var recentlyUpdated: [SavedWork] { section(.recentlyUpdated) }
    private var favorites: [SavedWork] { section(.favorites) }
    private var recentlyOpened: [SavedWork] { section(.recentlyOpened) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    localSection(.readingNow, works: readingNow)
                    localSection(.recentlyUpdated, works: recentlyUpdated)
                    subscriptionsSection
                    localSection(.favorites, works: favorites)
                    localSection(.recentlyOpened, works: recentlyOpened)
                }
                .padding(.vertical, 12)
            }
            .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle("Home")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inlineLarge)
            #endif
            .navigationDestination(for: SavedWork.self) { HomeWorkDestination(work: $0) }
            .navigationDestination(for: HomeSectionKind.self) { HomeSectionListView(kind: $0) }
            .navigationDestination(for: AO3WorkSummary.self) { AO3WorkDetailView(work: $0, path: $path) }
            .navigationDestination(for: SubscriptionsRoute.self) { _ in AO3AccountWorksList(kind: .subscriptions) }
            .task(id: auth.isLoggedIn) { await loadSubscriptions() }
            .task { await WorkUpdateChecker.checkForUpdates(among: works, in: context) }
        }
    }

    // MARK: Sections

    private func localSection(_ kind: HomeSectionKind, works sectionWorks: [SavedWork]) -> some View {
        WorkCarouselSection(
            title: kind.title,
            collapseKey: "home.\(kind.rawValue)",
            hasItems: !sectionWorks.isEmpty,
            onSeeAll: sectionWorks.count > 1 ? { path.append(kind) } : nil
        ) {
            ForEach(sectionWorks.prefix(12)) { work in
                NavigationLink(value: work) {
                    WorkCoverCard(work: work, footer: footer(kind, work), progress: progress(kind, work))
                }
                .buttonStyle(.plain)
            }
        } emptyState: {
            SectionEmptyState(message: kind.emptyMessage, systemImage: kind.emptyIcon)
        }
    }

    private var subscriptionsSection: some View {
        WorkCarouselSection(
            title: "Subscriptions",
            collapseKey: "home.subscriptions",
            hasItems: !subscriptions.isEmpty,
            onSeeAll: subscriptions.isEmpty ? nil : { path.append(SubscriptionsRoute()) }
        ) {
            ForEach(subscriptions.prefix(12)) { work in
                NavigationLink(value: work) { AO3WorkCoverCard(work: work) }
                    .buttonStyle(.plain)
            }
        } emptyState: {
            SectionEmptyState(
                message: auth.isLoggedIn
                    ? "You're not subscribed to anything yet. Subscribe to works or series to see updates here."
                    : "Log in to AO3 to see the works and series you subscribe to.",
                systemImage: "bell"
            )
        }
    }

    private func loadSubscriptions() async {
        guard auth.isLoggedIn, let username = auth.username,
              let url = AO3Client.subscriptionsURL(username: username, page: 1)
        else {
            subscriptions = []
            return
        }
        do {
            let request = try auth.authenticatedRequest(for: url)
            subscriptions = try await AO3Client.shared.worksPage(for: request, page: 1).works
        } catch {
            subscriptions = []
        }
    }

    // MARK: Card details

    private func footer(_ kind: HomeSectionKind, _ work: SavedWork) -> String? {
        switch kind {
        case .readingNow, .recentlyOpened:
            return work.lastSpineIndex > 0 ? "Ch \(work.lastSpineIndex + 1)" : nil
        case .recentlyUpdated:
            let new = work.postedChapterCount - work.knownChapterCount
            return new > 0 ? "+\(new) new" : "Updated"
        case .favorites:
            return nil
        }
    }

    /// Reading progress (0…1) for Reading Now cards: position over the work's AO3
    /// chapter count, falling back to the in-chapter scroll fraction.
    private func progress(_ kind: HomeSectionKind, _ work: SavedWork) -> Double? {
        guard kind == .readingNow else { return nil }
        let parts = work.chapters.split(separator: "/")
        if parts.count == 2, let total = Int(parts[1].trimmingCharacters(in: .whitespaces)), total > 1 {
            return min(1, Double(work.lastSpineIndex + 1) / Double(total))
        }
        return work.lastScrollFraction > 0 ? work.lastScrollFraction : nil
    }
}
