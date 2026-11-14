import Foundation
import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The Home tab: a personal launchpad. Tapping a local work opens the reader;
/// long-press opens its management actions, including Work Details.
/// Sections, in order: weekly stats, Resume, Reading Now, New Chapters, Reading
/// Queues, collections flagged Show on Home, then Subscriptions.
struct HomeView: View { // swiftlint:disable:this type_body_length
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inboxModel
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage(WorkSymbolPlacement.storageKey) private var symbolPlacement: WorkSymbolPlacement = .defaultValue
    @Environment(SubscriptionScanService.self) private var subscriptionScan
    #if os(iOS)
    @Environment(MailSubscriptionDriver.self) private var mailDriver
    #endif

    /// What the Subscriptions screen's Waiting tab shows, newest first: mail while it
    /// is connected, otherwise the scan's. Hide mode's omissions as in Waiting.
    private var recentSubscriptionUpdates: [SubscriptionUpdate] {
        var updates = subscriptionScan.updates
        #if os(iOS)
        if mailDriver.isConnected { updates = mailDriver.updates }
        #endif
        return updates
            .filter {
                !gate.isHidden(remoteID: Int(clamping: $0.workID), rating: $0.rating, enabled: hideMature, mode: matureMode)
            }
            .sorted { $0.at > $1.at }
    }

    /// New Chapters and Subscriptions dividers: under the 2×2 (79, as before), or at the
    /// screen inset when the symbols sit under the title.
    private var newChapterRowInset: CGFloat {
        symbolPlacement == .underTitle ? WorkRowMetrics.screenInset : 79
    }
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var works: [SavedWork]
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var readingQueues: [ReadingQueue]
    @Query(filter: #Predicate<WorkCollection> { $0.showsOnHome && !$0.isPendingDeletion })
    private var homeCollections: [WorkCollection]
    @Query(sort: \ReadingSession.startedAt, order: .reverse)
    private var readingSessions: [ReadingSession]
    @State private var readingStats = HomeReadingStats()
    @State private var path = NavigationPath()
    @Namespace private var cardZoomNamespace
    @State private var subscriptions: [AO3WorkSummary] = []
    @State private var accountAvatarURL: URL?
    /// True only while the remote subscriptions request is actually in flight, so the
    /// carousel can show cover skeletons instead of briefly flashing its empty state.
    @State private var isLoadingSubscriptions = false
    /// The size AO3's pagination gave the last successful load, taken from
    /// `AO3AccountListCountsCache` at that moment so the header count cannot
    /// outlive (or predate) the cards it describes.
    @State private var subscriptionsListCount: AO3AccountListCount?
    /// The first load failed and nothing was ever shown. Keeps the empty state
    /// from telling a signed-in reader they are not subscribed to anything.
    @State private var subscriptionsLoadFailed = false
    @State private var showingNewQueue = false
    @State private var newQueueName = ""
    /// 1j's colour swatch for the queue being created.
    @State private var newQueueHue: Double?

    // Multi-select / bulk actions, mirroring LibraryView's carousel selection.
    // Scoped to local works (Resume, Reading Now and New Chapters) — Subscriptions
    // merges in remote entries via CanonicalWorkCoverCard, a different card type
    // not wired for selection here.
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()

    // Section cache — same rationale as LibraryView: don't re-filter every
    // carousel on every body pass while Liquid Glass is mid-morph.
    @State private var sectionCache: [HomeSectionKind: [SavedWork]] = [:]
    @State private var hasSectionCache = false

    /// Route marker so the Subscriptions header can push the full AO3 list.
    private struct SubscriptionsRoute: Hashable {
        /// The tab the rows on Home were showing: updates → Waiting, followed works → Following.
        var tab: SubscriptionsView.Tab = .waiting
    }

    private var selectedWorks: [SavedWork] {
        allLocalSectionWorks.filter { selection.contains($0.id) }
    }

    private func toggleSelection(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private func enterSelectMode(selecting work: SavedWork? = nil) {
        if let work { selection.insert(work.id) }
        isSelecting = true
    }

    private func selectAction(for work: SavedWork) -> (() -> Void)? {
        { enterSelectMode(selecting: work) }
    }

    private func exitSelectMode() {
        isSelecting = false
        selection = []
    }

    private var allLocalSelected: Bool {
        let ids = Set(allLocalSectionWorks.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    private func toggleSelectAll() {
        selection = allLocalSelected ? [] : Set(allLocalSectionWorks.map(\.id))
    }

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private func section(_ kind: HomeSectionKind) -> [SavedWork] {
        sectionCache[kind] ?? []
    }

    private var readingNow: [SavedWork] { section(.readingNow) }
    private var recentlyUpdated: [SavedWork] { section(.recentlyUpdated) }

    /// The union of every local section, untruncated, for the Privacy button's
    /// visibility check — a `.prefix(12)`-truncated set could hide the button even
    /// though an adult work is sitting further down a section.
    private var allLocalSectionWorks: [SavedWork] {
        readingNow + recentlyUpdated
    }

    private var homeSectionsRevision: String {
        let newest = Int(works.map(\.lastModifiedAt).max()?.timeIntervalSince1970 ?? 0)
        let bits = works.reduce(into: 0) { partial, work in
            if work.isFavorite { partial += 1 }
            if work.isFinished { partial += 2 }
            if work.hasUpdate { partial += 4 }
            if work.hasStartedReading { partial += 8 }
        }
        return [
            "\(works.count)",
            "\(newest)",
            "\(bits)",
            "\(hideMature)",
            "\(matureMode.rawValue)",
            "\(gate.revealAll)",
            "\(gate.revealedIDs.count)"
        ].joined(separator: "|")
    }

    private func rebuildHomeSectionCache() {
        var next: [HomeSectionKind: [SavedWork]] = [:]
        for kind in HomeSectionKind.allCases {
            next[kind] = kind.works(from: works, visible: passesPrivacy)
        }
        sectionCache = next
        hasSectionCache = true
    }

    private var statisticsWorks: [SavedWork] {
        HomeReadingStats.insightsWorks(from: works, gate: gate, hideMature: hideMature)
    }

    private var homeStatsRevision: String {
        let newest = readingSessions.map(\.lastModifiedAt).max()?.timeIntervalSince1970 ?? 0
        return HomeReadingStats.revisionKey(
            sessionCount: readingSessions.count,
            newestModified: newest,
            now: Date(),
            calendar: .current
        )
    }

    private func updateReadingStats() {
        let facts = ReadingLogService.facts(from: readingSessions, works: works)
        readingStats = HomeReadingStats.calculate(facts: facts)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hasSectionCache {
                    DashboardRegionHost {
                        ScrollViewReader { proxy in
                            ScrollView {
                                // 26pt between sections (Rules; 1b drew 22).
                                VStack(alignment: .leading, spacing: SubjectMetrics.sectionSpacing) {
                                    statsLine
                                    resumeSection
                                    newChaptersSection
                                        .id("chapters")
                                    readingQueuesSection
                                        .id("queues")
                                    let shelves = HomeCollectionShelves.shelves(homeCollections)
                                    ForEach(Array(shelves.enumerated()), id: \.element.id) { index, collection in
                                        HomeCollectionShelf(
                                            collection: collection,
                                            works: HomeCollectionShelves.works(in: collection, visible: passesPrivacy),
                                            onSeeAll: { path.append(collection) }
                                        )
                                        .id(index == 0 ? "collections" : "collection:\(collection.id)")
                                    }
                                    subscriptionsSection
                                        .id("subscriptions")
                                }
                                .padding(.vertical, 12)
                            }
                            .refreshable { await refreshHome() }
                            #if os(iOS)
                            .task { await mailDriver.refreshIfNeeded() }
                            #endif
                            .scrollAwayTopChrome()
                            #if DEBUG
                            .task {
                                guard let anchor = DebugLaunchRoute.homeAnchor else { return }
                                try? await Task.sleep(for: .seconds(1.5))
                                proxy.scrollTo(anchor, anchor: .top)
                            }
                            #endif
                        }
                    }
                } else {
                    TabDashboardShell(
                        sectionTitles: [
                            "Reading Now", "New Chapters", "Reading Queues",
                            "Subscriptions"
                        ],
                        showsResumeHero: true
                    )
                }
            }
            .background(themeManager.appTheme.contentBackdrop.ignoresSafeArea())
            .navigationTitle("Home")
            #if os(iOS)
                .toolbarTitleDisplayMode(.inlineLarge)
            #endif
                .navigationDestination(for: SavedWork.self) { HomeWorkDestination(work: $0) }
                .navigationDestination(for: ReadingInsightsDestination.self) { _ in
                    ReadingInsightsView(works: statisticsWorks)
                }
                .navigationDestination(for: LocalWorkDestination.self) { destination in
                    LocalWorkDestinationView(destination: destination, onReaderOpen: markUpdateSeen)
                }
                // Still live for New Chapters (`newChaptersSection` → path.append(kind)).
                // Resume "See all" intentionally does NOT use this: it deep-links into
                // Library via `router.showLibrarySection(.readingNow)` so the full list
                // lives on Library's stack (Phase A contract). `.readingNow` remains a
                // valid HomeSectionKind for section cache / empty copy; the destination
                // case is simply unreached from current Home chrome, not orphaned wiring.
                .navigationDestination(for: HomeSectionKind.self) { kind in
                    HomeSectionListView(kind: kind, initialSelecting: isSelecting, initialSelection: selection)
                }
                .navigationDestination(for: AO3WorkSummary.self) { WorkDetailView(remote: $0) }
                .navigationDestination(for: WorkCollection.self) { CollectionDetailView(collection: $0) }
                .navigationDestination(for: SubscriptionsRoute.self) { route in
                    SubscriptionsView(initialTab: route.tab)
                }
                .navigationDestination(for: AllReadingQueuesDestination.self) { destination in
                    // Chevron passes nil → stack grid (owns its own New Queue sheet).
                    // A specific queue id opens the Safari-style browser.
                    if destination.initialQueueID == nil {
                        AllReadingQueuesGridView()
                    } else {
                        ReadingQueueBrowserView(initialQueueID: destination.initialQueueID, originKicker: "Home")
                    }
                }
                .onChange(of: router.pendingLocalWorkDestination, initial: true) { _, destination in
                    guard let destination else { return }
                    router.pendingLocalWorkDestination = nil
                    path.append(destination)
                }
                .ao3AuthorNavigation(path: $path, tab: .home)
                #if DEBUG
                .task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if let destination = DebugLaunchRoute.homeDestination(queues: readingQueues) {
                        path.append(destination)
                    } else if let kind = DebugLaunchRoute.homeSection() {
                        path.append(kind)
                    } else if let route = DebugLaunchRoute.authorRoute {
                        path.append(route)
                    } else if let work = DebugLaunchRoute.homeWork(in: works) {
                        DebugLaunchRoute.installFixtureEPUBs(in: works)
                        if DebugLaunchRoute.wantsSheet("readerend") {
                            work.lastSpineIndex = 1
                            work.readiumLocator = #"{"href":"ch2.xhtml","locations":{"progression":1.0,"totalProgression":1.0}}"#
                            work.isFinished = true
                        }
                        path.append(DebugLaunchRoute.opensReader ? .reader(work) : LocalWorkDestination.detail(work))
                        if let comments = DebugLaunchRoute.commentsRoute(for: work) { path.append(comments) }
                    }
                }
                #endif
                .task(id: homeSectionsRevision) {
                    await Task.yield()
                    rebuildHomeSectionCache()
                    updateReadingStats()
                }
                .task(id: homeStatsRevision) {
                    updateReadingStats()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        updateReadingStats()
                    }
                }
                .task(id: auth.isLoggedIn) {
                    await Task.yield()
                    await loadSubscriptions()
                }
                .task(id: accountAvatarCacheKey) { await loadCachedAccountAvatar() }
                .onChange(of: auth.sessionGeneration, initial: true) { _, _ in
                    // Keep a previous account's loaded count out of Home without
                    // activating Inbox or issuing a request for the new session.
                    inboxModel.syncAuthenticationContext(auth: auth)
                }
                .task {
                    // Defer network/update polling until after the Home tab paints —
                    // don't compete with tab-switch Liquid Glass for the main actor.
                    await Task.yield()
                    await WorkUpdateChecker.checkForUpdates(among: works, in: context)
                }
            #if os(iOS)
                // Select mode owns the bottom edge with its bulk-action bar; matches
                // LibraryView's own rationale for hiding the floating tab bar meanwhile.
                .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            #endif
                .toolbar {
                    if isSelecting {
                        ToolbarItem(placement: .confirmationAction) {
                            SelectAllButton(allSelected: allLocalSelected, action: toggleSelectAll)
                        }
                        if hideMature {
                            ToolbarItem(placement: .primaryAction) {
                                MatureRevealToggle()
                            }
                        }
                        #if os(iOS)
                        ToolbarItemGroup(placement: .bottomBar) {
                            WorkBulkActionBar(selectedWorks: selectedWorks, onDeleted: exitSelectMode, onDone: exitSelectMode)
                        }
                        #else
                        ToolbarItemGroup(placement: .primaryAction) {
                            WorkBulkActionBar(selectedWorks: selectedWorks, onDeleted: exitSelectMode, onDone: exitSelectMode)
                        }
                        #endif
                    } else {
                        let hasMature = hideMature
                        // Gated as a whole, not just its inner pieces — an empty HStack
                        // still reserves an (empty-looking) toolbar slot, which is
                        // exactly what showed a blank button when the Library was empty.
                        // WorkListMoreMenu's own gate widened to
                        // `!allLocalSectionWorks.isEmpty || hasMature` — Privacy now
                        // lives inside it, so it needs a home even with no local works.
                        ActionToolbar(items: [
                            // Was the Reading Queues shelf's first card (owner,
                            // 2026-10-01): the top chrome holds the create action.
                            AnyView(ToolbarIconButton(title: "New Queue", systemImage: "plus") {
                                newQueueName = ""
                                showingNewQueue = true
                            }),
                            (!allLocalSectionWorks.isEmpty || hasMature)
                                ? AnyView(WorkListMoreMenu {
                                    if hasMature {
                                        MatureRevealToggle()
                                    }
                                    if !allLocalSectionWorks.isEmpty {
                                        Button {
                                            enterSelectMode()
                                        } label: {
                                            Label("Select", systemImage: "checklist")
                                        }
                                    }
                                })
                                : nil
                        ].compactMap { $0 })
                        // The Account button is the right-most control (owner, 2026-11-02).
                        ToolbarItem(placement: .primaryAction) {
                            profileButton
                        }
                    }
                }
                // Sheet for the toolbar's New Queue (it was the carousel's card).
                //
                // This was a third inline copy of the same plain `Form`, which is
                // exactly what `NewReadingQueueSheet` was extracted to replace — the
                // organizer and the browser were migrated to it and Home was not, so
                // Home quietly missed 1j's colour swatches when they landed. One
                // sheet, three entry points.
                .sheet(isPresented: $showingNewQueue) {
                    NewReadingQueueSheet(
                        name: $newQueueName,
                        hue: $newQueueHue,
                        onCreate: createQueue,
                        onCancel: {
                            newQueueName = ""
                            newQueueHue = nil
                            showingNewQueue = false
                        }
                    )
                }
        }
        // Declared on the stack itself so the cards inside it and the screens
        // pushed from it resolve the same namespace — that pairing is what the
        // zoom transition matches on.
        .environment(\.workCardTransitionNamespace, cardZoomNamespace)
    }

    /// T-460 replaces the Account tab with this persistent Home identity control.
    /// Its badge shares the Inbox model with the sheet, so reads clear immediately.
    private var profileButton: some View {
        Button {
            router.showAccount()
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    HomeProfileAvatar(
                        url: accountAvatarURL,
                        username: auth.username,
                        identity: auth.username.map {
                            themeManager.appTheme.subjectPalette(hue: CoverArt.hue(for: $0))
                        }
                    )
                }
                .frame(width: 30, height: 30)

                if let unreadCount = inboxModel.unreadCount, unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, unreadCount > 9 ? 4 : 3)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(.accentFill, in: Capsule())
                        .offset(x: 7, y: -6)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(auth.isLoggedIn ? "Account" : "Log in to AO3")
        .accessibilityValue(inboxModel.unreadCount.map { "\($0) unread Inbox comments" } ?? "")
    }

    private var accountAvatarCacheKey: String {
        "\(auth.sessionGeneration)|\(auth.username ?? "")|\(router.isPresentingAccount)"
    }

    private func loadCachedAccountAvatar() async {
        guard let username = auth.username, let route = AO3AuthorRoute(username: username) else {
            accountAvatarURL = nil
            return
        }
        accountAvatarURL = nil
        let generation = auth.sessionGeneration
        let avatarURL = await AO3AuthorProfileFetcher.cachedDashboardAvatarURL(for: route, auth: auth)
        guard !Task.isCancelled,
              generation == auth.sessionGeneration,
              auth.username?.localizedCaseInsensitiveCompare(username) == .orderedSame
        else { return }
        accountAvatarURL = avatarURL
    }

    // MARK: Sections

    private var statsLine: some View {
        NavigationLink(value: ReadingInsightsDestination()) {
            HStack(spacing: 4) {
                (
                    Text(readingStats.formattedDuration).fontWeight(.semibold).foregroundStyle(.primary)
                    + Text(" this week · ").foregroundStyle(.secondary)
                    + Text("\(readingStats.finishedCount)").fontWeight(.semibold).foregroundStyle(.primary)
                    + Text(" finished · ").foregroundStyle(.secondary)
                    + Text(readingStats.formattedStreak).fontWeight(.semibold).foregroundStyle(.primary)
                    + Text(" streak").foregroundStyle(.secondary)
                )
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, -20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardLeadingRegion()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(readingStats.accessibilityLabel)
            .accessibilityHint("Opens reading insights")
        }
        .buttonStyle(.plain)
    }

    private var resumeSection: some View {
        Group {
            if readingNow.isEmpty {
                // Strong empty state (Synthesis v2): section chrome + CTAs, not a
                // dead hero-shaped hole. Same header weight as other Home rows.
                VStack(alignment: .leading, spacing: 11) {
                    SectionRuleHeader(title: "Continue Reading")
                        .dashboardLeadingRegion()

                    SectionEmptyState(
                        message: HomeSectionKind.readingNow.emptyMessage,
                        systemImage: HomeSectionKind.readingNow.emptyIcon
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .dashboardLeadingRegion()

                    HStack(spacing: 12) {
                        Button("Browse AO3") {
                            router.selection = .browse
                        }
                        .buttonStyle(.kudosPrimary)

                        Button("Open Library") {
                            router.selection = .library
                        }
                        .buttonStyle(.kudosSecondary)
                    }
                    .padding(.horizontal, 16)
                    .dashboardLeadingRegion()
                }
            } else {
                let heroWork = readingNow[0]
                let carouselWorks = Array(readingNow.dropFirst().prefix(3))
                HomeResumeComposition(
                    hasNext: !carouselWorks.isEmpty,
                    nextSectionTitle: "Reading Now",
                    nextSectionCount: readingNow.count,
                    nextSectionVisibleCount: min(readingNow.count, 4),
                    onSeeAll: { router.showLibrarySection(.readingNow, from: "Home") }
                ) {
                    HomeResumeHero(
                        work: heroWork,
                        isSelecting: isSelecting,
                        isSelected: selection.contains(heroWork.id),
                        onToggleSelection: { toggleSelection(heroWork) },
                        onSelect: selectAction(for: heroWork),
                        onPrimary: { path.append(LocalWorkDestination.reader(heroWork)) },
                        onReadAloud: { path.append(LocalWorkDestination.readerReadAloud(heroWork)) }
                    )
                    .downloadDimmed(heroWork)
                } next: {
                    ForEach(carouselWorks) { work in
                        if isSelecting {
                            SensitiveWorkCoverCard(
                                work: work,
                                footer: footer(.readingNow, work),
                                progress: progress(.readingNow, work),
                                isSelecting: true,
                                isSelected: selection.contains(work.id),
                                onToggleSelection: { toggleSelection(work) }
                            )
                            .localWorkContextMenu(work: work, onSelect: selectAction(for: work))
                        } else if gate.isBlurred(work, enabled: hideMature, mode: matureMode) {
                            SensitiveWorkCoverCard(
                                work: work,
                                footer: footer(.readingNow, work),
                                progress: progress(.readingNow, work)
                            )
                        } else {
                            NavigationLink(value: LocalWorkDestination.reader(work)) {
                                SensitiveWorkCoverCard(
                                    work: work,
                                    footer: footer(.readingNow, work),
                                    progress: progress(.readingNow, work)
                                )
                            }
                            .buttonStyle(.plain)
                            .localWorkContextMenu(work: work, onSelect: selectAction(for: work))
                        }
                    }
                }
            }
        }
    }

    private var newChaptersSection: some View {
        let sectionWorks = recentlyUpdated
        let visibleWorks = Array(sectionWorks.prefix(3))
        return VStack(alignment: .leading, spacing: 6) {
            SectionRuleHeader(
                title: "New Chapters",
                count: sectionWorks.count,
                actionTitle: sectionWorks.count > 3 ? "See All" : nil,
                onSeeAll: sectionWorks.isEmpty ? nil : { path.append(HomeSectionKind.recentlyUpdated) }
            )
            .dashboardLeadingRegion()

            if sectionWorks.isEmpty {
                SectionEmptyState(
                    message: HomeSectionKind.recentlyUpdated.emptyMessage,
                    systemImage: HomeSectionKind.recentlyUpdated.emptyIcon
                )
                .padding(.horizontal, 16)
                .dashboardLeadingRegion()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleWorks.enumerated()), id: \.element.id) { index, work in
                        if index > 0 {
                            Divider()
                                .padding(.leading, newChapterRowInset)
                        }
                        HomeNewChapterRow(
                            work: work,
                            isSelecting: isSelecting,
                            isSelected: selection.contains(work.id),
                            onToggleSelection: { toggleSelection(work) },
                            onSelect: selectAction(for: work)
                        )
                    }

                    if sectionWorks.count > 3 {
                        Divider()
                            .padding(.leading, newChapterRowInset)
                        ListMoreRow(
                            count: sectionWorks.count - 3,
                            sectionTitle: "New Chapters",
                            leadingInset: newChapterRowInset,
                            action: { path.append(HomeSectionKind.recentlyUpdated) }
                        )
                    }
                }
                .dashboardLeadingRegion()
            }
        }
    }

    private var readingQueuesSection: some View {
        let customQueues = readingQueues
            .filter { $0.kind == .custom }
            .sorted { $0.sortOrder < $1.sortOrder }
        let visibleQueues = Array(customQueues.prefix(3))

        return VStack(alignment: .leading, spacing: 6) {
            SectionRuleHeader(
                title: "Reading Queues",
                count: customQueues.count,
                actionTitle: customQueues.count > 3 ? "See All" : "Organise",
                onSeeAll: !customQueues.isEmpty
                    ? { path.append(AllReadingQueuesDestination(initialQueueID: nil)) }
                    : nil
            )
            .dashboardLeadingRegion()

            if customQueues.isEmpty {
                SectionEmptyState(message: "No reading queues yet.", systemImage: "rectangle.stack")
                    .padding(.horizontal, 16)
                    .dashboardLeadingRegion()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleQueues.enumerated()), id: \.element.id) { index, queue in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 80)
                        }
                        HomeQueueRow(
                            queue: queue,
                            onOpenQueue: { path.append(AllReadingQueuesDestination(initialQueueID: queue.id)) },
                            onStartWork: { path.append(LocalWorkDestination.reader($0)) }
                        )
                    }

                    if customQueues.count > 3 {
                        Divider()
                            .padding(.leading, 80)
                        ListMoreRow(
                            count: customQueues.count - 3,
                            sectionTitle: "Reading Queues",
                            leadingInset: 80,
                            action: { path.append(AllReadingQueuesDestination(initialQueueID: nil)) }
                        )
                    }
                }
                .dashboardLeadingRegion()
            }
        }
    }

    private var subscriptionsSection: some View {
        let showSkeleton = isLoadingSubscriptions && subscriptions.isEmpty
        let merged = CanonicalWorkMerge.remoteLed(
            remote: subscriptions,
            localLibrary: works
        )
        let visibleEntries = merged.filter {
            !gate.isHidden($0, enabled: hideMature, mode: matureMode)
        }
        let totalCount = showSkeleton
            ? nil
            : HomeSubscriptionsCount.itemCount(shown: visibleEntries.count, recorded: subscriptionsListCount)
        let visibleRows = Array(visibleEntries.prefix(2))
        // Owner, canvas 2026-11-08: "update this section to look like subscriptions do
        // now" — when Kudos knows what changed, the newest updates in Waiting's own rows.
        let updates = recentSubscriptionUpdates
        let updateRows = Array(updates.prefix(2))

        return VStack(alignment: .leading, spacing: 6) {
            SectionRuleHeader(
                title: "Subscriptions",
                count: updates.isEmpty ? totalCount : updates.count,
                actionTitle: (updates.isEmpty ? visibleEntries.count : updates.count) > 2 ? "See All" : nil,
                onSeeAll: visibleEntries.isEmpty && updates.isEmpty
                    ? nil
                    : { path.append(SubscriptionsRoute(tab: updates.isEmpty ? .following : .waiting)) }
            )
            .dashboardLeadingRegion()

            if !updateRows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(updateRows.enumerated()), id: \.element.id) { index, update in
                        // A tap gesture, not a Button: a concealed row's own reveal
                        // button must win the tap.
                        WaitingRow(
                            update: update,
                            position: index + 1,
                            showsPosition: false,
                            isFirst: index == 0,
                            isLast: index == updateRows.count - 1
                        )
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                        .onTapGesture { path.append(SubscriptionsRoute()) }
                        .accessibilityAction(named: "Open Subscriptions") { path.append(SubscriptionsRoute()) }
                    }
                }
                .dashboardLeadingRegion()
            } else if showSkeleton {
                VStack(spacing: 8) {
                    ForEach(0 ..< 2, id: \.self) { _ in
                        AO3WorkRowSkeleton()
                            .padding(.horizontal, 16)
                    }
                }
                .dashboardLeadingRegion()
            } else if visibleEntries.isEmpty {
                SectionEmptyState(
                    message: HomeSubscriptionsCopy.emptyMessage(
                        isLoggedIn: auth.isLoggedIn,
                        loadFailed: subscriptionsLoadFailed
                    ),
                    systemImage: "bell"
                )
                .padding(.horizontal, 16)
                .dashboardLeadingRegion()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider()
                                .padding(.leading, newChapterRowInset)
                        }
                        subscriptionRow(entry)
                    }

                    if visibleEntries.count > 2 {
                        Divider()
                            .padding(.leading, newChapterRowInset)
                        ListMoreRow(
                            count: visibleEntries.count - 2,
                            sectionTitle: "Subscriptions",
                            leadingInset: newChapterRowInset,
                            action: { path.append(SubscriptionsRoute(tab: .following)) }
                        )
                    }
                }
                .dashboardLeadingRegion()
            }
        }
    }

    @ViewBuilder
    private func subscriptionRow(_ entry: CanonicalWork) -> some View {
        if let work = entry.local {
            HomeNewChapterRow(
                work: work,
                isSelecting: isSelecting,
                isSelected: selection.contains(work.id),
                onToggleSelection: { toggleSelection(work) },
                onSelect: selectAction(for: work)
            )
        } else if let remote = entry.remote {
            HomeNewChapterRow(remote: remote, onEnriched: noteEnrichedSubscription)
        }
    }

    private func noteEnrichedSubscription(_ enriched: AO3WorkSummary) {
        guard let index = subscriptions.firstIndex(where: { $0.id == enriched.id }) else { return }
        subscriptions[index] = enriched
    }

    private func loadSubscriptions() async {
        // No request happens when signed out (accountWorks early-returns), so don't
        // raise the loading flag — the signed-out empty state should show immediately.
        guard auth.isLoggedIn else {
            subscriptions = []
            subscriptionsListCount = nil
            subscriptionsLoadFailed = false
            isLoadingSubscriptions = false
            return
        }
        isLoadingSubscriptions = true
        // Whose list this is. An answer that arrives after Sign Out (the task is cancelled,
        // but an await that already has its value still returns it) used to put the
        // signed-out reader's Home back under the account's private list (audit A19-5).
        let generation = auth.sessionGeneration
        do {
            let loaded = try await auth.accountSubscriptions()
            guard !Task.isCancelled, auth.isLoggedIn, auth.sessionGeneration == generation else {
                // Not this session's answer. Signed out: the signed-out pass clears the shelf.
                // Still signed in (Verify Session moved the session on): nothing else would
                // ask again, and the skeleton stayed up for good (audit A20-6).
                isLoadingSubscriptions = false
                if !Task.isCancelled, auth.isLoggedIn { await loadSubscriptions() }
                return
            }
            subscriptions = loaded
            subscriptionsListCount = AO3AccountListCountsCache.shared.count(
                for: .subscriptions,
                authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
            )
            subscriptionsLoadFailed = false
        } catch {
            // A refresh failure (network, rate limit, expired session) must not wipe
            // out a previously successful fetch — keep showing what's already there.
            // With nothing to show, the empty state says the load failed instead —
            // unless the task was cancelled (sign-out, tab switch), which is no failure.
            if subscriptions.isEmpty, !Task.isCancelled { subscriptionsLoadFailed = true }
            Log.network.notice(
                "Subscriptions refresh failed: \(UserFacingError.message(for: error), privacy: .public)"
            )
        }
        isLoadingSubscriptions = false
    }

    private func refreshHome() async {
        _ = await WorkMetadataRefresh.refresh(visibleHomeWorks, in: context, auth: auth)
        await loadSubscriptions()
        #if os(iOS)
        // The Subscriptions rows above can come from mail; reading it asks AO3 for nothing.
        await mailDriver.refresh()
        #endif
    }

    private var visibleHomeWorks: [SavedWork] {
        unique(
            Array(readingNow.prefix(4))
                + Array(recentlyUpdated.prefix(3))
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

    /// False keeps the sheet open: the queue did not save (`NewReadingQueueSheet` says so).
    private func createQueue(_ options: NewQueueOptions) -> Bool {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        _ = ReadingQueueService.createQueue(
            named: trimmed,
            hue: newQueueHue,
            colorHex: options.colorHex,
            keepsWorksOffline: options.keepsWorksOffline,
            seededFrom: options.seed,
            tagNames: options.tagNames,
            seedWorkIDs: options.seedWorkIDs,
            in: context
        )
        // `createQueue` saved best-effort; this asks whether that stuck (a no-op when it
        // did). Unsaved, the half-made queue is dropped so a second Create can't make two.
        guard context.saveBestEffort(reason: "Saving reading queue failed") else {
            context.rollback()
            return false
        }
        newQueueName = ""
        newQueueHue = nil
        showingNewQueue = false
        return true
    }

    // MARK: Card details

    private func footer(_ kind: HomeSectionKind, _ work: SavedWork) -> String? {
        switch kind {
        case .readingNow:
            return WorkReadingPosition.cardProgressLabel(progress: work.publicationProgress)
        case .recentlyUpdated:
            let new = work.postedChapterCount - work.knownChapterCount
            return new > 0 ? "+\(new) new" : "Updated"
        }
    }

    /// Reading progress (0…1) for Reading Now cards: position over the work's AO3
    /// chapter count, falling back to the in-chapter scroll fraction.
    private func progress(_ kind: HomeSectionKind, _ work: SavedWork) -> Double? {
        kind == .readingNow ? work.readingProgress : nil
    }
}

private struct HomeProfileAvatar: View {
    let url: URL?
    let username: String?
    /// The account's identity colour (board 56: a solid circle). Nil keeps the tinted fallback.
    let identity: SubjectPalette?

    @Environment(\.accentFill) private var accentFill
    @Environment(\.accentInk) private var accentInk
    @State private var cachedImage: Image?

    var body: some View {
        Group {
            if let cachedImage {
                cachedImage.resizable().scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: 30, height: 30)
        .background(identity?.accent ?? accentFill.opacity(0.16))
        .clipShape(Circle())
        .task(id: url) { cachedImage = Self.cachedImage(for: url) }
    }

    /// Home chrome is cache-only: if the profile screen's image load is not in
    /// URLCache, initials are more honest than issuing a decorative request.
    private static func cachedImage(for url: URL?) -> Image? {
        guard let url,
              let data = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data
        else { return nil }
        #if os(iOS)
        return UIImage(data: data).map(Image.init(uiImage:))
        #elseif os(macOS)
        return NSImage(data: data).map(Image.init(nsImage:))
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private var fallback: some View {
        if let initial = username?.first {
            Text(String(initial).uppercased())
                .font(.system(size: 15, weight: .bold, design: .rounded))
                // Black or white by contrast: Dark/OLED's identity accent is a light tint.
                .foregroundStyle(identity?.labelOnAccent ?? accentInk)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(.primary)
        }
    }
}

private struct HomeNewChapterRow: View {
    var work: SavedWork?
    var remote: AO3WorkSummary?
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    var onSelect: (() -> Void)?
    var onEnriched: ((AO3WorkSummary) -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure
    @AppStorage(WorkSymbolPlacement.storageKey) private var symbolPlacement: WorkSymbolPlacement = .defaultValue

    @State private var enrichedRemote: AO3WorkSummary?
    /// Measured chapter lengths for a downloaded work (word-count bar heights).
    @State private var chapterLengths: ChapterLengths?

    init(
        work: SavedWork,
        isSelecting: Bool = false,
        isSelected: Bool = false,
        onToggleSelection: (() -> Void)? = nil,
        onSelect: (() -> Void)? = nil
    ) {
        self.work = work
        self.remote = nil
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.onToggleSelection = onToggleSelection
        self.onSelect = onSelect
        self.onEnriched = nil
    }

    init(
        remote: AO3WorkSummary,
        onSelect: (() -> Void)? = nil,
        onEnriched: ((AO3WorkSummary) -> Void)? = nil
    ) {
        self.work = nil
        self.remote = remote
        self.isSelecting = false
        self.isSelected = false
        self.onToggleSelection = nil
        self.onSelect = onSelect
        self.onEnriched = onEnriched
    }

    private var displayedRemote: AO3WorkSummary? {
        enrichedRemote ?? remote
    }

    private var blurred: Bool {
        if let work {
            return gate.isBlurred(work, enabled: hideMature, mode: mode)
        }
        return displayedRemote.map { gate.isBlurred($0, enabled: hideMature, mode: mode) } ?? false
    }

    private var isHidden: Bool {
        if let work {
            return gate.isHidden(work, enabled: hideMature, mode: mode)
        }
        return displayedRemote.map { gate.isHidden($0, enabled: hideMature, mode: mode) } ?? false
    }

    private var newCount: Int {
        if let work {
            return max(0, work.postedChapterCount - work.knownChapterCount)
        }
        if let displayedRemote {
            return SubscriptionWatermarks.newChapterCount(
                for: displayedRemote,
                watermarks: SubscriptionWatermarks.load()
            )
        }
        return 0
    }

    private var rowTitle: String {
        work?.title ?? displayedRemote?.title ?? ""
    }

    private var rowRating: String? {
        if let rating = work?.rating, !rating.isEmpty { return rating }
        if let rating = displayedRemote?.rating, !rating.isEmpty { return rating }
        return nil
    }

    private var rowCategories: [String] {
        work?.workCategories ?? displayedRemote?.categories ?? []
    }

    private var rowWarnings: [String] {
        work?.workWarnings ?? displayedRemote?.warnings ?? []
    }

    private var rowCompletion: WorkCompletionStatus {
        if let status = work?.completionStatus { return status }
        if let displayedRemote {
            return WorkCompletionStatus(isComplete: displayedRemote.isComplete)
        }
        return .unknown
    }

    private var metaText: String {
        if let work {
            let author = work.author.trimmingCharacters(in: .whitespacesAndNewlines)
            let fandom = work.workFandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map(FandomDisplayName.bareTitle)
            let storedDate = work.dateUpdated.trimmingCharacters(in: .whitespacesAndNewlines)
            let when = storedDate.isEmpty ? nil : WorkStat.displayDate(storedDate)
            return [author.isEmpty ? nil : author, fandom, when]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
        if let remote = displayedRemote {
            let author = remote.authorText.trimmingCharacters(in: .whitespacesAndNewlines)
            let fandom = remote.fandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map(FandomDisplayName.bareTitle)
            let storedDate = remote.dateUpdated.trimmingCharacters(in: .whitespacesAndNewlines)
            let when = storedDate.isEmpty ? nil : WorkStat.displayDate(storedDate)
            return [author.isEmpty ? nil : author, fandom, when]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
        return ""
    }

    private var chapterBarItems: [ChapterBarItem] {
        if let work {
            return ChapterBarModel.items(
                chapters: work.chapters,
                progress: work.readingProgress,
                isFinished: work.isFinished,
                weights: chapterLengths?.positions,
                heights: chapterLengths?.words,
                newChapterCount: newCount
            )
        }
        if let remote = displayedRemote {
            return ChapterBarModel.items(
                chapters: remote.chapters,
                progress: nil,
                isFinished: remote.isComplete == true,
                weights: nil,
                newChapterCount: newCount
            )
        }
        return []
    }

    var body: some View {
        Group {
            if isHidden {
                EmptyView()
            } else if let work {
                localBody(work: work)
            } else if let remote = displayedRemote {
                remoteBody(remote: remote)
            }
        }
        .task(id: remote?.id) {
            if let remote {
                let result = await AO3SparseWorkEnricher.shared.enrich(remote)
                enrichedRemote = result
                if let result { onEnriched?(result) }
            }
        }
    }

    @ViewBuilder
    private func localBody(work: SavedWork) -> some View {
        Group {
            if blurred {
                obscuredBody { gate.reveal(work) }
            } else if isSelecting {
                Button { onToggleSelection?() } label: { rowContent }
                    .buttonStyle(.plain)
                    .localWorkContextMenu(work: work, onSelect: onSelect)
                    .accessibilityLabel(work.title)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                NavigationLink(value: LocalWorkDestination.reader(work)) {
                    rowContent
                }
                .buttonStyle(.plain)
                .localWorkContextMenu(work: work, onSelect: onSelect)
            }
        }
        .downloadDimmed(work)
        .task(id: ChapterLengthCache.taskKey(for: work)) {
            chapterLengths = await ChapterLengthCache.lengths(for: work)
        }
    }

    @ViewBuilder
    private func remoteBody(remote: AO3WorkSummary) -> some View {
        if blurred {
            obscuredBody { gate.reveal(remote) }
        } else {
            NavigationLink(value: remote) {
                rowContent
            }
            .buttonStyle(.plain)
            .remoteWorkContextMenu(work: remote)
        }
    }

    @ViewBuilder
    private func obscuredBody(reveal: @escaping () -> Void) -> some View {
        let content = rowContent
            .blur(radius: 6)
            .overlay {
                if !isSelecting { MatureRevealCapsule() }
            }
            .contentShape(Rectangle())
        if isSelecting {
            Button { onToggleSelection?() } label: {
                content.overlay(alignment: .leading) {
                    WorkSelectionBubble(isSelected: isSelected)
                        .padding(.leading, 16)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hidden mature work")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
        } else {
            Button(action: reveal) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden mature work")
                .accessibilityHint("Activate to reveal.")
        }
    }

    private func rowSymbols(_ arrangement: WorkStatusIconGrid.Arrangement) -> some View {
        WorkStatusIconGrid(
            rating: rowRating,
            categories: rowCategories,
            warnings: rowWarnings,
            completion: rowCompletion,
            tileSize: 24,
            announcesToVoiceOver: true,
            arrangement: arrangement,
            backed: true
        )
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            if isSelecting {
                WorkSelectionBubble(isSelected: isSelected)
                    .opacity(blurred ? 0 : 1)
            }

            if symbolPlacement == .beside {
                rowSymbols(.grid)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rowTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                if symbolPlacement == .underTitle {
                    rowSymbols(.row)
                }

                ChapterBars(
                    items: chapterBarItems,
                    scale: .row,
                    height: 16
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(metaText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                if let preservation = work?.preservationState.badgeLabel {
                    WorkStateBadge(text: preservation, symbol: work?.preservationState.badgeSymbol ?? "")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WorkPlusBadge(count: newCount)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct HomeQueueRow: View {
    let queue: ReadingQueue
    let onOpenQueue: () -> Void
    let onStartWork: (SavedWork) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @Environment(\.accentFill) private var accentFill
    /// The up-next work's measured chapters, so its "Ch N" matches its bars elsewhere.
    @State private var upNextLengths: ChapterLengths?

    private var queuedWorks: [SavedWork] {
        ReadingQueueService.orderedWorks(in: queue)
    }

    private var visibleQueuedWorks: [SavedWork] {
        queuedWorks.filter { !gate.isConcealed($0, enabled: hideMature) }
    }

    private var upNextWork: SavedWork? {
        ReadingQueueFacts.upNext(in: visibleQueuedWorks).upNext
    }

    private var worksBehind: [SavedWork] {
        let split = ReadingQueueFacts.upNext(in: visibleQueuedWorks)
        var ordered = split.inLine
        if let upNext = split.upNext { ordered.insert(upNext, at: 0) }
        return Array(ordered.prefix(CoverStackLayout.maxBacks))
    }

    private var leftCount: Int {
        queuedWorks.filter { !$0.isFinished }.count
    }

    private var isResume: Bool {
        guard let upNextWork else { return false }
        return (upNextWork.readingProgress ?? 0) > 0 || upNextWork.readingState == .inProgress
    }

    private var actionTitle: String {
        isResume ? "Resume" : "Start"
    }

    private var metaLine: String {
        guard let work = upNextWork else { return "No works" }
        var parts: [String] = []
        let author = work.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty { parts.append(author) }
        if isResume {
            if let progress = work.readingProgress, progress > 0 {
                parts.append(WorkCoverMetadata.reading(
                    chapters: work.chapters, progress: progress, weights: upNextLengths?.positions
                ))
            } else if !work.chapters.isEmpty {
                parts.append("Ch \(work.chapters)")
            }
        } else {
            if work.wordCount > 0 {
                parts.append("\(work.wordCount.formatted()) words")
                if let estimate = ReadingQueueFacts.readingTimeEstimate(wordCount: work.wordCount) {
                    parts.append(estimate)
                }
            }
            if !work.hasEPUB {
                parts.append("not downloaded")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: queue.displayHue, pickedHex: queue.colorHex)
    }

    private var queueProgress: ReadingQueueFacts.Progress {
        ReadingQueueFacts.progress(of: queuedWorks.map(\.readingState))
    }

    private var queueFills: [Double] {
        queuedWorks.map {
            ReadingQueueFacts.segmentFill(state: $0.readingState, progress: $0.readingProgress)
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        coverButton
                        detailsButton
                    }
                    if upNextWork != nil {
                        HStack {
                            Spacer(minLength: 0)
                            startButton
                        }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    coverButton
                    detailsButton
                    startButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .modifier(QueueCardMenu(queue: queue))
        .task(id: ChapterLengthCache.taskKey(for: upNextWork)) {
            guard let upNextWork else { upNextLengths = nil; return }
            upNextLengths = await ChapterLengthCache.lengths(for: upNextWork)
        }
    }

    private var coverButton: some View {
        Button(action: onOpenQueue) {
            StackedWorkCover(
                kind: .queue,
                name: queue.displayName,
                hue: queue.displayHue,
                pickedHex: queue.colorHex,
                backs: worksBehind,
                size: CGSize(width: 52, height: 52)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private var detailsButton: some View {
        Button(action: onOpenQueue) {
            VStack(alignment: .leading, spacing: 1) {
                Text(queue.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                // Two lines before it truncates: the offline count is the last fact.
                Text(ReadingQueueFacts.planFacts(for: queuedWorks))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let work = upNextWork {
                    Text(work.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                    HStack(spacing: 8) {
                        QueueProgressStrip(
                            progress: queueProgress,
                            palette: palette,
                            fills: queueFills,
                            height: 4,
                            gap: 3
                        )
                        .frame(maxWidth: .infinity)

                        Text("\(leftCount) to go")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)

                    Text(metaLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                } else {
                    Text(queuedWorks.isEmpty ? "Empty queue" : "Works hidden")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var startButton: some View {
        if let work = upNextWork {
            Button(action: { onStartWork(work) }) {
                Text(actionTitle)
                    .font(.subheadline.weight(.semibold))
                    // The theme's app colour (Sepia brown), not the fixed asset red.
                    .foregroundStyle(.accentInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(accentFill.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(actionTitle) \(work.title)")
        }
    }
}
