import SwiftUI
import SwiftData

/// The Library tab: a Books-style dashboard of the user's saved works. Every section
/// is a collapsible horizontal card carousel with a `>` chevron that opens its full
/// vertical list. Sections, in order: Reading Now, Saved for Later, Finished,
/// Collections, Downloaded. Saved for Later merges in the user's AO3 "Marked for
/// Later" list; Collections is a placeholder until shelves land.
///
/// Filtering (the inspector panel), Reading Insights, content privacy, and — on iOS —
/// multi-select bulk actions are kept from the previous list-based Library.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var works: [SavedWork]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \WorkCollection.dateAdded, order: .reverse) private var collections: [WorkCollection]
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

    // Multi-select / bulk actions. `EditMode` is iOS-only, so macOS has no select mode.
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    @State private var selection = Set<UUID>()
    @State private var confirmBulkDelete = false

    private var isSelecting: Bool {
        #if os(iOS)
        editMode.isEditing
        #else
        false
        #endif
    }
    private var selectedWorks: [SavedWork] { works.filter { selection.contains($0.id) } }

    /// Keeps privacy-hidden works out of aggregate counts and fandom labels.
    private var statisticsWorks: [SavedWork] {
        works.filter { !hideMature || !$0.isAdult || gate.isRevealed($0) }
    }

    /// Drops Mature/Explicit works in Hide mode (until revealed); Blur mode keeps them
    /// in the list but `SensitiveWorkRow` blurs them.
    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    /// The user's own tag names, for the filter panel's "Your Tags" facet.
    private var userTagNames: [String] { tags.map(\.name) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isSelecting {
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
            .navigationDestination(for: LibrarySectionKind.self) { LibrarySectionListView(kind: $0) }
            .navigationDestination(for: WorkCollection.self) { CollectionDetailView(collection: $0) }
            .navigationDestination(for: AO3WorkSummary.self) { WorkDetailView(remote: $0) }
            .toolbar { toolbarContent }
            .alert("New Collection", isPresented: $showingNewCollection) {
                TextField("Name", text: $newCollectionName)
                Button("Create") { createCollection() }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            } message: {
                Text("Name your collection.")
            }
            .confirmationDialog(
                "Delete \(selection.count) work\(selection.count == 1 ? "" : "s")?",
                isPresented: $confirmBulkDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { bulkDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The selected works will be removed from your Library. This can't be undone.")
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
            .task { await backfillFilterMetadata() }
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
                collectionsCarousel
                localCarousel(.downloaded)
            }
            .padding(.vertical, 12)
        }
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
                NavigationLink(value: work) {
                    WorkCoverCard(work: work, footer: footer(kind, work), progress: progress(kind, work))
                }
                .buttonStyle(.plain)
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
                ForEach(0..<6, id: \.self) { _ in WorkCoverCardSkeleton() }
            } else {
                ForEach(saved.prefix(12)) { work in
                    NavigationLink(value: work) {
                        WorkCoverCard(work: work, footer: nil, progress: nil)
                    }
                    .buttonStyle(.plain)
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

    /// The AO3 Marked-for-Later (remote) list, narrowed by the active fandom
    /// quick-filter so the chips affect this section too. The other, metadata-only
    /// filters don't apply to remote summaries (they carry no rating/word count).
    private var filteredMarkedForLater: [AO3WorkSummary] {
        guard !filters.fandoms.isEmpty else { return markedForLater }
        let wanted = Set(filters.fandoms.map { $0.lowercased() })
        return markedForLater.filter { summary in
            summary.fandoms.contains { wanted.contains($0.lowercased()) }
        }
    }

    /// User-named Collections (shelves). A leading "New" card is always present so
    /// creating one is one tap away; existing collections follow. Tapping a card
    /// opens the collection; the `>` chevron isn't used (the New card covers create).
    private var collectionsCarousel: some View {
        let kind = LibrarySectionKind.collections
        return WorkCarouselSection(
            title: kind.title,
            collapseKey: "library.\(kind.rawValue)",
            hasItems: true
        ) {
            Button {
                newCollectionName = ""
                showingNewCollection = true
            } label: {
                NewCollectionCard()
            }
            .buttonStyle(.plain)

            ForEach(collections) { collection in
                NavigationLink(value: collection) {
                    CollectionCard(collection: collection)
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
            .filter(passesPrivacy)
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
                    if hideMature && works.contains(where: \.isAdult) {
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
    }

    // MARK: Loading

    /// Fills in the filter metadata (categorized Work Tags, warnings, categories,
    /// language, word count) for any saved works that predate it, by refreshing each
    /// from AO3 once. Runs over *all* works — not the filtered subset — so a work isn't
    /// kept hidden by a filter it would actually match. Sequential, so it never bursts
    /// requests; each refresh is guarded and skips complete works / those with no source.
    private func backfillFilterMetadata() async {
        for work in works where work.needsAO3Refresh {
            await WorkTags.refreshFromAO3(for: work, in: context)
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
        markedForLater = await auth.accountWorks(from: AO3Client.markedForLaterURL)
        isLoadingMarkedForLater = false
    }

    private func createCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCollectionName = ""
        guard !trimmed.isEmpty else { return }
        context.insert(WorkCollection(name: trimmed))
        try? context.save()
    }

    // MARK: Multi-select / bulk actions

    /// All local works visible under privacy + the active filters, for the iOS
    /// select-mode list. Already newest-first from the query.
    private var selectableWorks: [SavedWork] {
        filters.apply(to: works.filter(passesPrivacy))
    }

    @ViewBuilder
    private var selectList: some View {
        #if os(iOS)
        List(selection: $selection) {
            Section {
                ForEach(selectableWorks) { SensitiveWorkRow(work: $0) }
                    .cardRow()
            }
        }
        .cardList()
        .environment(\.editMode, $editMode)
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
            Label("Save", systemImage: "bookmark")
        }
        .disabled(selection.isEmpty)

        Spacer()

        Button {
            bulkFavorite()
        } label: {
            Label("Favorite", systemImage: "star")
        }
        .disabled(selection.isEmpty)
    }

    #if os(iOS)
    private func enterSelectMode() {
        selection = []
        editMode = .active
    }
    #endif

    private func exitSelectMode() {
        #if os(iOS)
        editMode = .inactive
        #endif
        selection = []
    }

    private func bulkDelete() {
        for work in selectedWorks { WorkLifecycle.delete(work, in: context) }
        exitSelectMode()
    }

    /// Marks every selected work as saved (keeps its EPUB permanently).
    private func bulkSave() {
        for work in selectedWorks { WorkLifecycle.setSaved(work, true, in: context) }
        exitSelectMode()
    }

    private func bulkFavorite() {
        for work in selectedWorks { work.isFavorite = true }
        try? context.save()
        exitSelectMode()
    }
}
