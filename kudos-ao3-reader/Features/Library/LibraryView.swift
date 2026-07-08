import OSLog
import SwiftData
import SwiftUI

// Lint: this existing dashboard owns many stateful sections.
/// The Library tab: a Books-style dashboard of the user's saved works. Every section
/// is a collapsible horizontal card carousel with a `>` chevron that opens its full
/// vertical list. Sections, in order: Reading Now, Saved for Later, Finished,
/// Collections, Downloaded. Saved for Later merges in the user's AO3 "Marked for
/// Later" list; Collections is a placeholder until shelves land.
///
/// Filtering (the inspector panel), Reading Insights, content privacy, and — on iOS —
/// multi-select bulk actions are kept from the previous list-based Library.
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
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var readingQueues: [ReadingQueue]
    // Counts only — RecentlyDeletedView does its own full @Query for the actual list.
    @Query(filter: #Predicate<SavedWork> { $0.isPendingDeletion }) private var deletedWorks: [SavedWork]
    @Query(filter: #Predicate<WorkCollection> { $0.isPendingDeletion }) private var deletedCollections: [WorkCollection]
    @Query(filter: #Predicate<ReadingQueue> { $0.isPendingDeletion }) private var deletedQueues: [ReadingQueue]
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @State private var path = NavigationPath()
    @State private var filters = LibraryFilters()
    @State private var markedForLater: [AO3WorkSummary] = []
    /// True only while the remote Marked-for-Later request is in flight, so the
    /// Saved for Later carousel can show cover skeletons instead of its empty state.
    @State private var isLoadingMarkedForLater = false
    @State private var showingNewCollection = false
    @State private var newCollectionName = ""
    @State private var showingNewQueue = false
    @State private var newQueueName = ""

    // Multi-select / bulk actions. `EditMode` is iOS-only, so macOS has no select mode.
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    @State private var selection = Set<UUID>()
    @State private var confirmBulkDelete = false
    @State private var showingSelectionList = false
    /// Tracks the select-mode list's in-flight refresh so it can be cancelled if the
    /// user switches tabs (see `cancelRefreshOnTabChange`) — this can be the whole Library.
    @State private var refreshTask: Task<Void, Never>?

    private var isSelecting: Bool {
        #if os(iOS)
        editMode.isEditing
        #else
        false
        #endif
    }

    private var selectedWorks: [SavedWork] {
        works.filter { selection.contains($0.id) }
    }

    /// Whether the bulk Save/Favorite buttons show as "on" — every selected work is
    /// already in that state. Tapping toggles: makes the selection consistently on
    /// if it isn't already, otherwise undoes it for all of them.
    private var allSelectedAreSaved: Bool {
        !selectedWorks.isEmpty && selectedWorks.allSatisfy(\.isSaved)
    }

    private var allSelectedAreFavorited: Bool {
        !selectedWorks.isEmpty && selectedWorks.allSatisfy(\.isFavorite)
    }

    /// Escalates when any selected work is no longer available on AO3 — see
    /// `PreservedWorkService.deleteConfirmationMessage`, same reasoning applied
    /// across the whole selection rather than per-work.
    private var bulkDeleteMessage: String {
        let base = "The selected works will be moved to Recently Deleted. "
            + "You can restore them anytime in the next 90 days."
        guard selectedWorks.contains(where: \.ao3Unavailable) else { return base }
        return base + " Some of these are no longer available on AO3 — "
            + "if you don't restore them in time, they can't be re-saved afterward."
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

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isSelecting && showingSelectionList {
                    selectList
                } else {
                    dashboard
                }
            }
            .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle(isSelecting
                ? (selection.isEmpty ? "Select Works" : "\(selection.count) Selected")
                : "Library")
            #if os(iOS)
                .toolbarTitleDisplayMode(.inlineLarge)
            #endif
                .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
                .navigationDestination(for: LocalWorkDestination.self) { LocalWorkDestinationView(destination: $0) }
                .navigationDestination(for: LibrarySectionKind.self) { LibrarySectionListView(kind: $0) }
                .navigationDestination(for: WorkCollection.self) { CollectionDetailView(collection: $0) }
                .navigationDestination(for: ReadingQueue.self) { ReadingQueueDetailView(queue: $0) }
                .navigationDestination(for: AO3WorkSummary.self) { WorkDetailView(remote: $0) }
                .navigationDestination(for: RecentlyDeletedDestination.self) { _ in RecentlyDeletedView() }
                .navigationDestination(for: AllCollectionsDestination.self) { _ in
                    LibraryEntityGridView(
                        title: "Collections",
                        items: collections,
                        onNew: {
                            newCollectionName = ""
                            showingNewCollection = true
                        },
                        card: { CollectionCard(collection: $0) },
                        newCard: { NewCollectionCard() }
                    )
                }
                .navigationDestination(for: AllReadingQueuesDestination.self) { _ in
                    LibraryEntityGridView(
                        title: "Reading Queues",
                        items: readingQueues.filter { $0.kind == .custom }.sorted { $0.sortOrder < $1.sortOrder },
                        onNew: {
                            newQueueName = ""
                            showingNewQueue = true
                        },
                        card: { ReadingQueueCard(queue: $0) },
                        newCard: { NewReadingQueueCard() }
                    )
                }
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
                .alert("New Collection", isPresented: $showingNewCollection) {
                    TextField("Name", text: $newCollectionName)
                    Button("Create") { createCollection() }
                    Button("Cancel", role: .cancel) { newCollectionName = "" }
                } message: {
                    Text("Name your collection.")
                }
                .alert("New Queue", isPresented: $showingNewQueue) {
                    TextField("Name", text: $newQueueName)
                    Button("Create") { createQueue() }
                    Button("Cancel", role: .cancel) { newQueueName = "" }
                } message: {
                    Text("Name your reading queue.")
                }
                .confirmationDialog(
                    "Delete \(selection.count) work\(selection.count == 1 ? "" : "s")?",
                    isPresented: $confirmBulkDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) { bulkDelete() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(bulkDeleteMessage)
                }
                .inspector(isPresented: router.isShowing(.libraryFilters)) {
                    LibraryFilterPanel(filters: $filters, works: works, userTagNames: userTagNames)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                    // On iPhone the inspector collapses into a bottom sheet; show the
                    // standard grabber so it reads as swipe-to-dismiss.
                    #if os(iOS)
                        .presentationDragIndicator(.visible)
                    #endif
                }
                .task {
                    ReadingQueueService.ensureSavedForLaterQueue(in: context)
                    ReadingQueueService.normalizeAllQueuedWorks(in: context)
                    await backfillFilterMetadata()
                }
                .task(id: auth.isLoggedIn) { await loadMarkedForLater() }
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
                }
        }
    }

    // MARK: Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                fandomFilterBar
                localCarousel(.readingNow)
                savedForLaterCarousel
                localCarousel(.finished)
                readingQueuesCarousel
                collectionsCarousel
                localCarousel(.downloaded)
                if recentlyDeletedCount > 0 {
                    recentlyDeletedRow
                }
            }
            .padding(.vertical, 12)
        }
        .refreshable { await refreshLibraryDashboard() }
    }

    /// Only shown once something is actually pending deletion — matches every other
    /// section's hide-when-empty convention. A plain row rather than a card carousel,
    /// since it spans three different record types rather than a list of works.
    private var recentlyDeletedRow: some View {
        Button {
            path.append(RecentlyDeletedDestination())
        } label: {
            HStack {
                Label("Recently Deleted", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(recentlyDeletedCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    /// A purely local section carousel (Reading Now / Finished / Downloaded). Applies
    /// the active filters on top of the section's own filter + ordering.
    private func localCarousel(_ kind: LibrarySectionKind) -> some View {
        let sectionWorks = filters.apply(to: kind.works(from: works, visible: passesPrivacy))
        return WorkCarouselSection(
            title: kind.title,
            collapseKey: "library.\(kind.rawValue)",
            hasItems: !sectionWorks.isEmpty,
            onSeeAll: sectionWorks.count > 1 ? { path.append(kind) } : nil
        ) {
            ForEach(sectionWorks.prefix(12)) { work in
                localCarouselCard(work: work, footer: footer(kind, work), progress: progress(kind, work))
            }
        } emptyState: {
            SectionEmptyState(message: kind.emptyMessage, systemImage: kind.emptyIcon)
        }
    }

    /// Saved for Later merges the user's saved works with their AO3 "Marked for Later"
    /// list (loaded when signed in). The `>` chevron opens the combined full list.
    private var savedForLaterCarousel: some View {
        let kind = LibrarySectionKind.savedForLater
        let saved = filters.apply(to: kind.works(from: works, visible: passesPrivacy))
        let mfl = filteredMarkedForLater
        let hasItems = !saved.isEmpty || !mfl.isEmpty
        // Skeletons only while the remote list is loading and there's nothing yet —
        // local saved works render immediately and suppress the placeholders.
        let showSkeleton = isLoadingMarkedForLater && !hasItems
        return WorkCarouselSection(
            title: kind.title,
            collapseKey: "library.\(kind.rawValue)",
            hasItems: hasItems || showSkeleton,
            onSeeAll: hasItems ? { path.append(kind) } : nil
        ) {
            if showSkeleton {
                ForEach(0 ..< 6, id: \.self) { _ in WorkCoverCardSkeleton() }
            } else {
                ForEach(saved.prefix(12)) { work in
                    localCarouselCard(work: work, footer: nil, progress: nil)
                }
                ForEach(mfl.prefix(12)) { work in
                    NavigationLink(value: work) { AO3WorkCoverCard(work: work) }
                        .buttonStyle(.plain)
                }
            }
        } emptyState: {
            SectionEmptyState(message: kind.emptyMessage, systemImage: kind.emptyIcon)
        }
    }

    /// The AO3 Marked-for-Later (remote) list with any locally-saved work removed —
    /// a work in both lists renders once, as its richer local card (which may live
    /// in another section, e.g. Reading Now) — then narrowed by the active fandom
    /// quick-filter so the chips affect this section too. The other, metadata-only
    /// filters don't apply to remote summaries (they carry no rating/word count).
    private var filteredMarkedForLater: [AO3WorkSummary] {
        let remoteOnly = CanonicalWorkMerge.remoteOnly(remote: markedForLater, localLibrary: works)
        guard !filters.fandoms.isEmpty else { return remoteOnly }
        let wanted = Set(filters.fandoms.map { $0.lowercased() })
        return remoteOnly.filter { summary in
            summary.fandoms.contains { wanted.contains($0.lowercased()) }
        }
    }

    /// User-named Collections (shelves). A leading "New" card is always present so
    /// creating one is one tap away; existing collections follow, capped like every
    /// other carousel — the `>` chevron opens the full, uncapped grid.
    private var collectionsCarousel: some View {
        let kind = LibrarySectionKind.collections
        return WorkCarouselSection(
            title: kind.title,
            collapseKey: "library.\(kind.rawValue)",
            hasItems: true,
            onSeeAll: collections.count > 11 ? { path.append(AllCollectionsDestination()) } : nil
        ) {
            Button {
                newCollectionName = ""
                showingNewCollection = true
            } label: {
                NewCollectionCard()
            }
            .buttonStyle(.plain)

            ForEach(collections.prefix(12)) { collection in
                NavigationLink(value: collection) {
                    CollectionCard(collection: collection)
                }
                .buttonStyle(.plain)
            }
        } emptyState: {
            EmptyView()
        }
    }

    private var readingQueuesCarousel: some View {
        let customQueues = readingQueues
            .filter { $0.kind == .custom }
            .sorted { $0.sortOrder < $1.sortOrder }
        return WorkCarouselSection(
            title: "Reading Queues",
            collapseKey: "library.readingQueues",
            hasItems: true,
            onSeeAll: customQueues.count > 11 ? { path.append(AllReadingQueuesDestination()) } : nil
        ) {
            Button {
                newQueueName = ""
                showingNewQueue = true
            } label: {
                NewReadingQueueCard()
            }
            .buttonStyle(.plain)

            ForEach(customQueues.prefix(12)) { queue in
                NavigationLink(value: queue) {
                    ReadingQueueCard(queue: queue)
                }
                .buttonStyle(.plain)
            }
        } emptyState: {
            EmptyView()
        }
    }

    /// The user's most-common fandoms (privacy-filtered), most frequent first —
    /// the data behind the quick-filter chips.
    private var topFandoms: [String] {
        let counts: [String: Int] = works
            .filter { !$0.isQueueOnlyWork && passesPrivacy($0) }
            .flatMap(\.workFandoms)
            .reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(10)
            .map(\.key)
    }

    /// A light, horizontal quick-filter chip row: tap a fandom to filter every
    /// section to it (the full faceted filters stay behind the "Filters" button).
    /// Reuses `TagChip` so it matches the Browse/Search chips; a trailing Reset chip
    /// appears whenever any filter (chip or inspector) is active.
    @ViewBuilder
    private var fandomFilterBar: some View {
        let fandoms = topFandoms
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
                            Label("Reset", systemImage: "xmark")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundStyle(.secondary)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset filters")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func filterChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            TagChip(text: text, tinted: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Card details

    private func footer(_ kind: LibrarySectionKind, _ work: SavedWork) -> String? {
        switch kind {
        case .readingNow: work.readingProgressLabel
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
                Button("Done") { exitSelectMode() }
            }
            if PrivacyGate.hasVisibleMatureWorks(in: selectableWorks, hideMature: hideMature) {
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
            ToolbarItemGroup(placement: .bottomBar) { bulkActionBar }
            #else
            ToolbarItemGroup(placement: .primaryAction) { bulkActionBar }
            #endif
        } else {
            // A single item holding a tight HStack — separate ToolbarItems (and even
            // a ToolbarItemGroup) get the system's wide spacing, which squeezes the
            // large "Library" title. Icon-only so they read as a compact cluster.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    if PrivacyGate.hasVisibleMatureWorks(in: visibleDashboardWorksUnbounded, hideMature: hideMature) {
                        MatureRevealToggle()
                    }
                    if !statisticsWorks.isEmpty {
                        NavigationLink {
                            ReadingStatisticsView(works: statisticsWorks)
                        } label: {
                            Label("Reading Insights", systemImage: "chart.bar.xaxis")
                        }
                    }
                    #if os(iOS)
                    if !works.isEmpty {
                        Button {
                            enterSelectMode()
                        } label: {
                            Label("Select", systemImage: "checklist")
                        }
                    }
                    #endif
                    // Filters sits rightmost — matched on Browse.
                    if !works.isEmpty {
                        filterButton
                    }
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    /// Opens the filter panel; the icon fills while any filter is active. Routed
    /// through the shared router so only one inspector is ever open app-wide.
    private var filterButton: some View {
        Button {
            router.toggle(.libraryFilters)
        } label: {
            Label("Filter", systemImage: filters.hasActiveFilters
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .help("Filters")
        .contextMenu {
            if filters.hasActiveFilters {
                Button(role: .destructive, action: { filters = LibraryFilters() }) {
                    Label("Clear All Filters", systemImage: "arrow.counterclockwise")
                }
            }
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
            await WorkTags.backfillFromEPUB(for: work, in: context)
            if work.needsAO3Refresh {
                await WorkTags.refreshFromAO3(for: work, in: context)
            }
        }
    }

    /// Loads the user's AO3 "Marked for Later" list for the Saved for Later section.
    private func loadMarkedForLater() async {
        // No request happens when signed out (accountWorks early-returns), so skip the
        // loading flag — the local saved works (if any) and empty state show at once.
        guard auth.isLoggedIn else {
            markedForLater = []
            isLoadingMarkedForLater = false
            return
        }
        isLoadingMarkedForLater = true
        do {
            markedForLater = try await auth.accountWorks(from: AO3Client.markedForLaterURL)
        } catch {
            // A refresh failure (network, rate limit, expired session) must not wipe
            // out a previously successful fetch — keep showing what's already there.
            Log.network.notice(
                "Marked for Later refresh failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        isLoadingMarkedForLater = false
    }

    private func createCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCollectionName = ""
        guard !trimmed.isEmpty else { return }
        context.insert(WorkCollection(name: trimmed))
        try? context.save()
    }

    private func createQueue() {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        newQueueName = ""
        guard !trimmed.isEmpty else { return }
        _ = ReadingQueueService.createQueue(named: trimmed, in: context)
    }

    // MARK: Multi-select / bulk actions

    /// All local works visible under privacy + the active filters, for the iOS
    /// select-mode list. Already newest-first from the query.
    private var selectableWorks: [SavedWork] {
        filters.apply(to: works.filter { !$0.isQueueOnlyWork && passesPrivacy($0) })
    }

    @ViewBuilder
    private var selectList: some View {
        #if os(iOS)
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
                }
                    .cardRow()
            }
        }
        .cardList()
        .refreshable {
            let task = Task { await refreshSelectableWorks() }
            refreshTask = task
            await task.value
        }
        .cancelRefreshOnTabChange($refreshTask)
        #else
        EmptyView()
        #endif
    }

    /// The bulk-action controls shown while selecting (bottom bar on iOS). Delete
    /// always confirms — it's a batch and can't be undone.
    @ViewBuilder
    private var bulkActionBar: some View {
        Button(role: .destructive) {
            confirmBulkDelete = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(selection.isEmpty)

        Spacer()

        Button {
            bulkSave()
        } label: {
            Label(allSelectedAreSaved ? "Saved" : "Save",
                  systemImage: allSelectedAreSaved ? "bookmark.fill" : "bookmark")
        }
        .tint(allSelectedAreSaved ? themeManager.accentColor : nil)
        .disabled(selection.isEmpty)

        Spacer()

        Button {
            bulkFavorite()
        } label: {
            Label(allSelectedAreFavorited ? "Favorited" : "Favorite",
                  systemImage: allSelectedAreFavorited ? "star.fill" : "star")
        }
        .tint(allSelectedAreFavorited ? themeManager.accentColor : nil)
        .disabled(selection.isEmpty)
    }

    #if os(iOS)
    private func enterSelectMode(selecting work: SavedWork? = nil) {
        if let work {
            selection.insert(work.id)
        }
        showingSelectionList = false
        editMode = .active
    }
    #endif

    private func selectAction(for work: SavedWork) -> (() -> Void)? {
        #if os(iOS)
        return { enterSelectMode(selecting: work) }
        #else
        return nil
        #endif
    }

    private func exitSelectMode() {
        #if os(iOS)
        editMode = .inactive
        #endif
        showingSelectionList = false
        selection = []
    }

    @ViewBuilder
    private func localCarouselCard(work: SavedWork, footer: String?, progress: Double?) -> some View {
        #if os(iOS)
        if isSelecting {
            SensitiveWorkCoverCard(
                work: work,
                footer: footer,
                progress: progress,
                isSelecting: true,
                isSelected: selection.contains(work.id),
                onToggleSelection: { toggleSelection(work) }
            )
            .localWorkContextMenu(work: work, onSelect: selectAction(for: work))
        } else {
            NavigationLink(value: LocalWorkDestination.reader(work)) {
                SensitiveWorkCoverCard(work: work, footer: footer, progress: progress)
            }
            .buttonStyle(.plain)
            .localWorkContextMenu(work: work, onSelect: selectAction(for: work))
        }
        #else
        NavigationLink(value: LocalWorkDestination.reader(work)) {
            SensitiveWorkCoverCard(work: work, footer: footer, progress: progress)
        }
        .buttonStyle(.plain)
        .localWorkContextMenu(work: work, onSelect: selectAction(for: work))
        #endif
    }

    private func toggleSelection(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private func bulkDelete() {
        for work in selectedWorks {
            PreservedWorkService.softDelete(work, in: context)
        }
        exitSelectMode()
    }

    /// Toggles saved (keeps its EPUB permanently): if the selection isn't already
    /// all saved, saves everything; if it is, un-saves everything (tap again to
    /// undo). Select mode stays active — unlike Delete, the works are still there,
    /// so the user can keep stacking actions or adjusting the selection.
    private func bulkSave() {
        let shouldSave = !allSelectedAreSaved
        for work in selectedWorks {
            WorkLifecycle.setSaved(work, shouldSave, in: context)
        }
    }

    /// Same toggle behavior as `bulkSave`.
    private func bulkFavorite() {
        let shouldFavorite = !allSelectedAreFavorited
        let now = Date()
        for work in selectedWorks {
            work.isFavorite = shouldFavorite
            work.markModified(now)
        }
        try? context.save()
    }

    private func refreshLibraryDashboard() async {
        _ = await WorkMetadataRefresh.refresh(visibleDashboardWorks, in: context)
        await loadMarkedForLater()
    }

    private func refreshSelectableWorks() async {
        _ = await WorkMetadataRefresh.refresh(selectableWorks, in: context)
    }

    private var visibleDashboardWorks: [SavedWork] {
        unique(
            dashboardWorks(for: .readingNow)
                + dashboardWorks(for: .savedForLater)
                + dashboardWorks(for: .finished)
                + dashboardWorks(for: .downloaded)
        )
    }

    private func dashboardWorks(for kind: LibrarySectionKind) -> [SavedWork] {
        Array(filters.apply(to: kind.works(from: works, visible: passesPrivacy)).prefix(12))
    }

    private func unique(_ works: [SavedWork]) -> [SavedWork] {
        var seen = Set<UUID>()
        return works.filter { seen.insert($0.id).inserted }
    }
}
