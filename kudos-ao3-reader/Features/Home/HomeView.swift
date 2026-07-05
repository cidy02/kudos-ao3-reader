import OSLog
import SwiftData
import SwiftUI

/// The Home tab: a personal, Books-style dashboard. Every section is a collapsible
/// horizontal card carousel with a `>` chevron that opens its full vertical list.
/// Tapping a local card opens the reader; long-press opens management actions,
/// including Work Details. Remote cards still tap through to Work Details.
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

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var works: [SavedWork]
    @State private var path = NavigationPath()
    @State private var subscriptions: [AO3WorkSummary] = []
    /// True only while the remote subscriptions request is actually in flight, so the
    /// carousel can show cover skeletons instead of briefly flashing its empty state.
    @State private var isLoadingSubscriptions = false

    /// Route marker so the Subscriptions header can push the full AO3 list.
    private struct SubscriptionsRoute: Hashable {}

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private func section(_ kind: HomeSectionKind) -> [SavedWork] {
        kind.works(from: works, visible: passesPrivacy)
    }

    private var readingNow: [SavedWork] {
        section(.readingNow)
    }

    private var recentlyUpdated: [SavedWork] {
        section(.recentlyUpdated)
    }

    private var favorites: [SavedWork] {
        section(.favorites)
    }

    private var recentlyOpened: [SavedWork] {
        section(.recentlyOpened)
    }

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
            .refreshable { await refreshHome() }
            .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle("Home")
            #if os(iOS)
                .toolbarTitleDisplayMode(.inlineLarge)
            #endif
                .navigationDestination(for: SavedWork.self) { HomeWorkDestination(work: $0) }
                .navigationDestination(for: LocalWorkDestination.self) { destination in
                    LocalWorkDestinationView(destination: destination, onReaderOpen: markUpdateSeen)
                }
                .navigationDestination(for: HomeSectionKind.self) { HomeSectionListView(kind: $0) }
                .navigationDestination(for: AO3WorkSummary.self) { WorkDetailView(remote: $0) }
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
                NavigationLink(value: LocalWorkDestination.reader(work)) {
                    WorkCoverCard(work: work, footer: footer(kind, work), progress: progress(kind, work))
                }
                .buttonStyle(.plain)
                .localWorkContextMenu(work: work)
            }
        } emptyState: {
            SectionEmptyState(message: kind.emptyMessage, systemImage: kind.emptyIcon)
        }
    }

    private var subscriptionsSection: some View {
        // Show cover skeletons only while the request is in flight and we have nothing
        // yet; once it finishes (empty or not) the real cards / empty state take over.
        let showSkeleton = isLoadingSubscriptions && subscriptions.isEmpty
        return WorkCarouselSection(
            title: "Subscriptions",
            collapseKey: "home.subscriptions",
            hasItems: !subscriptions.isEmpty || showSkeleton,
            onSeeAll: subscriptions.isEmpty ? nil : { path.append(SubscriptionsRoute()) }
        ) {
            if showSkeleton {
                ForEach(0 ..< 6, id: \.self) { _ in WorkCoverCardSkeleton() }
            } else {
                ForEach(subscriptions.prefix(12)) { work in
                    NavigationLink(value: work) { AO3WorkCoverCard(work: work) }
                        .buttonStyle(.plain)
                }
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
        // No request happens when signed out (accountWorks early-returns), so don't
        // raise the loading flag — the signed-out empty state should show immediately.
        guard auth.isLoggedIn else {
            subscriptions = []
            isLoadingSubscriptions = false
            return
        }
        isLoadingSubscriptions = true
        do {
            subscriptions = try await auth.accountSubscriptions()
        } catch {
            // A refresh failure (network, rate limit, expired session) must not wipe
            // out a previously successful fetch — keep showing what's already there.
            Log.network.notice(
                "Subscriptions refresh failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        isLoadingSubscriptions = false
    }

    private func refreshHome() async {
        _ = await WorkMetadataRefresh.refresh(visibleHomeWorks, in: context)
        await loadSubscriptions()
    }

    private var visibleHomeWorks: [SavedWork] {
        unique(
            Array(readingNow.prefix(12))
                + Array(recentlyUpdated.prefix(12))
                + Array(favorites.prefix(12))
                + Array(recentlyOpened.prefix(12))
        )
    }

    private func unique(_ works: [SavedWork]) -> [SavedWork] {
        var seen = Set<UUID>()
        return works.filter { seen.insert($0.id).inserted }
    }

    private func markUpdateSeen(_ work: SavedWork) {
        guard work.hasUpdate else { return }
        work.knownChapterCount = work.postedChapterCount
        try? context.save()
    }

    // MARK: Card details

    private func footer(_ kind: HomeSectionKind, _ work: SavedWork) -> String? {
        switch kind {
        case .readingNow, .recentlyOpened:
            return work.readingProgressLabel
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
        kind == .readingNow ? work.readingProgress : nil
    }
}
