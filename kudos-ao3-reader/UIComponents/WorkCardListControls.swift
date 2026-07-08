import SwiftUI

/// A category detail page's card layout — "Detailed" is the existing full `WorkRow`/
/// `AO3WorkRow` list; "Compact" lays the same works out as `WorkCoverCard`/
/// `AO3WorkCoverCard` cover cards, two side-by-side, Apple Books-style.
nonisolated enum WorkListDisplayMode: String, CaseIterable {
    case detailed
    case compact
}

/// A tight segmented toggle between `WorkListDisplayMode.detailed`/`.compact`, meant
/// to sit in the same toolbar cluster as `WorkCardListControls`.
struct DisplayModeToggle: View {
    @Binding var mode: WorkListDisplayMode

    var body: some View {
        Picker("Layout", selection: $mode) {
            Image(systemName: "list.bullet").tag(WorkListDisplayMode.detailed)
            Image(systemName: "square.grid.2x2").tag(WorkListDisplayMode.compact)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// The shared toolbar cluster for any page that lists full work cards: an
/// expand/collapse-all toggle and a filter button, grouped tightly so they read as a
/// unit (separate `ToolbarItem`s get the system's wider spacing). The expand toggle
/// drives each card's `expandAll`; the filter button opens the page's own filter
/// inspector — contextual to that page, never an app-wide or website-wide filter.
///
/// `filtersActive` is passed as a plain Bool so the same control serves pages backed by
/// `LibraryFilters` (local works) and by `AO3SearchFilters` (remote summaries).
struct WorkCardListControls: View {
    @Binding var expandAll: Bool
    var filtersActive: Bool
    @Binding var showingFilters: Bool
    var filterHelp: String = "Filter the works on this page"
    var onClearFilters: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expandAll.toggle() }
            } label: {
                Label(expandAll ? "Collapse all cards" : "Expand all cards",
                      systemImage: expandAll
                          ? "rectangle.compress.vertical"
                          : "rectangle.expand.vertical")
            }
            Button { showingFilters = true } label: {
                Label("Filter", systemImage: filtersActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }
            .help(filterHelp)
            .contextMenu {
                if filtersActive, let onClearFilters {
                    Button(role: .destructive, action: onClearFilters) {
                        Label("Clear All Filters", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .labelStyle(.iconOnly)
    }
}
