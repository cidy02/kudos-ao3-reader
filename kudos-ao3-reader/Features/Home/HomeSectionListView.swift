import SwiftUI
import SwiftData

/// The full, vertically scrolling list behind a Home section's header ("See all").
/// Reuses the Library's privacy-aware `SensitiveWorkRow`; rows open works the same
/// way the dashboard cards do (via Home's `SavedWork` navigation destination).
struct HomeSectionListView: View {
    let kind: HomeSectionKind

    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var works: [SavedWork]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var expandAll = false
    /// Filters scoped to this one section, applied live to the works on the page.
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private var items: [SavedWork] { kind.works(from: works, visible: passesPrivacy) }

    /// This section's works after the active filters. With no filter set, the section's
    /// own ordering is kept rather than re-sorted by the filter's default sort.
    private var visibleItems: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: items) : items
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "books.vertical")
            } else {
                List {
                    ForEach(visibleItems) { work in
                        SensitiveWorkRow(work: work, expandAll: expandAll)
                    }
                    .cardRow()
                }
                .cardList()
                .overlay {
                    // Section has works, but the active filters hid them all.
                    if visibleItems.isEmpty {
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
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle(kind.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !items.isEmpty {
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
    }
}
