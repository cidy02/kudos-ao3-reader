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
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @State private var path = NavigationPath()
    @State private var filters = LibraryFilters()
    @State private var markedForLater: [AO3WorkSummary] = []

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
            .navigationDestination(for: AO3WorkSummary.self) { AO3WorkDetailView(work: $0, path: $path) }
            .toolbar { toolbarContent }
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
                if filters.hasActiveFilters { activeFilterBanner }
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
        let hasItems = !saved.isEmpty || !markedForLater.isEmpty
        return WorkCarouselSection(
            title: kind.title,
            collapseKey: "library.\(kind.rawValue)",
            hasItems: hasItems,
            onSeeAll: hasItems ? { path.append(kind) } : nil
        ) {
            ForEach(saved.prefix(12)) { work in
                NavigationLink(value: work) {
                    WorkCoverCard(work: work, footer: nil, progress: nil)
                }
                .buttonStyle(.plain)
            }
            ForEach(markedForLater.prefix(12)) { work in
                NavigationLink(value: work) { AO3WorkCoverCard(work: work) }
                    .buttonStyle(.plain)
            }
        } emptyState: {
            SectionEmptyState(message: kind.emptyMessage, systemImage: kind.emptyIcon)
        }
    }

    /// Placeholder: shelves aren't backed by a model yet, so this is always its empty
    /// state (no `>` chevron).
    private var collectionsCarousel: some View {
        let kind = LibrarySectionKind.collections
        return WorkCarouselSection(
            title: kind.title,
            collapseKey: "library.\(kind.rawValue)",
            hasItems: false
        ) {
            EmptyView()
        } emptyState: {
            SectionEmptyState(message: kind.emptyMessage, systemImage: kind.emptyIcon)
        }
    }

    private var activeFilterBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.tint)
            Text("Filters active").font(.subheadline.weight(.medium))
            Spacer()
            Button("Reset") { filters = LibraryFilters() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
    }

    // MARK: Card details

    private func footer(_ kind: LibrarySectionKind, _ work: SavedWork) -> String? {
        switch kind {
        case .readingNow: work.lastSpineIndex > 0 ? "Ch \(work.lastSpineIndex + 1)" : nil
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
            if hideMature && works.contains(where: \.isAdult) {
                ToolbarItem { MatureRevealToggle() }
            }
            if !works.isEmpty {
                ToolbarItem { filterButton }
            }
            if !statisticsWorks.isEmpty {
                ToolbarItem {
                    NavigationLink {
                        ReadingStatisticsView(works: statisticsWorks)
                    } label: {
                        Label("Reading Insights", systemImage: "chart.bar.xaxis")
                    }
                }
            }
            #if os(iOS)
            if !works.isEmpty {
                ToolbarItem {
                    Button("Select") { enterSelectMode() }
                }
            }
            #endif
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
        markedForLater = await auth.accountWorks(from: AO3Client.markedForLaterURL)
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
