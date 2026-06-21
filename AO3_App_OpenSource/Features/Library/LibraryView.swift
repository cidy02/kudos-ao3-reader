import SwiftUI
import SwiftData

/// The library tab: saved works, filterable by tag, opening into the reader.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(PrivacyGate.self) private var gate
    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var works: [SavedWork]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @State private var filters = LibraryFilters()
    @State private var pendingDelete: SavedWork?

    // Multi-select / bulk actions.
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var confirmBulkDelete = false

    /// Tap a Continue Reading card to resume straight into the reader.
    @State private var resumeWork: SavedWork?

    private var isSelecting: Bool { editMode.isEditing }
    private var selectedWorks: [SavedWork] { works.filter { selection.contains($0.id) } }

    /// Keeps privacy-hidden works out of aggregate counts and fandom labels.
    private var statisticsWorks: [SavedWork] {
        works.filter {
            !hideMature || !$0.isAdult || gate.isRevealed($0)
        }
    }

    /// In-progress works (started, not finished, file present), most recently read
    /// first — the "Continue Reading" shelf. Capped so the shelf stays compact.
    private var continueReading: [SavedWork] {
        works
            .filter { $0.hasEPUB && !$0.isFinished
                && ($0.lastSpineIndex > 0 || $0.lastScrollFraction > 0 || !$0.readiumLocator.isEmpty)
                && passesPrivacy($0) }
            .sorted { ($0.lastReadDate ?? $0.dateAdded) > ($1.lastReadDate ?? $1.dateAdded) }
            .prefix(10)
            .map { $0 }
    }

    /// In-progress, transient downloads: have an EPUB, not explicitly saved,
    /// not finished. Finishing an unprotected work frees its EPUB and removes it.
    private var readingWorks: [SavedWork] {
        filters.apply(to: works.filter { $0.hasEPUB && !$0.isSaved && !$0.isFinished && passesPrivacy($0) })
    }

    /// The permanent shelf: works the user explicitly saved.
    private var savedWorks: [SavedWork] {
        filters.apply(to: works.filter { $0.isSaved && passesPrivacy($0) })
    }

    /// Drops Mature/Explicit works in Hide mode (until revealed); Blur mode keeps
    /// them in the list but `SensitiveWorkRow` blurs them.
    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    /// The user's own tag names, for the filter panel's "Your Tags" facet.
    private var userTagNames: [String] { tags.map(\.name) }

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

    var body: some View {
        NavigationStack {
            Group {
                if readingWorks.isEmpty && savedWorks.isEmpty {
                    if hasHiddenWorks {
                        MatureContentHiddenView()
                    } else if filters.hasActiveFilters {
                        noMatchState
                    } else {
                        emptyState
                    }
                } else {
                    List(selection: $selection) {
                        if !isSelecting && !continueReading.isEmpty {
                            Section("Continue Reading") {
                                continueReadingShelf
                            }
                        }
                        if !readingWorks.isEmpty {
                            Section("Reading") {
                                ForEach(readingWorks, content: row).cardRow()
                            }
                        }
                        if !savedWorks.isEmpty {
                            Section("Saved") {
                                ForEach(savedWorks, content: row).cardRow()
                            }
                        }
                    }
                    .cardList()
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationTitle(isSelecting
                ? (selection.isEmpty ? "Select Works" : "\(selection.count) Selected")
                : "Library")
            #if os(iOS)
            // Large, left-aligned title kept inline on the toolbar row (alongside the
            // eye/filter buttons) rather than dropping to its own row. Restores the
            // proper title size/alignment after the scroll-fix regression made it
            // small + centered (.inline).
            .toolbarTitleDisplayMode(.inlineLarge)
            #endif
            .navigationDestination(for: SavedWork.self) { work in
                WorkDetailView(work: work)
            }
            // Continue Reading cards resume straight into the reader (these works
            // all have their EPUB on disk, so no re-download is needed).
            .navigationDestination(item: $resumeWork) { work in
                BookReaderView(work: work)
            }
            .toolbar {
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
                    if !works.isEmpty {
                        ToolbarItem {
                            Button("Select") { enterSelectMode() }
                        }
                    }
                }
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
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Delete this work?",
                confirmLabel: "Delete",
                message: { "“\($0.title)” will be removed from your Library. This can't be undone." },
                perform: { delete($0) }
            )
            .task { await backfillFilterMetadata() }
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

    /// Fills in the filter metadata (categorized Work Tags, warnings, categories,
    /// language, word count) for any saved works that predate it, by refreshing
    /// each from AO3 once. Runs over *all* works — not the filtered subset — so a
    /// work isn't kept hidden by a filter it would actually match. Sequential, so
    /// it never bursts requests; each refresh is guarded and skips works that are
    /// already complete or have no AO3 source.
    private func backfillFilterMetadata() async {
        for work in works where work.needsAO3Refresh {
            await WorkTags.refreshFromAO3(for: work, in: context)
        }
    }

    /// A horizontal shelf of Continue Reading cards; tapping one resumes the reader.
    private var continueReadingShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(continueReading) { work in
                    Button { resumeWork = work } label: {
                        ContinueReadingCard(work: work)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func row(_ work: SavedWork) -> some View {
        SensitiveWorkRow(work: work)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                WorkLifecycle.setSaved(work, !work.isSaved, in: context)
            } label: {
                Label(
                    work.isSaved ? "Unsave" : "Save",
                    systemImage: work.isSaved ? "bookmark.slash" : "bookmark"
                )
            }
            .tint(.blue)

            Button {
                toggleFavorite(work)
            } label: {
                Label(
                    work.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: work.isFavorite ? "star.slash" : "star"
                )
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                if confirmBeforeDelete { pendingDelete = work } else { delete(work) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No saved works yet", systemImage: "books.vertical")
        } description: {
            Text("Browse AO3 and download a work as EPUB to add it here.")
        } actions: {
            Button("Browse AO3") { router.selection = .browse }
        }
    }

    /// Filters are active but no saved work matches them.
    private var noMatchState: some View {
        ContentUnavailableView {
            Label("No works match", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No saved works match the current filters.")
        } actions: {
            Button("Reset Filters") { filters = LibraryFilters() }
        }
    }

    /// Shown when the library has works but they're all hidden by content privacy.
    private var hasHiddenWorks: Bool {
        hideMature && matureMode == .hide && !gate.revealAll && works.contains(where: \.isAdult)
    }

    private func toggleFavorite(_ work: SavedWork) {
        work.isFavorite.toggle()
        try? context.save()
    }

    private func delete(_ work: SavedWork) {
        try? FileManager.default.removeItem(at: work.fileURL)
        try? FileManager.default.removeItem(at: Storage.readerDirectory(for: work.id))
        context.delete(work)
        try? context.save()
    }

    // MARK: Multi-select / bulk actions

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

    private func enterSelectMode() {
        selection = []
        editMode = .active
    }

    private func exitSelectMode() {
        editMode = .inactive
        selection = []
    }

    private func bulkDelete() {
        for work in selectedWorks { delete(work) }
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

/// A compact card for the Library's Continue Reading shelf: title, author, and the
/// chapter to resume at.
private struct ContinueReadingCard: View {
    let work: SavedWork

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(work.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if !work.author.isEmpty {
                Text(work.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Label(resumeText, systemImage: "book")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 168, height: 112, alignment: .topLeading)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }

    private var resumeText: String {
        work.lastSpineIndex > 0 ? "Resume · Ch \(work.lastSpineIndex + 1)" : "Resume"
    }
}
