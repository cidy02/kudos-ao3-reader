import SwiftUI

/// A category detail page's card layout — "Detailed" is the existing full `WorkRow`/
/// `AO3WorkRow` list; "Compact" lays the same works out as `WorkCoverCard`/
/// `AO3WorkCoverCard` cover cards, two side-by-side, Apple Books-style.
nonisolated enum WorkListDisplayMode: String, CaseIterable {
    case detailed
    case compact
}

/// The filter button + its "Clear All Filters" long-press menu — the one control
/// that stays directly visible in every work-list toolbar app-wide. Everything else
/// (Privacy, Select, Reorder, Expand/Collapse, Detailed/Compact, Reading Insights,
/// Rename/Delete…) lives behind `WorkListMoreMenu`.
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
            // "line.3.horizontal.decrease" — the funnel-shaped filter glyph
            // without a circle around it (there is no plain "funnel" SF
            // Symbol; confirmed via NSImage(systemSymbolName:), the literal
            // name silently fails to resolve and Label/Button falls back to
            // showing the text title instead of a broken icon, which is
            // exactly the bug this replaces). No dedicated ".fill" asset for
            // this glyph either, so the active state comes from
            // .symbolVariant instead of a second name.
            //
            // Custom icon view (not a plain `Label("Filter", systemImage:)`)
            // because the active state needs a real solid badge — Messages'
            // own filter chip: neutral outline glyph normally, a filled
            // accent-colored circle with a white glyph once a filter is on.
            // Neither `.tint()` nor `.foregroundStyle()` alone produces that;
            // both only recolor the glyph, not draw a background behind it.
            Label {
                Text("Filter")
            } icon: {
                Image(systemName: "line.3.horizontal.decrease")
                    .symbolVariant(filtersActive ? .fill : .none)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(filtersActive ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background {
                        if filtersActive {
                            Circle().fill(Color.accentColor)
                        }
                    }
            }
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

/// The app-wide "..." overflow menu for a work-list toolbar. Every control except
/// `FilterButton` lives here — each page supplies whichever of `MatureRevealToggle` /
/// Select / Reorder / `DisplayModeMenuPicker` / `ExpandAllMenuItem` / page-specific
/// items (Reading Insights, Rename, Delete…) actually apply, via `content`.
struct WorkListMoreMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            // Plain dots, not "ellipsis.circle" — the glass button already
            // draws its own circular background, so the circled symbol
            // doubled it up. Matches Apple Books' "..." more button.
            Label("More", systemImage: "ellipsis")
        }
        // Neutral, not the ambient accent (red) — a plain overflow menu, no
        // active/inactive state to signal, so it (and its popover items,
        // which inherit tint from here — .tint() propagates into presented
        // menu content, unlike .foregroundStyle()) should read as ordinary
        // controls, not something already "on."
        .tint(Color.primary)
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
