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

private struct WritingTagsEditor: View {
    @Environment(ThemeManager.self) private var theme
    let title: String
    @Binding var values: [String]
    let options: [AO3FormOption]
    let kind: AO3TagKind?
    @State private var term = ""
    @State private var suggestions: [AO3EditorTag] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let kind {
                Section("Selected") {
                    ForEach(values, id: \.self) { value in
                        Button { values.removeAll { $0 == value } } label: {
                            Label(value, systemImage: "minus.circle")
                        }
                        .accessibilityLabel("Remove \(value)")
                    }
                }
                Section("Add a tag") {
                    TextField("Tag name", text: $term).onSubmit { add(term) }
                    Button("Add \(term)") { add(term) }.disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                    ForEach(suggestions, id: \.name) { tag in
                        Button(tag.name) { add(tag.name) }
                    }
                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.secondary) }
                }
                .task(id: term) {
                    suggestions = []
                    errorMessage = nil
                    do {
                        let loaded = try await AO3TagAutocomplete.suggest(kind: kind, term: term)
                        guard !Task.isCancelled else { return }
                        suggestions = loaded.filter { !values.contains($0.name) }
                    } catch {
                        guard !Task.isCancelled else { return }
                        errorMessage = "Suggestions unavailable. You can still add a tag by name."
                    }
                }
            } else {
                ForEach(options) { option in
                    Toggle(option.title, isOn: Binding(
                        get: { values.contains(option.value) },
                        set: { selected in
                            if selected { if !values.contains(option.value) { values.append(option.value) } } else { values.removeAll { $0 == option.value } }
                        }
                    ))
                }
            }
        }
        .cardList()
        .navigationTitle(title)
        .subjectScreenWash(palette: theme.scopePalette)
    }

    private func add(_ name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !values.contains(value) { values.append(value) }
        term = ""
    }
}
