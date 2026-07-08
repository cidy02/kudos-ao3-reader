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

    // Works sitting in Recently Deleted don't count toward the card's size.
    private var workCount: Int {
        collection.works.count(where: { !$0.isPendingDeletion })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            tile
                .frame(width: CarouselCardMetrics.width, height: CarouselCardMetrics.height)
            Text(collection.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("\(workCount) work\(workCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: CarouselCardMetrics.width, alignment: .leading)
    }

    private var tile: some View {
        let hue = CoverArt.hue(for: collection.name)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(width: CarouselCardMetrics.width, height: CarouselCardMetrics.height)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            Text("New Collection")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("Tap to create")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: CarouselCardMetrics.width, alignment: .leading)
    }
}

// MARK: - Collection detail

/// The works in a collection. Rows open the reader; Work Details remains in the
/// long-press menu. Swipe removes a work from the collection (it isn't deleted). The
/// menu renames or deletes the collection itself.
struct CollectionDetailView: View {
    let collection: WorkCollection

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var expandAll = false
    /// Filters scoped to this one collection, applied live to its works.
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    /// Tracks the in-flight refresh so it can be cancelled if the user switches tabs
    /// (see `cancelRefreshOnTabChange`) — a collection can hold a large number of works.
    @State private var refreshTask: Task<Void, Never>?

    // A soft-deleted work stays linked to the collection (restore brings it back
    // here) but renders only in Recently Deleted until then.
    private var works: [SavedWork] {
        collection.works.filter { !$0.isPendingDeletion }.sorted { $0.dateAdded > $1.dateAdded }
    }

    /// The collection's works after the active filters. With no filter set, the default
    /// newest-first order is kept rather than re-sorted by the filter's default sort.
    private var visibleWorks: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: works) : works
    }

    var body: some View {
        Group {
            if works.isEmpty {
                ContentUnavailableView {
                    Label(collection.name, systemImage: "square.stack")
                } description: {
                    Text("No works yet. Add works to this collection from a work's page (Add to Collection).")
                }
            } else {
                List {
                    ForEach(visibleWorks) { work in
                        SensitiveWorkRow(work: work, expandAll: expandAll, openMode: .reader)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    remove(work)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                    }
                    .cardRow()
                }
                .cardList()
                .refreshable {
                    let task = Task { _ = await WorkMetadataRefresh.refresh(visibleWorks, in: context) }
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
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 2) {
                        if !works.isEmpty {
                            FilterButton(filtersActive: filters.hasActiveFilters,
                                         showingFilters: $showingFilters,
                                         filterHelp: "Filter the works in this collection",
                                         onClearFilters: { filters = LibraryFilters() })
                        }
                        WorkListMoreMenu {
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
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("Delete Collection", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .alert("Rename Collection", isPresented: $showingRename) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        collection.name = trimmed
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
    }

    private func remove(_ work: SavedWork) {
        SyncTombstones.recordCollectionMembershipRemoval(work: work, collection: collection, in: context)
        work.collections.removeAll { $0.id == collection.id }
        work.markModified()
        collection.markModified()
        try? context.save()
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
                        Button("Done") { dismiss() }
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
        }
        collection.markModified(now)
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
