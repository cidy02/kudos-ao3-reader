import SwiftUI

/// A single-choice row: the spec's `Menu { Picker }` in a `.control` row.
///
/// It was a bare `Picker`, and a `Picker` inside a `List` row claims a tap
/// ANYWHERE in that row. The editors put several rows in one row-sized card, so
/// on the new-work form a tap on "Archive warnings" or "Fandoms" — both
/// required — opened the Rating menu instead (measured on the simulator; plain
/// button styles on the other rows' links alone did not stop it). A `Menu`
/// with a plain button style answers only its own label.
struct WritingChoiceRow: View {
    let title: String
    @Binding var value: String
    let options: [AO3FormOption]

    private var currentTitle: String {
        options.first { $0.value == value }?.title ?? (value.isEmpty ? "Select…" : value)
    }

    var body: some View {
        SubjectFormRow(label: title, arrangement: .control) {
            Menu {
                Picker(title, selection: $value) {
                    if !options.contains(where: { $0.value == value }) {
                        Text(value.isEmpty ? "Select…" : value).tag(value)
                    }
                    ForEach(options) { Text($0.title).tag($0.value) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Text(currentTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.tint)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(currentTitle)
        }
    }
}

struct WritingTagsRow: View {
    let title: String
    @Binding var values: [String]
    var options: [AO3FormOption] = []
    var kind: AO3TagKind?
    var isRequired = false
    /// 1bp draws the tags on the row, with Add as the way into the picker.
    /// The disclosure row stays the default: Work Edit and bulk edit are one
    /// field per row, and a chip wrap there would be a second design.
    var showsInlineChips = false
    var onAdd: (() -> Void)?

    @ScaledMetric(relativeTo: .subheadline) private var rowTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var countSize: CGFloat = 13

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        if showsInlineChips {
            inlineChips
        } else {
            SubjectFormRow(
                label: title,
                value: values.isEmpty ? "None" : "\(values.count)",
                showsDisclosure: true,
                isRequired: isRequired
            )
            .subjectRowNavigation(accessibilityLabel: isRequired ? "\(title), required" : title) {
                WritingTagsEditor(title: title, values: $values, options: options, kind: kind)
            }
        }
    }

    /// The count stays, so a long wrap does not hide how many tags there are.
    /// Add is a button rather than a link: a `NavigationLink` in this row would
    /// fire for every chip tap.
    private var inlineChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                titleLabel
                    .font(.system(size: rowTitleSize))
                    .accessibilityLabel(isRequired ? "\(title), required" : title)
                Spacer(minLength: 8)
                Text(values.isEmpty ? "None" : "\(values.count)")
                    .font(.system(size: countSize))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button {
                        values.removeAll { $0 == value }
                    } label: {
                        SubjectChip(
                            text: value,
                            style: .neutral,
                            trailingImage: "xmark",
                            palette: theme.scopePalette
                        )
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .accessibilityLabel("Remove \(value)")
                }
                Button {
                    onAdd?()
                } label: {
                    SubjectChip(
                        text: "Add",
                        style: .dashed,
                        systemImage: "plus",
                        palette: theme.scopePalette
                    )
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel("Add \(title)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var titleLabel: Text {
        if isRequired {
            Text("\(title) \(Text("∗").foregroundStyle(.tint))")
        } else {
            Text(title)
        }
    }
}
