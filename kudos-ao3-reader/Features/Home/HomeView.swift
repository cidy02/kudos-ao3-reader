import OSLog
import SwiftData
import SwiftUI

/// The Home tab: a personal, Books-style dashboard. Every section is a collapsible
/// horizontal card carousel with a `>` chevron that opens its full vertical list.
/// Tapping a local card opens the reader; long-press opens management actions,
/// including Work Details. Remote cards still tap through to Work Details.
/// Sections, in order: Resume (hero+strip), Reading Queues, Recently Updated,
/// Subscriptions.
struct HomeView: View { // swiftlint:disable:this type_body_length
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    /// Same key `WorkCarouselSection` used to persist this strip's collapse
    /// state, kept unchanged — only the toggle affordance moved (onto
    /// "Continue Reading"), not the state itself.
    @AppStorage("section.collapsed.home.readingNow.strip") private var stripCollapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var works: [SavedWork]
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var readingQueues: [ReadingQueue]
    @State private var path = NavigationPath()
    @Namespace private var cardZoomNamespace
    @State private var subscriptions: [AO3WorkSummary] = []
    /// True only while the remote subscriptions request is actually in flight, so the
    /// carousel can show cover skeletons instead of briefly flashing its empty state.
    @State private var isLoadingSubscriptions = false
    @State private var showingNewQueue = false
    @State private var newQueueName = ""

    // Multi-select / bulk actions, mirroring LibraryView's carousel selection.
    // Scoped to local works (Resume hero+strip + Recently Updated) — Subscriptions
    // merges in remote entries via CanonicalWorkCoverCard, a different card type
    // not wired for selection here.
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()

    // Section cache — same rationale as LibraryView: don't re-filter every
    // carousel on every body pass while Liquid Glass is mid-morph.
    @State private var sectionCache: [HomeSectionKind: [SavedWork]] = [:]
    @State private var hasSectionCache = false

    /// Route marker so the Subscriptions header can push the full AO3 list.
    private struct SubscriptionsRoute: Hashable {}

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

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hasSectionCache {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            resumeSection
                            readingQueuesCarousel
                            localSection(.recentlyUpdated, works: recentlyUpdated)
                            subscriptionsSection
                        }
                        .padding(.vertical, 12)
                    }
                    .refreshable { await refreshHome() }
                } else {
                    TabDashboardShell(
                        sectionTitles: [
                            "Reading Now", "Reading Queues", "Recently Updated",
                            "Subscriptions"
                        ]
                    )
                }
            }
            .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle("Home")
            #if os(iOS)
                .toolbarTitleDisplayMode(.inlineLarge)
            #endif
                .navigationDestination(for: SavedWork.self) { HomeWorkDestination(work: $0) }
                .navigationDestination(for: LocalWorkDestination.self) { destination in
                    LocalWorkDestinationView(destination: destination, onReaderOpen: markUpdateSeen)
                }
                // Still live for Recently Updated (`localSection` → path.append(kind)).
                // Resume "See all" intentionally does NOT use this: it deep-links into
                // Library via `router.showLibrarySection(.readingNow)` so the full list
                // lives on Library's stack (Phase A contract). `.readingNow` remains a
                // valid HomeSectionKind for section cache / empty copy; the destination
                // case is simply unreached from current Home chrome, not orphaned wiring.
                .navigationDestination(for: HomeSectionKind.self) { kind in
                    HomeSectionListView(kind: kind, initialSelecting: isSelecting, initialSelection: selection)
                }
                .navigationDestination(for: AO3WorkSummary.self) { WorkDetailView(remote: $0) }
                .navigationDestination(for: SubscriptionsRoute.self) { _ in AO3AccountWorksList(kind: .subscriptions) }
                .navigationDestination(for: AllReadingQueuesDestination.self) { destination in
                    // Chevron passes nil → stack grid (owns its own New Queue sheet).
                    // A specific queue id opens the Safari-style browser.
                    if destination.initialQueueID == nil {
                        AllReadingQueuesGridView()
                    } else {
                        ReadingQueueBrowserView(initialQueueID: destination.initialQueueID)
                    }
                }
                .ao3AuthorNavigation(path: $path, tab: .home)
                .task(id: homeSectionsRevision) {
                    await Task.yield()
                    rebuildHomeSectionCache()
                }
                .task(id: auth.isLoggedIn) {
                    await Task.yield()
                    await loadSubscriptions()
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
                        if PrivacyGate.hasVisibleMatureWorks(in: selectedWorks, hideMature: hideMature) {
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
                    } else if PrivacyGate.hasVisibleMatureWorks(in: allLocalSectionWorks, hideMature: hideMature)
                        || !allLocalSectionWorks.isEmpty {
                        // Gated as a whole, not just its inner pieces — an empty HStack
                        // still reserves an (empty-looking) toolbar slot, which is
                        // exactly what showed a blank button when the Library was empty.
                        ActionToolbar(items: [
                            PrivacyGate.hasVisibleMatureWorks(in: allLocalSectionWorks, hideMature: hideMature)
                                ? AnyView(MatureRevealToggle())
                                : nil,
                            !allLocalSectionWorks.isEmpty
                                ? AnyView(WorkListMoreMenu {
                                    Button {
                                        enterSelectMode()
                                    } label: {
                                        Label("Select", systemImage: "checklist")
                                    }
                                })
                                : nil
                        ].compactMap { $0 })
                    }
                }
                // Sheet for the dashboard carousel's New Queue card — same reliability
                // reasons as AllReadingQueuesGridView / ReadingQueueBrowserView.
                .sheet(isPresented: $showingNewQueue) {
                    NavigationStack {
                        Form {
                            TextField("Name", text: $newQueueName)
                                #if os(iOS)
                                .textInputAutocapitalization(.words)
                                #endif
                        }
                        .navigationTitle("New Queue")
                        #if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    newQueueName = ""
                                    showingNewQueue = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Create") { createQueue() }
                                    .disabled(newQueueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    #if os(iOS)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    #endif
                }
        }
        // Declared on the stack itself so the cards inside it and the screens
        // pushed from it resolve the same namespace — that pairing is what the
        // zoom transition matches on.
        .environment(\.workCardTransitionNamespace, cardZoomNamespace)
    }

    // MARK: Sections

    private var resumeSection: some View {
        Group {
            if readingNow.isEmpty {
                // Strong empty state (Synthesis v2): section chrome + CTAs, not a
                // dead hero-shaped hole. Same header weight as other Home rows.
                VStack(alignment: .leading, spacing: 12) {
                    // "Continue Reading" — matches the title used above the hero
                    // in the non-empty branch below, so the section doesn't
                    // appear to rename itself depending on whether it has content.
                    Text("Continue Reading")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)

                    SectionEmptyState(
                        message: HomeSectionKind.readingNow.emptyMessage,
                        systemImage: HomeSectionKind.readingNow.emptyIcon
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Button("Browse AO3") {
                            router.selection = .browse
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open Library") {
                            router.selection = .library
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                // Hero = most recent; strip = next up to 4 (5 visible total).
                // "See all" only when a 6th+ work exists beyond that window.
                let heroWork = readingNow[0]
                let stripWorks = Array(readingNow.dropFirst().prefix(4))

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        // The "More In Progress" strip's own collapse toggle moved
                        // here — it's this row's chevron now, not a separate
                        // header sitting between the hero and the strip.
                        Group {
                            if stripWorks.isEmpty {
                                Text("Continue Reading")
                            } else {
                                Button {
                                    withAnimationUnlessReduced(.snappy(duration: 0.22), reduceMotion: reduceMotion) {
                                        stripCollapsed.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("Continue Reading")
                                        Image(systemName: "chevron.down")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                            .rotationEffect(.degrees(stripCollapsed ? -90 : 0))
                                    }
                                }
                                .buttonStyle(.plain)
                                .minimumHitTarget()
                                .accessibilityLabel(
                                    stripCollapsed ? "Expand More In Progress" : "Collapse More In Progress"
                                )
                            }
                        }
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        if readingNow.count > 5 {
                            Button {
                                router.showLibrarySection(.readingNow)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .minimumHitTarget()
                            .accessibilityLabel("See all in progress")
                        }
                    }
                    .padding(.horizontal, 16)

                    HomeResumeHero(
                        work: heroWork,
                        isSelecting: isSelecting,
                        isSelected: selection.contains(heroWork.id),
                        onToggleSelection: { toggleSelection(heroWork) },
                        onSelect: selectAction(for: heroWork)
                    )
                    .padding(.horizontal, 16)

                    if !stripWorks.isEmpty, !stripCollapsed {
                        // Same compact portrait card every other Home carousel uses
                        // (see localSection below), not the wide book-row strip this
                        // used to be. SensitiveWorkCoverCard doesn't wrap its own
                        // NavigationLink/selection handling, so both branches are
                        // spelled out here, matching localSection's pattern exactly.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(stripWorks) { work in
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
                            .uniformWorkCardHeights()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    /// Moved here from the Library dashboard — Reading Queues sits right under
    /// Continue Reading rather than several sections down Library, since a queue
    /// is itself a reading plan (what to read next), the same territory as the
    /// hero above it.
    private var readingQueuesCarousel: some View {
        let customQueues = readingQueues
            .filter { $0.kind == .custom }
            .sorted { $0.sortOrder < $1.sortOrder }
        return WorkCarouselSection(
            title: "Reading Queues",
            collapseKey: "home.readingQueues",
            hasItems: true,
            onSeeAll: !customQueues.isEmpty
                ? { path.append(AllReadingQueuesDestination(initialQueueID: nil)) }
                : nil
        ) {
            Button {
                newQueueName = ""
                showingNewQueue = true
            } label: {
                NewReadingQueueCard()
            }
            .buttonStyle(.plain)

            ForEach(customQueues.prefix(12)) { queue in
                NavigationLink(value: AllReadingQueuesDestination(initialQueueID: queue.id)) {
                    ReadingQueueCard(queue: queue)
                }
                .buttonStyle(.plain)
            }
        } emptyState: {
            EmptyView()
        }
    }

    private func localSection(_ kind: HomeSectionKind, works sectionWorks: [SavedWork]) -> some View {
        WorkCarouselSection(
            title: kind.title,
            collapseKey: "home.\(kind.rawValue)",
            hasItems: !sectionWorks.isEmpty,
            onSeeAll: sectionWorks.count > 1 ? { path.append(kind) } : nil
        ) {
            ForEach(sectionWorks.prefix(12)) { work in
                if isSelecting {
                    SensitiveWorkCoverCard(
                        work: work,
                        footer: footer(kind, work),
                        progress: progress(kind, work),
                        isSelecting: true,
                        isSelected: selection.contains(work.id),
                        onToggleSelection: { toggleSelection(work) }
                    )
                    .localWorkContextMenu(work: work, onSelect: selectAction(for: work))
                } else {
                    NavigationLink(value: LocalWorkDestination.reader(work)) {
                        SensitiveWorkCoverCard(
                            work: work,
                            footer: footer(kind, work),
                            progress: progress(kind, work)
                        )
                    }
                    .buttonStyle(.plain)
                    .localWorkContextMenu(work: work, onSelect: selectAction(for: work))
                }
            }
        } emptyState: {
            SectionEmptyState(message: kind.emptyMessage, systemImage: kind.emptyIcon)
        }
    }

    private var subscriptionsSection: some View {
        // Show cover skeletons only while the request is in flight and we have nothing
        // yet; once it finishes (empty or not) the real cards / empty state take over.
        let showSkeleton = isLoadingSubscriptions && subscriptions.isEmpty
        // A subscribed work that's also saved locally renders once, as its richer
        // local card, in AO3's own subscription order. Matching only against
        // privacy-visible works so a hidden Mature work isn't leaked via its
        // local card here.
        let merged = CanonicalWorkMerge.remoteLed(
            remote: subscriptions,
            localLibrary: works.filter(passesPrivacy)
        )
        return WorkCarouselSection(
            title: "Subscriptions",
            collapseKey: "home.subscriptions",
            hasItems: !merged.isEmpty || showSkeleton,
            onSeeAll: merged.isEmpty ? nil : { path.append(SubscriptionsRoute()) }
        ) {
            if showSkeleton {
                ForEach(0 ..< 6, id: \.self) { _ in WorkCoverCardSkeleton() }
            } else {
                ForEach(merged.prefix(12)) { entry in
                    CanonicalWorkCoverCard(entry: entry)
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

    private func createQueue() {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newQueueName = ""
        showingNewQueue = false
        _ = ReadingQueueService.createQueue(named: trimmed, in: context)
    }

    // MARK: Card details

    private func footer(_ kind: HomeSectionKind, _ work: SavedWork) -> String? {
        switch kind {
        case .readingNow:
            return work.readingProgressLabel
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
