import SwiftUI
import SwiftData

/// The full, vertically scrolling list behind a Library section's `>` chevron.
/// Mirrors `HomeSectionListView`, but adds the Library's per-row swipe actions and,
/// for Saved for Later, also surfaces the user's AO3 "Marked for Later" list in a
/// second section. Navigation resolves through the Library's root stack (which
/// registers the `SavedWork` and `AO3WorkSummary` destinations).
struct LibrarySectionListView: View {
    let kind: LibrarySectionKind

    @Environment(\.modelContext) private var context
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AO3AuthService.self) private var auth
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true

    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var works: [SavedWork]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var pendingDelete: SavedWork?
    @State private var markedForLater: [AO3WorkSummary] = []
    @State private var expandAll = false
    /// Filters scoped to this one section — applied live to the works already on the
    /// page, not the app-wide Library filter.
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    /// This section's works (before the filter panel narrows them further).
    private var items: [SavedWork] { kind.works(from: works, visible: passesPrivacy) }

    /// This section's works after the active filters — what the list renders. When no
    /// filter is set, the section's own ordering (e.g. most-recently-read first) is kept
    /// rather than re-sorted by the filter's default sort.
    private var visibleItems: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: items) : items
    }

    /// The remote Marked-for-Later list, narrowed by the active fandom filter (the
    /// other facets need local metadata these summaries don't carry).
    private var visibleMarkedForLater: [AO3WorkSummary] {
        guard !filters.fandoms.isEmpty else { return markedForLater }
        let wanted = Set(filters.fandoms.map { $0.lowercased() })
        return markedForLater.filter { summary in
            summary.fandoms.contains { wanted.contains($0.lowercased()) }
        }
    }

    /// Saved for Later is the one section that merges in a remote (AO3) list.
    private var showsMarkedForLater: Bool { kind == .savedForLater && !visibleMarkedForLater.isEmpty }

    /// Whether the section has any works at all (pre-filter) — drives the toolbar.
    private var hasAnyContent: Bool {
        !items.isEmpty || (kind == .savedForLater && !markedForLater.isEmpty)
    }

    var body: some View {
        content
            .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle(kind.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if hasAnyContent {
                    ToolbarItem(placement: .primaryAction) {
                        WorkCardListControls(expandAll: $expandAll,
                                             filtersActive: filters.hasActiveFilters,
                                             showingFilters: $showingFilters,
                                             filterHelp: "Filter the works in this section")
                    }
                }
            }
            .inspector(isPresented: $showingFilters) {
                LibraryFilterPanel(filters: $filters, works: items, userTagNames: allTags.map(\.name))
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                    #if os(iOS)
                    .presentationDragIndicator(.visible)
                    #endif
            }
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Delete this work?",
                confirmLabel: "Delete",
                message: { "“\($0.title)” will be removed from your Library. This can't be undone." },
                perform: { WorkLifecycle.delete($0, in: context) }
            )
            .task(id: auth.isLoggedIn) {
                if kind == .savedForLater { await loadMarkedForLater() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if kind.isPlaceholder {
            ContentUnavailableView {
                Label(kind.title, systemImage: kind.emptyIcon)
            } description: {
                Text(kind.emptyMessage)
            }
        } else if !hasAnyContent {
            // The section genuinely has no works (independent of any filter).
            ContentUnavailableView {
                Label(kind.title, systemImage: kind.emptyIcon)
            } description: {
                Text(kind.emptyMessage)
            }
        } else {
            List {
                if !visibleItems.isEmpty {
                    Section {
                        ForEach(visibleItems, content: row).cardRow()
                    } header: {
                        if showsMarkedForLater { Text("Saved for Later in Kudos") }
                    }
                }
                if showsMarkedForLater {
                    Section("Marked for Later on AO3") {
                        ForEach(visibleMarkedForLater) { work in
                            AO3WorkRow(work: work, expandAll: expandAll).cardNavigation(to: work)
                        }
                        .cardRow()
                    }
                }
            }
            .cardList()
            .overlay {
                // Section has works, but the active filters hid them all.
                if visibleItems.isEmpty && !showsMarkedForLater {
                    ContentUnavailableView {
                        Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No works in this section match the current filters.")
                    } actions: {
                        Button("Clear Filters") { filters = LibraryFilters() }
                    }
                }
            }
        }
    }

    /// A local work row with the Library's standard swipe actions (save / favorite /
    /// delete). Tapping opens the work via the root `SavedWork` destination.
    private func row(_ work: SavedWork) -> some View {
        SensitiveWorkRow(work: work, expandAll: expandAll)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    WorkLifecycle.setSaved(work, !work.isSaved, in: context)
                } label: {
                    Label(work.isSaved ? "Unsave" : "Save",
                          systemImage: work.isSaved ? "bookmark.slash" : "bookmark")
                }
                .tint(.blue)

                Button {
                    work.isFavorite.toggle()
                    try? context.save()
                } label: {
                    Label(work.isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: work.isFavorite ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    if confirmBeforeDelete { pendingDelete = work } else { WorkLifecycle.delete(work, in: context) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func loadMarkedForLater() async {
        markedForLater = await auth.accountWorks(from: AO3Client.markedForLaterURL)
    }
}
