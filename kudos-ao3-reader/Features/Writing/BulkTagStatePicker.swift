import SwiftUI

/// A three-state list for artboard **1bn**'s bulk editor: each option is left
/// alone, added to every selected work, or removed from every selected work.
///
/// Three states rather than a switch, because that is the board's whole point —
/// "its model is add-and-remove rather than replace … every field left alone
/// stays untouched on all three works". A two-state toggle cannot say "leave
/// this one as it is", which is the state most rows are in.
///
/// Uses the app's existing `FilterSelectionState` cycle and its `includeColor` /
/// `excludeColor` roles, the same vocabulary Search's filter panel uses for the
/// same question, so a reader meets one idiom rather than two.
struct BulkTagStatePicker: View {
    let title: String
    let options: [AO3FormOption]
    @Binding var added: [String]
    @Binding var removed: [String]

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(options) { option in
                    row(option)
                }
            } footer: {
                Text("Tap once to add to every selected work, twice to remove it from "
                    + "every selected work, three times to leave it alone.")
            }
        }
        .appThemedRows()
        .appThemedScroll()
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func row(_ option: AO3FormOption) -> some View {
        let state = state(of: option.value)
        return Button {
            apply(state.next, to: option.value)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol(for: state))
                    .foregroundStyle(colour(for: state))
                Text(option.title)
                    .foregroundStyle(.primary)
                    .strikethrough(state == .excluded, color: theme.appTheme.excludeColor.opacity(0.7))
                Spacer(minLength: 8)
                if let label = stateLabel(state) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(colour(for: state))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(stateLabel(state) ?? "Unchanged")
    }

    /// `.included` is "add", `.excluded` is "remove" — the same two verbs the
    /// board names, wearing the app's existing state names.
    private func state(of value: String) -> FilterSelectionState {
        if added.contains(value) { return .included }
        if removed.contains(value) { return .excluded }
        return .clear
    }

    private func apply(_ state: FilterSelectionState, to value: String) {
        added.removeAll { $0 == value }
        removed.removeAll { $0 == value }
        switch state {
        case .included: added.append(value)
        case .excluded: removed.append(value)
        case .clear: break
        }
    }

    private func symbol(for state: FilterSelectionState) -> String {
        switch state {
        case .included: "plus.circle.fill"
        case .excluded: "minus.circle.fill"
        case .clear: "circle"
        }
    }

    private func colour(for state: FilterSelectionState) -> Color {
        switch state {
        case .included: theme.appTheme.includeColor
        case .excluded: theme.appTheme.excludeColor
        case .clear: .secondary
        }
    }

    private func stateLabel(_ state: FilterSelectionState) -> String? {
        switch state {
        case .included: "Add"
        case .excluded: "Remove"
        case .clear: nil
        }
    }
}

/// 1bn's "Add to collections" row.
///
/// A free-text list rather than a picker, because otwarchive's field here is
/// `work[collections_to_add]` — a comma-separated text input, not a checkbox
/// set. You can add a work to a collection that is not already on the form, so
/// a picker over `currentCollections` (which is the *remove* list) would both
/// invent a constraint AO3 does not impose and quietly hide every collection
/// the reader has not used yet.
struct BulkNameListRow: View {
    let title: String
    let placeholder: String
    @Binding var names: [String]

    var body: some View {
        SubjectFormRow(
            label: title,
            value: names.isEmpty ? "None" : "\(names.count)",
            showsDisclosure: true
        )
        .subjectRowNavigation(accessibilityLabel: title) {
            BulkNameListEditor(title: title, placeholder: placeholder, names: $names)
        }
    }
}

private struct BulkNameListEditor: View {
    let title: String
    let placeholder: String
    @Binding var names: [String]

    @Environment(ThemeManager.self) private var theme
    @State private var entry = ""

    var body: some View {
        List {
            if !names.isEmpty {
                Section("Added") {
                    ForEach(names, id: \.self) { name in
                        Button {
                            names.removeAll { $0 == name }
                        } label: {
                            Label(name, systemImage: "minus.circle")
                        }
                        .accessibilityLabel("Remove \(name)")
                    }
                }
            }
            Section {
                TextField(placeholder, text: $entry)
                    // iOS-only modifier; macOS has no software keyboard to tell.
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(trimmed.isEmpty)
            } footer: {
                Text("Type the collection name exactly as it appears on AO3. "
                    + "A name AO3 does not recognize is reported when you save.")
            }
        }
        .cardList()
        .navigationTitle(title)
        .subjectScreenWash(palette: theme.scopePalette)
    }

    private var trimmed: String {
        entry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let name = trimmed
        guard !name.isEmpty, !names.contains(name) else { entry = ""; return }
        names.append(name)
        entry = ""
    }
}
