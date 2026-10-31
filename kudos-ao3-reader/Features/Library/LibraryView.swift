import OSLog
import SwiftData
import SwiftUI

// Lint: this existing dashboard owns many stateful sections.
/// The Library tab. The reader chooses which shelves are sections (a carousel or
/// ledger rows) and which are buttons in the Shelves grid. The default is
/// Favourites, Collections, then Downloaded, as carousels. All Works stays in
/// the header. Saved for Later is the Want to Read shelf; AO3-managed lists live
/// in the On AO3 group and never become local queue membership.
///
/// Filtering (the inspector panel), Reading Insights, content privacy, and
/// multi-select bulk actions (all platforms) are kept from the previous
/// list-based Library.
struct LibraryView: View { // swiftlint:disable:this type_body_length
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var works: [SavedWork]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(
        filter: #Predicate<WorkCollection> { !$0.isPendingDeletion },
        sort: \WorkCollection.dateAdded, order: .reverse
    )
    private var collections: [WorkCollection]
    // Counts only — RecentlyDeletedView does its own full @Query for the actual list.
    @Query(filter: #Predicate<SavedWork> { $0.isPendingDeletion }) private var deletedWorks: [SavedWork]
    @Query(filter: #Predicate<WorkCollection> { $0.isPendingDeletion }) private var deletedCollections: [WorkCollection]
    @Query(filter: #Predicate<ReadingQueue> { $0.isPendingDeletion }) private var deletedQueues: [ReadingQueue]
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }) private var readingQueues: [ReadingQueue]
    /// `library.dashboard.layout` is left in UserDefaults and never read. Which
    /// shelves are sections, and carousel or list, is `pageArrangement`.
    @AppStorage(LibraryPageArrangement.storageKey) private var pageArrangement = LibraryPageArrangement.default
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @State private var path = NavigationPath()
    @Namespace private var cardZoomNamespace
    @State private var filters = LibraryFilters()
    @State private var showingNewCollection = false
    @State private var showingEditShelves = false
    @State private var importedCache: [SavedWork] = []
    @State private var libraryHeader = LibraryHeaderFacts()
    @State private var filteredDownloadedBytes: Int64 = 0

    @ScaledMetric(relativeTo: .footnote) private var recentlyDeletedTitleSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var recentlyDeletedCountSize: CGFloat = 13

    // MARK: Section cache
    //
    // Filtering the whole library for every carousel on every body pass was
    // hitching Liquid Glass tab switches. Rebuild once when data/filters change;
    // carousels read the cache.

    @State private var sectionCache: [LibrarySectionKind: [SavedWork]] = [:]
    @State private var topFandomsCache: [String] = []
    @State private var hasSectionCache = false

    // Multi-select / bulk actions — a plain cross-platform Bool, the same pattern
    // `LibrarySectionListView` already uses (its `EditMode`-free `isSelecting`
    // state works identically on iOS and macOS). This used to be a local,
    // never-bound `EditMode` on this dashboard specifically (never attached to any
    // List's `\.editMode` environment, so wrapping it in `#if os(iOS)` bought
    // nothing but an accidental macOS gap): the dashboard's own select-mode list,
    // card-selection bubbles, and toolbar "Select" entry were all `#if os(iOS)`
    // besides, so macOS had no way to enter bulk-select at all (HIG audit UI-7).
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var showingSelectionList = false
    /// Tracks the select-mode list's in-flight refresh so it can be cancelled if the
    /// user switches tabs (see `cancelRefreshOnTabChange`) — this can be the whole Library.
    @State private var refreshTask: Task<Void, Never>?

    /// Selection acts on what is on screen, as the queue browser and the section
    /// lists already do (L3 B2 #1). A fandom chip or the privacy toggle used during
    /// Select hid rows that stayed selected, and Delete took them unseen (audit A12-4).
    private var selectedWorks: [SavedWork] {
        selectableWorks.filter { selection.contains($0.id) }
    }

    /// Keeps privacy-hidden works out of aggregate counts and fandom labels.
    private var statisticsWorks: [SavedWork] {
        works.filter { !$0.isQueueOnlyWork && (!hideMature || !$0.isAdult || gate.isRevealed($0)) }
    }

    /// The dashboard's currently-visible/filtered works (mirrors `dashboardWorks(for:)`
    /// minus its `.prefix(12)` truncation, which would wrongly hide the Privacy button
    /// if an adult work sat outside the first 12 in every section) — what the main
    /// toolbar's Privacy button condition should actually check.
    private var visibleDashboardWorksUnbounded: [SavedWork] {
        filters.apply(to: works.filter { !$0.isQueueOnlyWork })
    }

    private var recentlyDeletedCount: Int {
        deletedWorks.count + deletedCollections.count + deletedQueues.count
    }

    /// Drops Mature/Explicit works in Hide mode (until revealed); Blur mode keeps them
    /// in the list but `SensitiveWorkRow` blurs them.
    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    /// The user's own tag names, for the filter panel's "Your Tags" facet.
    private var userTagNames: [String] {
        tags.map(\.name)
    }

    // Extracted out of `body`'s `.navigationDestination` chain (rather than inlined
    // as trailing closures) with an explicit `some View` return type — that chain is
    // already a long compound expression, and inlining these left the compiler
    // unable to type-check it in reasonable time (a hard build failure), not just slow.
    private var collectionsGridDestination: some View {
        LibraryEntityGridView(
            title: "Collections",
            items: collections,
            destination: { $0 },
            onNew: {
                showingNewCollection = true
            },
            card: { CollectionCard(collection: $0).collectionCardMenu($0) }
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isSelecting && showingSelectionList {
                    DashboardRegionHost { selectList.dashboardLeadingRegion(fillsHeight: true) }
                } else {
                    dashboard
                }
            }
            .scrollAwayTopChrome()
            .background(themeManager.appTheme.contentBackdrop.ignoresSafeArea())
            .navigationTitle(isSelecting ? WorkSelectionTitle.text(selectedCount: selectedWorks.count) : "Library")
            #if os(iOS)
                .toolbarTitleDisplayMode(.inlineLarge)
            #endif
                .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
                .navigationDestination(for: LocalWorkDestination.self) { LocalWorkDestinationView(destination: $0) }
                .navigationDestination(for: LibrarySectionRoute.self, destination: sectionList)
                .navigationDestination(for: WorkCollection.self) { CollectionDetailView(collection: $0) }
                .navigationDestination(for: ReadingQueue.self) { ReadingQueueDetailView(queue: $0) }
                .navigationDestination(for: AO3WorkSummary.self) { WorkDetailView(remote: $0) }
                .navigationDestination(for: LibraryAO3Route.self) { route in
                    AO3AccountWorksList(kind: route.kind, originKicker: "Library")
                }
                .ao3AuthorNavigation(path: $path, tab: .library)
                .navigationDestination(for: RecentlyDeletedDestination.self) { _ in RecentlyDeletedView() }
                .navigationDestination(for: ReadingInsightsDestination.self) { _ in
                    ReadingInsightsView(works: statisticsWorks)
                }
                #if DEBUG
                .task {
                    try? await Task.sleep(for: .seconds(1.5))
                    DebugLaunchRoute.applyLibrary(to: &path, collections: collections)
                    if DebugLaunchRoute.wantsSheet("libpicker") { router.panel = .libraryFilters }
                    if DebugLaunchRoute.takeSheet("newcollection") { showingNewCollection = true }
                    if DebugLaunchRoute.wantsSheet("bulktag") {
                        for work in works.filter({ !$0.isQueueOnlyWork }).prefix(2) {
                            selection.insert(work.id)
                        }
                        if !selection.isEmpty { isSelecting = true }
                    }
                }
                #endif
                .navigationDestination(for: AllCollectionsDestination.self) { _ in collectionsGridDestination }
                .navigationDestination(for: AllReadingQueuesDestination.self, destination: queuesDestination)
                .navigationDestination(for: LibraryCatalogueDestination.self, destination: catalogueDestination)
                .toolbar { toolbarContent }
            #if os(iOS)
                // Select mode owns the bottom edge with its bulk-action bar; the
                // floating tab/search glass hides meanwhile. Besides decluttering,
                // this keeps the selection UI's red accents from refracting through
                // the tab pill — Liquid Glass samples ambient color from surrounding
                // content, and solid accent-red on screen bled visible red rings onto
                // the (unrelated) tab icons whenever a selection was active.
                .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            #endif
                // 1bk draws a form — name, description, colour, and a Behaviour
                // group — not the bare name alert this replaced. One sheet
                // serves both entry points, which both flip the same flag.
                .sheet(isPresented: $showingNewCollection) {
                    NewCollectionSheet()
                }
                .sheet(isPresented: $showingEditShelves) {
                    LibraryEditShelvesSheet(
                        arrangement: $pageArrangement,
                        counts: shelfCounts,
                        allWorksCount: libraryHeader.workCount
                    )
                }
                // The shelf layout lives in UserDefaults, which the folder-sync
                // observer does not query. The notice it listens for marks the
                // folder dirty so the layout reaches the reader's other devices.
                .onChange(of: pageArrangement) { _, _ in
                    NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
                }
                .filterPanelPresentation(isPresented: router.isShowing(.libraryFilters)) {
                    // The lists are drawn from what the Library can show: not a work Hide
                    // mode hides (its fandoms and tags were offered here). A queue's
                    // entry stays: the Saved for Later shelf shows it.
                    LibraryFilterPanel(
                        filters: $filters,
                        works: works.filter(passesPrivacy),
                        userTagNames: userTagNames
                    )
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                }
                .task {
                    // ContentView already normalizes the full library at launch.
                    // Don't re-walk every SavedWork + fileExists when the Library
                    // tab first mounts — that was hitching Liquid Glass tab switches.
                    await Task.yield()
                    ReadingQueueService.ensureSavedForLaterQueue(in: context)
                    await backfillFilterMetadata()
                }
                .task(id: sectionsRevision) {
                    // Yield so the progressive tab shell (or prior frame) can paint
                    // before we spend the main actor filtering every section.
                    await Task.yield()
                    rebuildSectionCache()
                }
                // A tag tapped on a work's detail page filters the Library to it.
                // `initial: true` catches a tag set just before this view appears.
                .onChange(of: router.pendingLibraryTag, initial: true) { _, tag in
                    guard let tag else { return }
                    var applied = LibraryFilters()
                    switch tag.field {
                    case .userTag: applied.userTags = [tag.value]
                    case .fandom: applied.fandoms = [tag.value]
                    case .character: applied.characters = [tag.value]
                    case .relationship: applied.relationships = [tag.value]
                    case .additional: applied.additionalTags = [tag.value]
                    }
                    filters = applied
                    router.pendingLibraryTag = nil
                    // The filtered dashboard lives at the stack root — if a pushed
                    // screen (e.g. the Work Detail the tag was tapped on) is still on
                    // top, applying the filter here is otherwise invisible until the
                    // user separately backs all the way out.
                    path = NavigationPath()
                }
                // Home Resume "See all" (and future Account/widget deep-links) push a
                // Library section list. Reuses the same `LibrarySectionKind` destination
                // as the carousel chevrons — `initial: true` catches a section set just
                // before this view appears.
                .onChange(of: router.pendingLibrarySection, initial: true) { _, kind in
                    guard let kind else { return }
                    // Reset first, same as `pendingLibraryTag` above — without it, a
                    // deep-link arriving while the user is already mid-navigation
                    // elsewhere in Library (e.g. left inside a Collection before
                    // switching tabs) would stack the section list under whatever was
                    // already pushed instead of landing cleanly, or double-push the
                    // same kind if it happens to already be on the stack.
                    openDeepLinkedSection(kind)
                }
                .onChange(of: router.pendingLibraryAO3Route, initial: true) { _, route in
                    guard let route else { return }
                    path = NavigationPath()
                    path.append(route)
                    router.pendingLibraryAO3Route = nil
                }
        }
        // Declared on the stack itself so the cards inside it and the screens
        // pushed from it resolve the same namespace — that pairing is what the
        // zoom transition matches on.
        .environment(\.workCardTransitionNamespace, cardZoomNamespace)
    }

    /// Named rather than an inline closure, for the same reason as
    /// `openDeepLinkedSection` below: this body sits right at the edge of what
    /// Swift's type checker will solve, and a multi-argument closure inside the
    /// modifier chain pushed it over — the compile did not fail, it stopped
    /// terminating.
    private func sectionList(_ route: LibrarySectionRoute) -> some View {
        LibrarySectionListView(
            kind: route.kind,
            originKicker: route.originKicker,
            initialSelecting: isSelecting,
            initialSelection: selection
        )
    }

    @ViewBuilder
    private func queuesDestination(_ destination: AllReadingQueuesDestination) -> some View {
        if destination.initialQueueID == nil {
            AllReadingQueuesGridView()
        } else {
            ReadingQueueBrowserView(initialQueueID: destination.initialQueueID, originKicker: "Library")
        }
    }

    private func catalogueDestination(_ destination: LibraryCatalogueDestination) -> some View {
        LibraryCatalogueListView(kind: destination.kind)
    }

    /// Extracted from the `onChange` closure: inline, the added branch tipped this
    /// view's body past what the type checker would solve in reasonable time.
    private func openDeepLinkedSection(_ kind: LibrarySectionKind) {
        path = NavigationPath()
        let origin = router.pendingLibrarySectionOrigin ?? "Library"
        path.append(LibrarySectionRoute(kind: kind, originKicker: origin))
        router.pendingLibrarySection = nil
        router.pendingLibrarySectionOrigin = nil
    }

    // MARK: Dashboard

    /// Fingerprint of everything that should rebuild section slices. Kept coarse
    /// (counts + newest stamp + filter/privacy bits) so we don't re-filter on
    /// unrelated body passes, but still refresh when the user filters or reveals.
    private var sectionsRevision: String {
        let newest = Int(works.map(\.lastModifiedAt).max()?.timeIntervalSince1970 ?? 0)
        let lifecycleBits = works.reduce(into: 0) { partial, work in
            if work.isQueuedForLater { partial += 1 }
            if work.isSaved { partial += 2 }
            if work.isFinished { partial += 4 }
            if work.isFavorite { partial += 8 }
            if work.hasEPUB { partial += 16 }
        }
        return [
            "\(works.count)",
            "\(newest)",
            "\(lifecycleBits)",
            // All of them, not a subset: see `LibraryFilters.revisionKey`.
            filters.revisionKey,
            "\(hideMature)",
            "\(matureMode.rawValue)",
            "\(gate.revealAll)",
            "\(gate.revealedIDs.count)",
        ].joined(separator: "|")
    }

    private func rebuildSectionCache() {
        var next: [LibrarySectionKind: [SavedWork]] = [:]
        let localKinds: [LibrarySectionKind] = [
            .readingNow, .savedForLater, .finished, .downloaded, .history, .favorites
        ]
        for kind in localKinds {
            next[kind] = filters.apply(to: kind.works(from: works, visible: passesPrivacy))
        }
        sectionCache = next
        importedCache = filters.apply(to: works.filter { work in
            LibraryShelfID.isImported(origin: work.origin, isQueueOnly: work.isQueueOnlyWork)
                && passesPrivacy(work)
        })
        let libraryWorks = works.filter { !$0.isQueueOnlyWork && passesPrivacy($0) }
        let downloadedWorks = libraryWorks.filter(\.isDownloaded)
        libraryHeader = LibraryHeaderFacts(
            workCount: libraryWorks.count,
            downloadedCount: downloadedWorks.count,
            downloadedBytes: downloadedWorks.reduce(0) { $0 + queueWorkFileSize($1.fileURL) }
        )
        filteredDownloadedBytes = (next[.downloaded] ?? []).reduce(0) { $0 + queueWorkFileSize($1.fileURL) }

        // One chip per fandom family, counted once per work.
        let counts: [String: Int] = works
            .filter { !$0.isQueueOnlyWork && passesPrivacy($0) }
            .flatMap { Set($0.workFandoms.map(FandomDisplayName.bareTitle)) }
            .reduce(into: [:]) { $0[$1, default: 0] += 1 }
        topFandomsCache = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(10)
            .map(\.key)

        hasSectionCache = true
    }

    private func cachedWorks(for kind: LibrarySectionKind) -> [SavedWork] {
        sectionCache[kind] ?? []
    }

    private var dashboard: some View {
        DashboardRegionHost {
            Group {
                if hasSectionCache {
                    realDashboard
                } else {
                    // First paint inside the progressive tab content — keep showing
                    // skeletons until the section cache is ready (usually one yield).
                    TabDashboardShell(
                        sectionTitles: pageArrangement.sections.map(\.id.title)
                            + (pageArrangement.buttons.isEmpty ? [] : ["Shelves"]),
                        showFilterChips: true
                    )
                }
            }
        }
    }

    private var realDashboard: some View { shelvesDashboard }

    private var shelvesDashboard: some View {
        ScrollView {
            // 26pt between sections (Rules; 1c drew 22), the chips' row included.
            VStack(alignment: .leading, spacing: SubjectMetrics.sectionSpacing) {
                libraryHeaderLink
                fandomFilterBar
                ForEach(pageArrangement.sections) { section in
                    arrangedSection(section)
                }
                if !pageArrangement.buttons.isEmpty {
                    LibraryShelfButtonGrid(
                        buttons: pageArrangement.buttons,
                        counts: shelfCounts,
                        onEdit: { showingEditShelves = true },
                        onOpen: openShelf
                    )
                    .dashboardLeadingRegion()
                }
                onAO3Panel.dashboardLeadingRegion()
                if recentlyDeletedCount > 0 {
                    recentlyDeletedRow.dashboardLeadingRegion()
                }
            }
            .padding(.vertical, 12)
        }
        .refreshable { await refreshLibraryDashboard() }
    }

    private var onAO3Panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRuleHeader(title: "On AO3")
                .padding(.horizontal, SubjectMetrics.accountGutter)

            VStack(spacing: 0) {
                ForEach(Array(LibraryAO3Route.allCases.enumerated()), id: \.element) { index, route in
                    if index > 0 { SubjectRowSeparator() }
                    Button {
                        path.append(route)
                    } label: {
                        AccountNavCardLabel(
                            title: route.title,
                            systemImage: route.systemImage,
                            count: cachedAO3Count(route)
                        )
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .subjectPanel()
            .padding(.horizontal, CardListMetrics.sideMargin)
        }
    }

    private func cachedAO3Count(_ route: LibraryAO3Route) -> String? {
        AO3AccountListCountsCache.shared.count(
            for: route.countKind,
            authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        )?.displayText
    }

    /// Only shown once something is actually pending deletion — matches every other
    /// section's hide-when-empty convention. A plain row rather than a card carousel,
    /// since it spans three different record types rather than a list of works.
    private var recentlyDeletedRow: some View {
        Button {
            path.append(RecentlyDeletedDestination())
        } label: {
            // 1c: a subject row on the app's panel ground, not a material tile.
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Recently Deleted")
                    .font(.system(size: recentlyDeletedTitleSize, weight: .semibold))
                Spacer()
                Text(recentlyDeletedCount.compactCount)
                    .font(.system(size: recentlyDeletedCountSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .subjectPanel()
            .padding(.horizontal, CardListMetrics.sideMargin)
        }
        .buttonStyle(.plain)
    }

    /// A purely local section carousel (Reading Now / Finished / Downloaded).
    /// Reads pre-filtered slices from `sectionCache`.
    private func localCarousel(
        _ kind: LibrarySectionKind,
        title: String,
        countText: String? = nil,
        emptyMessage: String? = nil
    ) -> some View {
        let sectionWorks = cachedWorks(for: kind)
        return WorkCarouselSection(
            title: title,
            collapseKey: "library.\(kind.rawValue)",
            hasItems: !sectionWorks.isEmpty,
            itemCount: sectionWorks.count,
            countText: countText,
            visibleCount: min(sectionWorks.count, 12),
            onSeeAll: !sectionWorks.isEmpty
                ? { path.append(LibrarySectionRoute(kind: kind, originKicker: "Library")) }
                : nil
        ) {
            ForEach(sectionWorks.prefix(12)) { work in
                localCarouselCard(
                    work: work,
                    footer: footer(kind, work),
                    progress: progress(kind, work),
                    metadataStyle: kind == .downloaded ? .downloaded : .standard
                )
            }
        } emptyState: {
            SectionEmptyState(message: emptyMessage ?? kind.emptyMessage, systemImage: kind.emptyIcon)
        }
    }

    private var collectionsCarousel: some View {
        let kind = LibrarySectionKind.collections
        return WorkCarouselSection(
            title: kind.title,
            collapseKey: "library.\(kind.rawValue)",
            hasItems: !collections.isEmpty,
            itemCount: collections.count,
            cardSpacing: CarouselCardMetrics.coverStackSpacing,
            cardWidth: CarouselCardMetrics.stackWidth,
            visibleCount: min(collections.count, 12),
            onSeeAll: !collections.isEmpty ? { path.append(AllCollectionsDestination()) } : nil
        ) {
            // The "New collection" card is the toolbar's "+" now (owner,
            // 2026-10-01: global actions live in the top-right chrome).
            ForEach(collections.prefix(12)) { collection in
                NavigationLink(value: collection) {
                    CollectionCard(collection: collection)
                        .collectionCardMenu(collection)
                }
                .buttonStyle(.plain)
            }
        } emptyState: {
            Text("Use + above to create a collection for works you want to group together.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func arrangedSection(_ section: LibraryPageSection) -> some View {
        switch section.id {
        case .collections:
            if section.style == .list {
                collectionsList
            } else {
                collectionsCarousel
            }
        case .queues:
            if section.style == .list {
                queuesList
            } else {
                queuesCarousel
            }
        case .imported:
            importedSection(section.style)
        default:
            if let kind = shelfKind(section.id) {
                if section.style == .list {
                    workListSection(section.id, kind: kind)
                } else {
                    localCarousel(
                        kind,
                        title: section.id.title,
                        countText: downloadedCountText(for: section.id),
                        emptyMessage: emptyCopy(for: section.id)
                    )
                }
            }
        }
    }

    private var libraryHeaderLink: some View {
        let bytes = LocalStorageFootprint.formatted(bytes: libraryHeader.downloadedBytes)
        let tally = LibraryPageArrangement.headerTally(
            works: libraryHeader.workCount,
            downloaded: libraryHeader.downloadedCount,
            byteText: bytes
        )
        let phrase = LibraryPageArrangement.workCountPhrase(libraryHeader.workCount)
        let line = Text(phrase).fontWeight(.semibold).foregroundStyle(.primary)
            + Text(" · \(libraryHeader.downloadedCount) downloaded · \(bytes)").foregroundStyle(.secondary)
        return Button {
            path.append(LibraryCatalogueDestination(kind: .allWorks))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                line
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All Works, \(tally)")
        .accessibilityHint("Opens every work in the library")
        .dashboardLeadingRegion()
    }

    private var shelfCounts: [LibraryShelfID: Int] {
        Dictionary(uniqueKeysWithValues: LibraryShelfID.allCases.map { ($0, shelfCount($0)) })
    }

    private func shelfCount(_ shelf: LibraryShelfID) -> Int {
        switch shelf {
        case .favourites: cachedWorks(for: .favorites).count
        case .collections: collections.count
        case .downloaded: cachedWorks(for: .downloaded).count
        case .wantToRead: cachedWorks(for: .savedForLater).count
        case .readingNow: cachedWorks(for: .readingNow).count
        case .finished: cachedWorks(for: .finished).count
        case .queues: shelfQueues.count
        case .history: cachedWorks(for: .history).count
        case .imported: importedCache.count
        }
    }

    private var shelfQueues: [ReadingQueue] {
        readingQueues
            .filter { $0.kind == .custom }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func shelfKind(_ shelf: LibraryShelfID) -> LibrarySectionKind? {
        switch shelf {
        case .favourites: .favorites
        case .downloaded: .downloaded
        case .wantToRead: .savedForLater
        case .readingNow: .readingNow
        case .finished: .finished
        case .history: .history
        case .collections, .queues, .imported: nil
        }
    }

    private func emptyCopy(for shelf: LibraryShelfID) -> String {
        switch shelf {
        case .wantToRead:
            LibrarySectionKind.savedForLater.emptyMessage
        case .imported:
            "Works you import, or bring in from another site, appear here."
        case .queues:
            "You have no queues yet. Open Queues to add one."
        case .collections:
            "Use + above to create a collection for works you want to group together."
        default:
            shelfKind(shelf)?.emptyMessage ?? ""
        }
    }

    private func downloadedCountText(for shelf: LibraryShelfID) -> String? {
        guard shelf == .downloaded else { return nil }
        let count = cachedWorks(for: .downloaded).count
        guard count > 0 else { return nil }
        return "\(count.compactCount) · \(LocalStorageFootprint.formatted(bytes: filteredDownloadedBytes))"
    }

    private func openShelf(_ shelf: LibraryShelfID) {
        switch shelf {
        case .collections:
            path.append(AllCollectionsDestination())
        case .queues:
            path.append(AllReadingQueuesDestination(initialQueueID: nil))
        case .imported:
            path.append(LibraryCatalogueDestination(kind: .imported))
        default:
            if let kind = shelfKind(shelf) {
                path.append(LibrarySectionRoute(kind: kind, originKicker: "Library"))
            }
        }
    }

    private func workListSection(_ shelf: LibraryShelfID, kind: LibrarySectionKind) -> some View {
        let sectionWorks = cachedWorks(for: kind)
        return LibraryCollapsingShelf(
            title: shelf.title,
            collapseKey: "library.\(kind.rawValue)",
            count: sectionWorks.count,
            countText: downloadedCountText(for: shelf),
            onSeeAll: sectionWorks.isEmpty
                ? nil
                : { path.append(LibrarySectionRoute(kind: kind, originKicker: "Library")) }
        ) {
            if sectionWorks.isEmpty {
                SectionEmptyState(message: emptyCopy(for: shelf), systemImage: kind.emptyIcon)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(sectionWorks.prefix(12)) { work in
                        ledgerRow(work)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func importedSection(_ style: LibrarySectionStyle) -> some View {
        let sectionWorks = importedCache
        return LibraryCollapsingShelf(
            title: LibraryShelfID.imported.title,
            collapseKey: "library.imported",
            count: sectionWorks.count,
            onSeeAll: sectionWorks.isEmpty
                ? nil
                : { path.append(LibraryCatalogueDestination(kind: .imported)) }
        ) {
            if sectionWorks.isEmpty {
                SectionEmptyState(message: emptyCopy(for: .imported), systemImage: "doc")
                    .padding(.horizontal, 16)
            } else if style == .list {
                VStack(spacing: 8) {
                    ForEach(sectionWorks.prefix(12)) { work in
                        ledgerRow(work)
                    }
                }
                .padding(.horizontal, 16)
            } else {
                DashboardCardShelf {
                    ForEach(sectionWorks.prefix(12)) { work in
                        localCarouselCard(work: work, footer: nil, progress: nil)
                    }
                }
            }
        }
    }

    private func ledgerRow(_ work: SavedWork) -> some View {
        let selected = selection.contains(work.id)
        let toggle: (() -> Void)? = isSelecting ? { toggleSelection(work) } : nil
        return SensitiveWorkRow(
            work: work,
            openMode: .reader,
            onSelect: selectAction(for: work),
            isSelecting: isSelecting,
            isSelected: selected,
            onToggleSelection: toggle,
            presentation: .ledger,
            showsFavoriteStar: true,
            showsFullLedgerStats: true,
            showsSummary: false,
            usesInlineNavigation: !isSelecting
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
            shape.fill(themeManager.appTheme.cardSurface)
                .overlay(
                    shape.strokeBorder(
                        selected ? AnyShapeStyle(.tint) : AnyShapeStyle(themeManager.appTheme.cardBorder),
                        lineWidth: selected ? 2 : 0.5
                    )
                )
        }
    }

    private var collectionsList: some View {
        LibraryCollapsingShelf(
            title: LibraryShelfID.collections.title,
            collapseKey: "library.\(LibrarySectionKind.collections.rawValue)",
            count: collections.count,
            onSeeAll: collections.isEmpty ? nil : { path.append(AllCollectionsDestination()) }
        ) {
            if collections.isEmpty {
                Text(emptyCopy(for: .collections))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(collections.prefix(12)) { collection in
                        NavigationLink(value: collection) {
                            CollectionLedgerRow(
                                collection: collection,
                                previewWorks: collectionPreviews(collection)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func collectionPreviews(_ collection: WorkCollection) -> [SavedWork] {
        collection.works.filter { work in
            !work.isPendingDeletion && !gate.isConcealed(work, enabled: hideMature)
        }
    }

    private var queuesCarousel: some View {
        WorkCarouselSection(
            title: LibraryShelfID.queues.title,
            collapseKey: "library.queues",
            hasItems: !shelfQueues.isEmpty,
            itemCount: shelfQueues.count,
            cardSpacing: ReadingQueueCard.spacing,
            cardWidth: ReadingQueueCard.width,
            visibleCount: min(shelfQueues.count, 12),
            actionTitle: "Organise",
            onSeeAll: !shelfQueues.isEmpty ? { path.append(AllReadingQueuesDestination(initialQueueID: nil)) } : nil
        ) {
            ForEach(shelfQueues.prefix(12)) { queue in
                NavigationLink(value: AllReadingQueuesDestination(initialQueueID: queue.id)) {
                    ReadingQueueCard(queue: queue)
                }
                .buttonStyle(.plain)
            }
        } emptyState: {
            VStack(alignment: .leading, spacing: 8) {
                Text(emptyCopy(for: .queues))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Queues") {
                    path.append(AllReadingQueuesDestination(initialQueueID: nil))
                }
                .foregroundStyle(.accentFill)
            }
        }
    }

    private var queuesList: some View {
        LibraryCollapsingShelf(
            title: LibraryShelfID.queues.title,
            collapseKey: "library.queues",
            count: shelfQueues.count,
            onSeeAll: { path.append(AllReadingQueuesDestination(initialQueueID: nil)) }
        ) {
            if shelfQueues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(emptyCopy(for: .queues))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Queues") {
                        path.append(AllReadingQueuesDestination(initialQueueID: nil))
                    }
                    .foregroundStyle(.accentFill)
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(shelfQueues.prefix(12)) { queue in
                        NavigationLink(value: AllReadingQueuesDestination(initialQueueID: queue.id)) {
                            LibraryQueueLedgerRow(queue: queue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// A light, horizontal quick-filter chip row: tap a fandom to filter every
    /// section to it (the full faceted filters stay behind the "Filters" button).
    /// A trailing Reset chip appears whenever any filter (chip or inspector) is
    /// active.
    ///
    /// Pills, not the rounded rects the results rails use. Spec 1c and 1ad draw
    /// this row round and the active-filter summary square, and the difference
    /// carries meaning: a pill here is an offer you can tap on and off, where a
    /// rect on a results page states a filter that is already in force.
    @ViewBuilder
    private var fandomFilterBar: some View {
        let fandoms = topFandomsCache
        if !fandoms.isEmpty || filters.hasActiveFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !fandoms.isEmpty {
                        filterChip("All", selected: filters.fandoms.isEmpty) {
                            filters.fandoms = []
                        }
                        ForEach(fandoms, id: \.self) { fandom in
                            filterChip(fandom, selected: filters.fandoms.contains(fandom)) {
                                filters.fandoms = filters.fandoms.contains(fandom) ? [] : [fandom]
                            }
                        }
                    }
                    if filters.hasActiveFilters {
                        Button {
                            withAnimation(.snappy) { filters = LibraryFilters() }
                        } label: {
                            // Quieter than the filter pills beside it — spec 1c
                            // drops its fill to 6% and its text to 50%, because
                            // undoing is not one of the choices on offer, it is
                            // the way out of them.
                            SubjectChip(text: "Reset", style: .pill(isSelected: false), systemImage: "xmark")
                                .opacity(0.7)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset filters")
                    }
                }
                .padding(.horizontal, 16)
            }
            .horizontalScrollViewport()
            .dashboardLeadingRegion()
        }
    }

    private func filterChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            SubjectChip(
                text: text,
                style: .pill(isSelected: selected),
                palette: themeManager.scopePalette
            )
        }
        .buttonStyle(.plain)
        .minimumHitTarget(28)
    }

    // MARK: Card details

    private func footer(_ kind: LibrarySectionKind, _ work: SavedWork) -> String? {
        switch kind {
        case .readingNow: WorkReadingPosition.cardProgressLabel(progress: work.publicationProgress)
        case .finished: "Finished"
        default: nil
        }
    }

    private func progress(_ kind: LibrarySectionKind, _ work: SavedWork) -> Double? {
        kind == .readingNow ? work.readingProgress : nil
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                SelectAllButton(allSelected: allSelectableSelected, action: toggleSelectAll)
            }
            if hideMature {
                ToolbarItem(placement: .primaryAction) {
                    MatureRevealToggle()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSelectionList.toggle()
                } label: {
                    Label(
                        showingSelectionList ? "Show Carousels" : "Show Detailed List",
                        systemImage: showingSelectionList ? "rectangle.grid.1x2" : "list.bullet.rectangle"
                    )
                }
                .help(showingSelectionList ? "Show carousels" : "Show detailed list")
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
            let showsMature = hideMature
            let showsStatistics = !statisticsWorks.isEmpty
            let showsSelect = !works.isEmpty
            let showsMoreMenu = true
            // Gated as a whole, not just its inner pieces — an empty HStack (or a
            // WorkListMoreMenu with no items) still reserves an (empty-looking)
            // toolbar slot, which is exactly what showed a blank "..." button when
            // the Library was empty.
            // New Collection is always there — it was the collections shelf's
            // first card (owner, 2026-10-01). Filter is the only other control
            // directly visible; Privacy lives behind "..." (with Select and
            // Reading Insights).
            ActionToolbar(items: [
                    AnyView(ToolbarIconButton(title: "New Collection", systemImage: "plus") {
                        showingNewCollection = true
                    }),
                    !works.isEmpty
                        ? AnyView(FilterButton(filtersActive: filters.hasActiveFilters,
                                                showingFilters: router.isShowing(.libraryFilters),
                                                onClearFilters: { filters = LibraryFilters() }))
                        : nil,
                    showsMoreMenu
                        ? AnyView(WorkListMoreMenu {
                            Button {
                                showingEditShelves = true
                            } label: {
                                Label("Edit Shelves", systemImage: "square.grid.2x2")
                            }
                            if showsMature {
                                MatureRevealToggle()
                            }
                            if showsSelect {
                                Button {
                                    enterSelectMode()
                                } label: {
                                    Label("Select", systemImage: "checklist")
                                }
                            }
                            // A page item, so after Select (pass2-2).
                            if showsStatistics {
                                NavigationLink(value: ReadingInsightsDestination()) {
                                    Label("Reading Insights", systemImage: "chart.bar.xaxis")
                                }
                            }
                        })
                        : nil
                ].compactMap { $0 })
        }
    }

    // MARK: Loading

    /// Fills in the filter metadata (categorized Work Tags, warnings, categories,
    /// language, word count) for any saved works that predate it. First seeds tags from
    /// each downloaded work's on-disk EPUB (pure local — so downloaded works always keep
    /// their tags, even when deleted from AO3), then refreshes from AO3 once for works
    /// that still need the categorized/extra data. Runs over *all* works — not the
    /// filtered subset — so a work isn't kept hidden by a filter it would actually match.
    /// Sequential, so it never bursts requests; each step is guarded and skips works that
    /// are already complete, have no EPUB, or no AO3 source.
    private func backfillFilterMetadata() async {
        for work in works where !work.isQueueOnlyWork {
            // A cancelled `.task` must stop here, not spin through every remaining
            // work stamping attempts it never made (T-255).
            if Task.isCancelled { break }
            await WorkTags.backfillFromEPUB(for: work, in: context)
            if work.needsAO3Refresh {
                await WorkTags.refreshFromAO3(for: work, in: context)
            }
        }
    }

    // MARK: Multi-select / bulk actions

    /// All local works visible under privacy + the active filters, for the
    /// select-mode list. Already newest-first from the query.
    private var selectableWorks: [SavedWork] {
        filters.apply(to: works.filter { !$0.isQueueOnlyWork && passesPrivacy($0) })
    }

    private var selectList: some View {
        List {
            Section {
                ForEach(selectableWorks) { work in
                    SensitiveWorkRow(
                        work: work,
                        openMode: .reader,
                        isSelecting: true,
                        isSelected: selection.contains(work.id),
                        onToggleSelection: { toggleSelection(work) }
                    )
                    .cardRow(isSelected: selection.contains(work.id), chrome: .plain)
                }
            }
        }
        .cardList()
        .appScreenSurface(.content)
        .refreshable {
            let task = Task { await refreshSelectableWorks() }
            refreshTask = task
            await task.value
        }
        .cancelRefreshOnTabChange($refreshTask)
    }

    private var allSelectableSelected: Bool {
        let ids = Set(selectableWorks.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    private func toggleSelectAll() {
        selection = allSelectableSelected ? [] : Set(selectableWorks.map(\.id))
    }

    private func enterSelectMode(selecting work: SavedWork? = nil) {
        if let work {
            selection.insert(work.id)
        }
        showingSelectionList = false
        isSelecting = true
    }

    private func selectAction(for work: SavedWork) -> (() -> Void)? {
        { enterSelectMode(selecting: work) }
    }

    private func exitSelectMode() {
        isSelecting = false
        showingSelectionList = false
        selection = []
    }

    @ViewBuilder
    private func localCarouselCard(
        work: SavedWork,
        footer: String?,
        progress: Double?,
        metadataStyle: WorkCoverMetadataStyle = .standard
    ) -> some View {
        localCoverCard(
            work: work,
            footer: footer,
            progress: progress,
            metadataStyle: metadataStyle
        )
    }

    @ViewBuilder
    private func localCoverCard(
        work: SavedWork,
        footer: String?,
        progress: Double?,
        metadataStyle: WorkCoverMetadataStyle
    ) -> some View {
        if isSelecting {
            SensitiveWorkCoverCard(
                work: work,
                footer: footer,
                progress: progress,
                metadataStyle: metadataStyle,
                isSelecting: true,
                isSelected: selection.contains(work.id),
                onToggleSelection: { toggleSelection(work) }
            )
            .localWorkContextMenu(work: work, onSelect: selectAction(for: work))
        } else {
            NavigationLink(value: LocalWorkDestination.reader(work)) {
                SensitiveWorkCoverCard(
                    work: work,
                    footer: footer,
                    progress: progress,
                    metadataStyle: metadataStyle
                )
            }
            .buttonStyle(.plain)
            .localWorkContextMenu(work: work, onSelect: selectAction(for: work))
        }
    }

    private func toggleSelection(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private func refreshLibraryDashboard() async {
        _ = await WorkMetadataRefresh.refresh(visibleDashboardWorks, in: context, auth: auth)
    }

    private func refreshSelectableWorks() async {
        _ = await WorkMetadataRefresh.refresh(selectableWorks, in: context, auth: auth)
    }

    private var visibleDashboardWorks: [SavedWork] {
        var listed: [SavedWork] = []
        for section in pageArrangement.sections {
            if section.id == .imported {
                listed += importedCache.prefix(12)
            } else if let kind = shelfKind(section.id) {
                listed += dashboardWorks(for: kind)
            }
        }
        return unique(listed)
    }

    private func dashboardWorks(for kind: LibrarySectionKind) -> [SavedWork] {
        Array(cachedWorks(for: kind).prefix(12))
    }

    private func unique(_ works: [SavedWork]) -> [SavedWork] {
        var seen = Set<UUID>()
        return works.filter { seen.insert($0.id).inserted }
    }
}

/// Counts for the line under the Library title. Privacy-filtered, not narrowed
/// by the fandom chips: the header is the whole library.
private struct LibraryHeaderFacts {
    var workCount = 0
    var downloadedCount = 0
    var downloadedBytes: Int64 = 0
}

private extension LibraryAO3Route {
    var title: String {
        switch self {
        case .markedForLater: "Marked for Later"
        case .bookmarks: "Bookmarks"
        case .subscriptions: "Subscriptions"
        case .history: "AO3 History"
        }
    }

    var systemImage: String {
        switch self {
        case .markedForLater: "clock.badge"
        case .bookmarks: "bookmark"
        case .subscriptions: "bell"
        case .history: "clock.arrow.circlepath"
        }
    }

    var kind: AO3AccountWorksList.Kind {
        switch self {
        case .markedForLater: .markedForLater
        case .bookmarks: .bookmarks
        case .subscriptions: .subscriptions
        case .history: .history
        }
    }

    var countKind: AO3AccountListKind {
        switch self {
        case .markedForLater: .markedForLater
        case .bookmarks: .bookmarks
        case .subscriptions: .subscriptions
        case .history: .history
        }
    }
}
