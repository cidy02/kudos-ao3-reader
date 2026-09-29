import SwiftData
import SwiftUI

/// Navigation route for the Collections carousel's "See all" destination.
struct AllCollectionsDestination: Hashable {}

// MARK: - Cards

/// A Library Collections carousel card: a tinted tile (hued from the collection
/// name, with a stack glyph so it reads as a shelf, not a single work), the name,
/// and a work count. Sized to match `WorkCoverCard`.
struct CollectionCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let collection: WorkCollection

    /// Scales width and height together so the card grows proportionally at
    /// large Dynamic Type sizes instead of only getting taller.
    var cardSize = ScaledCarouselCardSize()

    /// Explicit, non-defaulted init — see `ReadingQueueCard.init` in
    /// ReadingQueues.swift for why this matters here.
    init(collection: WorkCollection) {
        self.collection = collection
    }

    // Works sitting in Recently Deleted don't count toward the card's size or the stack.
    private var visibleWorks: [SavedWork] {
        collection.works.filter { !$0.isPendingDeletion }.sorted { $0.dateAdded > $1.dateAdded }
    }

    private var workCount: Int {
        visibleWorks.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            tile
                .frame(minWidth: cardSize.width, maxWidth: cardSize.width,
                       minHeight: cardSize.height)
            Text(collection.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("\(workCount) work\(workCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: cardSize.width, alignment: .leading)
    }

    // 2+ works reads as a shelf of the actual works inside; 0-1 keeps the abstract
    // name-hued tile — a single face would just be a worse-looking work card, and an
    // empty stack has no titles to hue.
    @ViewBuilder
    private var tile: some View {
        if workCount >= 2 {
            StackedWorkCover(workTitles: visibleWorks.map(\.title), cardSize: cardSize)
        } else {
            singleTile
        }
    }

    private var singleTile: some View {
        let hue = collection.displayHue
        let gradient = themeManager.appTheme.carouselCollectionGradient(hue: hue)
        return RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
            .fill(LinearGradient(
                colors: [gradient.start, gradient.end],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                Image(systemName: "square.stack.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}

/// The leading "create" card in the Collections carousel.
struct NewCollectionCard: View {
    /// Scales width and height together so the card grows proportionally at
    /// large Dynamic Type sizes instead of only getting taller.
    var cardSize = ScaledCarouselCardSize()

    /// Explicit, non-defaulted init — see `ReadingQueueCard.init` in
    /// ReadingQueues.swift for why this matters here.
    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(minWidth: cardSize.width, maxWidth: cardSize.width,
                       minHeight: cardSize.height)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            Text("New collection")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("Tap to create")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: cardSize.width, alignment: .leading)
    }
}

// MARK: - Collection detail

/// The works in a collection. Rows open the reader; Work Details remains in the
/// long-press menu. Swipe removes a work from the collection (it isn't deleted). The
/// menu renames or deletes the collection itself.
struct CollectionDetailView: View {
    @AppStorage("hideMatureContent") private var hideMature = true
    let collection: WorkCollection

    @Environment(\.modelContext) private var context
    @Environment(DownloadQueue.self) private var downloadQueue
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AO3AuthService.self) private var auth
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @State private var showingRename = false
    @State private var showingDetails = false
    @State private var showingReorder = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var showingAddWorks = false
    @State private var expandAll = false
    @State private var pendingRemoval: SavedWork?
    /// Filters scoped to this one collection, applied live to its works.
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    /// Tracks the in-flight refresh so it can be cancelled if the user switches tabs
    /// (see `cancelRefreshOnTabChange`) — a collection can hold a large number of works.
    @State private var refreshTask: Task<Void, Never>?

    // A soft-deleted work stays linked to the collection (restore brings it back
    // here) but renders only in Recently Deleted until then.
    private var works: [SavedWork] {
        collection.inReadingOrder(collection.works.filter { !$0.isPendingDeletion })
    }

    /// The collection's works after the active filters. With no filter set, the default
    /// newest-first order is kept rather than re-sorted by the filter's default sort.
    private var visibleWorks: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: works) : works
    }

    /// Writes straight through to the model, like Rename beside it — there is no
    /// Save on this screen and never was.
    ///
    /// 1bk's create sheet (`NewCollectionSheet`) has two groups, Collection and
    /// Behaviour, and every field in both was editable exactly once: at
    /// creation. Colour had its own sheet already; description and the two
    /// behaviour toggles had no edit path at all — set once, permanent. This is
    /// that sheet widened to cover the rest of what creation asks for, rather
    /// than a fourth single-purpose one next to Rename/Colour/Reorder/Delete.
    // Split out of `detailsSheet` one section at a time — three sections'
    // worth of inline Bindings in one `Form` timed out the type checker.
    private var detailsColourSection: some View {
        Section {
            SubjectHueSwatchRow(
                selection: Binding(
                    get: { collection.hue },
                    set: { newValue in
                        collection.hue = newValue
                        // Not `markMembershipChanged` — a colour is not a
                        // choice about contents, and stamping that clock here
                        // would make recolouring a collection override a
                        // removal made on another device.
                        collection.markModified()
                        context.saveBestEffort(reason: "Saving collection colour failed")
                    }
                ),
                fallbackHue: collection.displayHue
            )
        } header: {
            SubjectFieldLabel(text: "Colour", style: .formGroup)
        } footer: {
            Text(collection.hue == nil
                ? "Taken from the collection's name, so renaming it changes the colour."
                : "Set on the collection, so renaming it keeps this colour.")
        }
        .appThemedRows()
    }

    private var detailsDescriptionSection: some View {
        Section {
            TextField(
                "Optional",
                text: Binding(
                    get: { collection.collectionDescription ?? "" },
                    set: { newValue in
                        collection.collectionDescription = newValue
                        collection.markModified()
                        context.saveBestEffort(reason: "Saving collection description failed")
                    }
                ),
                axis: .vertical
            )
        } header: {
            SubjectFieldLabel(text: "Description", style: .formGroup)
        }
        .appThemedRows()
    }

    private var detailsBehaviourSection: some View {
        Section {
            Toggle(
                "Keep downloads",
                isOn: Binding(
                    get: { collection.keepsWorksOffline ?? false },
                    set: { newValue in
                        collection.keepsWorksOffline = newValue
                        collection.markModified()
                        context.saveBestEffort(reason: "Saving collection behaviour failed")
                        // T-276: on fetches the works still missing their EPUB,
                        // through the paced download queue. Only this tap starts it.
                        if newValue {
                            downloadQueue.enqueue(KeepOffline.downloadItems(for: collection.works), into: context)
                        }
                    }
                )
            )
            Toggle(
                "Show on Home",
                isOn: Binding(
                    get: { collection.showsOnHome },
                    set: { newValue in
                        collection.showsOnHome = newValue
                        collection.markModified()
                        context.saveBestEffort(reason: "Saving collection behaviour failed")
                    }
                )
            )
        } header: {
            SubjectFieldLabel(text: "Behaviour", style: .formGroup)
        } footer: {
            // 1bk's copy, as at creation (`NewCollectionSheet.behaviourFootnote`).
            Text(NewCollectionSheet.behaviourFootnote)
        }
        .appThemedRows()
    }

    private var detailsSheet: some View {
        NavigationStack {
            Form {
                detailsColourSection
                detailsDescriptionSection
                detailsBehaviourSection
            }
            .appThemedScroll()
            .navigationTitle(collection.name)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingDetails = false }
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    var body: some View {
        Group {
            if works.isEmpty {
                ContentUnavailableView {
                    Label(collection.name, systemImage: "square.stack")
                } description: {
                    Text("No works yet. Add works from your library here, or from any "
                        + "work's page (Add to Collection).")
                } actions: {
                    Button {
                        showingAddWorks = true
                    } label: {
                        Label("Add Works", systemImage: "plus")
                    }
                }
            } else {
                List {
                    ForEach(visibleWorks) { work in
                        SensitiveWorkRow(
                            work: work,
                            expandAll: expandAll,
                            openMode: .reader,
                            isSelecting: isSelecting,
                            isSelected: selection.contains(work.id),
                            onToggleSelection: { toggleSelection(work) }
                        )
                        .swipeActions(edge: .trailing) {
                            if !isSelecting {
                                Button(role: .destructive) {
                                    if confirmBeforeDelete {
                                        pendingRemoval = work
                                    } else {
                                        remove(work)
                                    }
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                    .cardRow()
                }
                .cardList()
                .refreshable {
                    let task = Task { _ = await WorkMetadataRefresh.refresh(visibleWorks, in: context, auth: auth) }
                    refreshTask = task
                    await task.value
                }
                .cancelRefreshOnTabChange($refreshTask)
                .overlay {
                    // Collection has works, but the active filters hid them all.
                    if visibleWorks.isEmpty {
                        ContentUnavailableView {
                            Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("No works in this collection match the current filters.")
                        } actions: {
                            Button("Clear Filters") { filters = LibraryFilters() }
                        }
                    }
                }
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle(collection.name)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .inspector(isPresented: $showingFilters) {
                LibraryFilterPanel(filters: $filters, works: works, userTagNames: allTags.map(\.name))
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                #if os(iOS)
                    .presentationDragIndicator(.visible)
                #endif
            }
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .confirmationAction) {
                        SelectAllButton(allSelected: allSelected, action: toggleSelectAll)
                    }
                    #if os(iOS)
                    ToolbarItemGroup(placement: .bottomBar) {
                        ScopedRemovalBulkActionBar(
                            selectedWorks: selectedWorks,
                            removeLabel: "Remove from Collection",
                            scopeName: "collection",
                            onRemove: bulkRemove,
                            onDone: exitSelectMode
                        )
                    }
                    #else
                    ToolbarItemGroup(placement: .primaryAction) {
                        ScopedRemovalBulkActionBar(
                            selectedWorks: selectedWorks,
                            removeLabel: "Remove from Collection",
                            scopeName: "collection",
                            onRemove: bulkRemove,
                            onDone: exitSelectMode
                        )
                    }
                    #endif
                } else {
                    ActionToolbar(items: [
                        AnyView(ToolbarIconButton(title: "Add Works", systemImage: "plus") {
                            showingAddWorks = true
                        }),
                        !works.isEmpty
                            ? AnyView(FilterButton(filtersActive: filters.hasActiveFilters,
                                                    showingFilters: $showingFilters,
                                                    filterHelp: "Filter the works in this collection",
                                                    onClearFilters: { filters = LibraryFilters() }))
                            : nil,
                        AnyView(WorkListMoreMenu {
                            if hideMature {
                                MatureRevealToggle()
                            }
                            // The app's order: Mature · Select · Reorder · Expand ·
                            // page items · destructive last.
                            if !works.isEmpty {
                                Button {
                                    isSelecting = true
                                } label: {
                                    Label("Select", systemImage: "checklist")
                                }
                            }
                            if works.count > 1 {
                                Button {
                                    showingReorder = true
                                } label: {
                                    Label(
                                        filters.hasActiveFilters ? "Clear Filters to Reorder" : "Reorder",
                                        systemImage: "arrow.up.arrow.down"
                                    )
                                }
                                .disabled(filters.hasActiveFilters)
                            }
                            if !works.isEmpty {
                                ExpandAllMenuItem(expandAll: $expandAll)
                                Divider()
                            }
                            Button {
                                renameText = collection.name
                                showingRename = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            // 1bk: "editing is the same sheet with the values
                            // filled". Rename stays its own quick alert — a name
                            // is the one field worth changing without leaving
                            // this screen — but colour, description and the two
                            // behaviour toggles are `detailsSheet`, which is
                            // creation's own Collection/Behaviour shape, filled.
                            Button {
                                showingDetails = true
                            } label: {
                                Label("Details", systemImage: "paintpalette")
                            }
                            // 1bk's "Remove works" is Select by another name — this
                            // screen already removes through selection.
                            Divider()
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("Delete Collection", systemImage: "trash")
                            }
                        })
                    ].compactMap { $0 })
                }
            }
            #if os(iOS)
                // Select mode owns the bottom edge with its bulk-action bar (matches
                // LibraryView's own selection-mode tab-bar hide).
                .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            #endif
            .sheet(isPresented: $showingAddWorks) {
                AddLibraryWorksSheet(
                    destinationName: collection.name,
                    scopeName: "collection",
                    candidates: { CollectionWorkPicker.candidates(from: $0, notIn: collection) },
                    onAdd: { chosen in
                        CollectionWorkPicker.add(chosen, to: collection, in: context)
                        // T-276: a Keep-downloads collection fetches what it just gained.
                        if KeepOffline.collectionKeeps(collection.keepsWorksOffline) {
                            downloadQueue.enqueue(KeepOffline.downloadItems(for: chosen), into: context)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingDetails) { detailsSheet }
            .sheet(isPresented: $showingReorder) {
                CollectionReorderSheet(collection: collection, works: works)
            }
            .alert("Rename Collection", isPresented: $showingRename) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        collection.name = trimmed
                        // A rename says nothing about membership — see the
                        // colour setter above.
                        collection.markModified()
                        try? context.save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete “\(collection.name)”?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    PreservedWorkService.softDelete(collection, in: context)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The collection moves to Recently Deleted for 90 days. The works "
                        + "themselves stay in your Library either way."
                )
            }
            .destructiveConfirmation(
                for: $pendingRemoval,
                title: "Remove this work?",
                confirmLabel: "Remove",
                message: { work in
                    "“\(work.title)” will no longer be in “\(collection.name)”. "
                        + "The work itself stays in your Library."
                },
                perform: { remove($0) }
            )
    }

    private func remove(_ work: SavedWork) {
        SyncTombstones.recordCollectionMembershipRemoval(work: work, collection: collection, in: context)
        work.collections.removeAll { $0.id == collection.id }
        work.markModified()
        collection.markMembershipChanged()
        try? context.save()
    }

    // MARK: Multi-select / bulk actions

    private var selectedWorks: [SavedWork] {
        works.filter { selection.contains($0.id) }
    }

    private var allSelected: Bool {
        let ids = Set(works.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    private func toggleSelectAll() {
        selection = allSelected ? [] : Set(works.map(\.id))
    }

    private func toggleSelection(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private func exitSelectMode() {
        isSelecting = false
        selection = []
    }

    private func bulkRemove() {
        for work in selectedWorks {
            remove(work)
        }
    }
}

// MARK: - Add to collection

/// A sheet to add/remove a work from collections, and create new ones. Presented
/// from a work's detail page.
struct AddToCollectionView: View {
    let works: [SavedWork]

    init(work: SavedWork) {
        works = [work]
    }

    init(works: [SavedWork]) {
        self.works = works
    }

    @Environment(\.modelContext) private var context
    @Environment(DownloadQueue.self) private var downloadQueue
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<WorkCollection> { !$0.isPendingDeletion },
        sort: \WorkCollection.dateAdded, order: .reverse
    )
    private var collections: [WorkCollection]
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("New collection", text: $newName)
                            .onSubmit(create)
                        Button("Add", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if collections.isEmpty {
                    Section {
                        Text("No collections yet. Create one above to start grouping works.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Collections") {
                        ForEach(collections) { collection in
                            Button {
                                toggle(collection)
                            } label: {
                                HStack {
                                    Text(collection.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(collection.works.count(where: { !$0.isPendingDeletion }))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if isMember(collection) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                            .accessibilityLabel("In this collection")
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add to Collection")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Done")
                    }
                }
                // Same stub cleanup as AddToQueueView: metadata-only rows created only
                // to open this sheet shouldn't linger if the user never attaches them.
                .onDisappear {
                    for work in works {
                        ReadingQueueService.discardUnattachedMetadataIfNeeded(work, in: context)
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private func isMember(_ collection: WorkCollection) -> Bool {
        works.allSatisfy { work in work.collections.contains { $0.id == collection.id } }
    }

    private func toggle(_ collection: WorkCollection) {
        let now = Date()
        if isMember(collection) {
            for work in works {
                SyncTombstones.recordCollectionMembershipRemoval(work: work, collection: collection, in: context)
                work.collections.removeAll { $0.id == collection.id }
                work.markModified(now)
            }
        } else {
            for work in works where !work.collections.contains(where: { $0.id == collection.id }) {
                work.collections.append(collection)
                work.markModified(now)
            }
            // T-276: a Keep-downloads collection fetches what it just gained.
            if KeepOffline.collectionKeeps(collection.keepsWorksOffline) {
                downloadQueue.enqueue(KeepOffline.downloadItems(for: works), into: context)
            }
        }
        collection.markMembershipChanged(now)
        try? context.save()
    }

    private func create() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let collection = WorkCollection(name: trimmed)
        context.insert(collection)
        let now = Date()
        for work in works {
            work.collections.append(collection)
            work.markModified(now)
        }
        try? context.save()
        newName = ""
    }
}

// MARK: - Add works to a collection (from inside the collection)

/// The membership rules behind a collection's `AddLibraryWorksSheet`, kept free of view/@Query
/// state so they're unit-testable. Privacy filtering stays in the view (it needs the
/// live `PrivacyGate`); everything here is pure eligibility + the add mutation.
enum CollectionWorkPicker {
    /// Library works eligible to be added to `collection`: real works only (queue-only
    /// EPUB-preservation records are excluded) that aren't already members.
    static func candidates(from works: [SavedWork], notIn collection: WorkCollection) -> [SavedWork] {
        works.filter { work in
            !work.isQueueOnlyWork && !work.collections.contains { $0.id == collection.id }
        }
    }

    /// Adds `works` to `collection`, idempotently (already-members are skipped), stamping
    /// both sides modified for sync and saving. Mirrors `AddToCollectionView`'s add
    /// branch; adds never record a tombstone (only removals do).
    static func add(_ works: [SavedWork], to collection: WorkCollection,
                    in context: ModelContext, now: Date = Date()) {
        for work in works where !work.collections.contains(where: { $0.id == collection.id }) {
            work.collections.append(collection)
            work.markModified(now)
        }
        collection.markMembershipChanged(now)
        try? context.save()
    }
}
