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
    var onFinish: (AO3CollectionsFilter) -> Void

    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .caption) private var noteSize: CGFloat = 12
    @State private var editor: AO3CollectionsFilterDraft

    init(
        initial: AO3CollectionsFilter,
        onFinish: @escaping (AO3CollectionsFilter) -> Void
    ) {
        self.onFinish = onFinish
        self._editor = State(initialValue: AO3CollectionsFilterDraft(initial: initial))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sortGroup
                    showOnlyGroup
                    unavailableNote
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.vertical, 20)
            }
            .safeAreaInset(edge: .bottom) { resetBar }
            .appThemedScroll()
            .navigationTitle("Sort and filter")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: theme.scopePalette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onFinish(editor.resolved(.cancel))
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onFinish(editor.resolved(.apply))
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Apply")
                        .disabled(editor.draft == editor.initial)
                    }
                }
        }
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
                        Picker("Order by", selection: $editor.draft.sort) {
                            ForEach(AO3CollectionsFilter.Sort.allCases, id: \.self) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                )
                if editor.draft.sort != .asReturned {
                    SubjectRowSeparator()
                    SubjectFormRow(
                        label: "Direction",
                        arrangement: .control,
                        trailing: {
                            SubjectSegmentedControl(
                                options: AO3CollectionsFilter.Order.allCases,
                                title: { $0.title(for: editor.draft.sort) },
                                selection: $editor.draft.order
                            )
                        }
                    )
                }
            }
            .subjectPanel()

            if editor.draft.sort == .recentlyUpdated {
                note("Recently updated uses the date shown on each AO3 collection. If a date "
                    + "can't be read, that collection stays in AO3's order.")
            }
        }
    }

    // MARK: Show only

    private var showOnlyGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubjectFieldLabel(text: "Show only", style: .formGroup)
            VStack(spacing: 0) {
                toggleRow("Open to new works", isOn: $editor.draft.showsOpenOnly)
                SubjectRowSeparator()
                toggleRow("Has works", isOn: $editor.draft.showsWithWorksOnly)
                SubjectRowSeparator()
                toggleRow("Moderated", isOn: $editor.draft.showsModeratedOnly)
                SubjectRowSeparator()
                toggleRow("Unrevealed", isOn: $editor.draft.showsUnrevealedOnly)
            }
            .subjectPanel()
            note("You can turn on more than one of these. Each choice narrows the results further.")
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
        note("AO3 doesn't show your role in its collections list, so you can't filter by "
            + "Maintainer, Member or Invited here.")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: noteSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resetBar: some View {
        Button("Reset") { editor.reset() }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(editor.draft == AO3CollectionsFilter())
        .padding(.horizontal, SubjectMetrics.gutter)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
