import SwiftUI

/// A category detail page's card layout — "Detailed" is the existing full `WorkRow`/
/// `AO3WorkRow` list; "Compact" lays the same works out as `WorkCoverCard`/
/// `AO3WorkCoverCard` cover cards, two side-by-side, Apple Books-style.
nonisolated enum WorkListDisplayMode: String, CaseIterable {
    case detailed
    case compact
}

/// The filter button + its "Clear All Filters" long-press menu — the one control,
/// alongside the privacy toggle where present, that stays directly visible in every
/// work-list toolbar app-wide. Everything else (Select, Reorder, Expand/Collapse,
/// Detailed/Compact, Reading Insights, Rename/Delete…) lives behind `WorkListMoreMenu`.
///
/// `filtersActive` is passed as a plain Bool so the same control serves pages backed by
/// `LibraryFilters` (local works) and by `AO3SearchFilters` (remote summaries).
struct FilterButton: View {
    var filtersActive: Bool
    @Binding var showingFilters: Bool
    var filterHelp: String = "Filter the works on this page"
    var onClearFilters: (() -> Void)?

    var body: some View {
        Button { showingFilters = true } label: {
            Label("Filter", systemImage: filtersActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .labelStyle(.iconOnly)
        .help(filterHelp)
        .contextMenu {
            if filtersActive, let onClearFilters {
                Button(role: .destructive, action: onClearFilters) {
                    Label("Clear All Filters", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }
}

/// The app-wide "..." overflow menu for a work-list toolbar. Every control except the
/// privacy toggle and `FilterButton` lives here — each page supplies whichever of
/// Select / Reorder / `DisplayModeMenuPicker` / `ExpandAllMenuItem` / page-specific
/// items (Reading Insights, Rename, Delete…) actually apply, via `content`.
struct WorkListMoreMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }
}

/// Expand/collapse-all — a `WorkListMoreMenu` item present on nearly every work-list
/// page.
struct ExpandAllMenuItem: View {
    @Binding var expandAll: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expandAll.toggle() }
        } label: {
            Label(expandAll ? "Collapse All Cards" : "Expand All Cards",
                  systemImage: expandAll ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
        }
    }
}

/// Detailed/Compact — a `WorkListMoreMenu` item. A `Picker` placed directly inside a
/// `Menu`'s content renders as a checkmarked submenu section, the standard system
/// idiom for "view options" (replaces the old segmented `DisplayModeToggle`, which
/// needed its own toolbar slot).
struct DisplayModeMenuPicker: View {
    @Binding var mode: WorkListDisplayMode

    var body: some View {
        Picker("Layout", selection: $mode) {
            Label("Detailed", systemImage: "list.bullet").tag(WorkListDisplayMode.detailed)
            Label("Compact", systemImage: "square.grid.2x2").tag(WorkListDisplayMode.compact)
        }
    }
}
