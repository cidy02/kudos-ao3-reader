import SwiftUI

struct WritingChoiceRow: View {
    let title: String
    @Binding var value: String
    let options: [AO3FormOption]

    var body: some View {
        SubjectFormRow(label: title, arrangement: .control) {
            Picker(title, selection: $value) {
                if !options.contains(where: { $0.value == value }) { Text(value.isEmpty ? "Select…" : value).tag(value) }
                ForEach(options) { Text($0.title).tag($0.value) }
            }.labelsHidden()
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
