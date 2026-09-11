import SwiftUI

/// Artboard **1bm** — the collections list's sort-and-filter sheet.
///
/// Built from the form family rather than a native `Form`: the spec draws
/// `SubjectFormRow` groups under `SubjectFieldLabel` headings, and this panel is
/// small enough (four groups, nine controls) that hand-building it carries none of
/// the risk that made the big Library filter panel worth deferring.
///
/// **Every control here is backed by a field AO3 actually returns.** Spec 1bm also
/// draws a "My role" group — Maintainer / Member / Invited — and that is *not* here,
/// because `AO3Collection` carries no role and the collections page does not give
/// one. Finding out would mean a participants request per collection, which is a
/// page load per row for a filter. Recorded rather than faked: a filter that
/// silently matched everything would be worse than its absence.
struct AO3CollectionsFilterPanel: View {
    @Binding var filters: AO3CollectionsFilter
    var onApply: () -> Void
    var onReset: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sortGroup
                showOnlyGroup
                unavailableNote
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.vertical, 20)
        }
        .safeAreaInset(edge: .bottom) { applyBar }
        .appThemedScroll()
    }

    // MARK: Sort

    private var sortGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubjectFieldLabel(text: "Sort by", style: .formGroup)
            VStack(spacing: 0) {
                SubjectFormRow(
                    label: "Order by",
                    arrangement: .control,
                    trailing: {
                        Picker("Order by", selection: $filters.sort) {
                            ForEach(AO3CollectionsFilter.Sort.allCases, id: \.self) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                )
                if filters.sort != .asReturned {
                    SubjectRowSeparator()
                    SubjectFormRow(
                        label: "Direction",
                        arrangement: .control,
                        trailing: {
                            SubjectSegmentedControl(
                                options: AO3CollectionsFilter.Order.allCases,
                                title: { $0.title(for: filters.sort) },
                                selection: $filters.order
                            )
                        }
                    )
                }
            }
            .subjectPanel()

            if filters.sort == .recentlyUpdated {
                note("Recently updated is computed here from the date AO3 prints on each "
                    + "collection. A collection whose date does not parse keeps AO3's own "
                    + "position rather than being sorted somewhere wrong.")
            }
        }
    }

    // MARK: Show only

    private var showOnlyGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubjectFieldLabel(text: "Show only", style: .formGroup)
            VStack(spacing: 0) {
                toggleRow("Open to new works", isOn: $filters.showsOpenOnly)
                SubjectRowSeparator()
                toggleRow("Has works", isOn: $filters.showsWithWorksOnly)
                SubjectRowSeparator()
                toggleRow("Moderated", isOn: $filters.showsModeratedOnly)
                SubjectRowSeparator()
                toggleRow("Unrevealed", isOn: $filters.showsUnrevealedOnly)
            }
            .subjectPanel()
            note("These four are independent on AO3, so they narrow together rather than "
                + "replacing one another.")
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        SubjectFormRow(
            label: label,
            arrangement: .control,
            trailing: {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        )
    }

    /// States what the panel cannot offer and why, where a reader looking for it
    /// will actually be.
    private var unavailableNote: some View {
        note("AO3's collections page does not say what your role in each collection is, "
            + "so there is no Maintainer / Member / Invited filter here. Finding out would "
            + "mean loading each collection's participants — a page request per row.")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var applyBar: some View {
        HStack(spacing: 12) {
            Button("Reset", action: onReset)
                .buttonStyle(.bordered)
                .disabled(!filters.hasActiveFilters)
            Button("Done", action: onApply)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, SubjectMetrics.gutter)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
