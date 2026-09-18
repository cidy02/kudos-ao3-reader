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

    var body: some View {
        SubjectFormRow(label: title, value: values.isEmpty ? "None" : "\(values.count)", showsDisclosure: true)
            .subjectRowNavigation(accessibilityLabel: title) {
                WritingTagsEditor(title: title, values: $values, options: options, kind: kind)
            }
    }
}
