import SwiftUI

/// The filter button + its "Clear All Filters" long-press menu — the one control
/// that stays directly visible in every work-list toolbar app-wide. Everything else
/// (Privacy, Select, Reorder, Expand/Collapse, Show Summaries, List/Grid, Reading Insights,
/// Rename/Delete…) lives behind `WorkListMoreMenu`.
///
/// `filtersActive` is passed as a plain Bool so the same control serves pages backed by
/// `LibraryFilters` (local works) and by `AO3SearchFilters` (remote summaries).
struct FilterButton: View {
    var filtersActive: Bool
    @Binding var showingFilters: Bool
    var filterHelp: String = "Filter the works on this page"
    var onClearFilters: (() -> Void)?
    /// Count of narrowing filters, drawn as a numeric badge so a zero-results
    /// page still shows *why* the list is empty. 0 hides the number; the filled
    /// glyph still marks an active set.
    var badgeCount: Int = 0

    var body: some View {
        Button { showingFilters = true } label: {
            // "line.3.horizontal.decrease" (off) / ".circle.fill" (on) — the
            // actual SF Symbol pair Mail.app uses for this same filter state (all
            // three of the bare/circle/circle.fill variants resolve fine via
            // NSImage(systemSymbolName:); an earlier version of this comment
            // wrongly claimed none did). The circle only appears once a filter is
            // active, as part of the *badge* glyph itself, not a hand-drawn
            // background — so plain `.tint()` renders it correctly through the
            // toolbar's Liquid Glass pipeline with no custom background/
            // buttonStyle needed.
            Label("Filter", systemImage: filtersActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease")
                .overlay(alignment: .topTrailing) {
                    if badgeCount > 0 {
                        Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Circle().fill(.accentFill))
                            .offset(x: 6, y: -6)
                            .accessibilityHidden(true)
                    }
                }
        }
        // nil inherits the screen's tint, so an active filter takes its colour.
        .tint(filtersActive ? nil : Color.primary)
        .labelStyle(.iconOnly)
        .accessibilityValue(badgeCount > 0 ? "\(badgeCount) active" : "")
        // The default toolbar glyph size left the filled circle visibly smaller
        // than the button's own touch-target circle around it — Messages' filled
        // filter badge fills that outer circle almost completely.
        .imageScale(.large)
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
/// Select / Reorder / `ShowSummariesMenuItem` / `ListGridMenuPicker` / `ExpandAllMenuItem` / page-specific
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

/// Show Summaries — a `WorkListMoreMenu` item on a detailed surface. On by
/// default. Tags stay on the row either way; this only hides the paragraph.
struct ShowSummariesMenuItem: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Show Summaries", isOn: $isOn)
            .accessibilityHint("Shows or hides the summary under each work. Tags stay on the row.")
    }
}

/// List / Grid — a `WorkListMoreMenu` item on a ledger list. A `Picker` inside
/// a `Menu` renders as a checkmarked section, the same idiom the old layout
/// picker used.
struct ListGridMenuPicker: View {
    @Binding var arrangement: WorkListArrangement

    var body: some View {
        Picker("Layout", selection: $arrangement) {
            ForEach(WorkListArrangement.allCases, id: \.self) { arrangement in
                Label(arrangement.title, systemImage: arrangement.systemImage).tag(arrangement)
            }
        }
        .accessibilityLabel("Layout")
    }
}
