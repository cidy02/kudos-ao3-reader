import SwiftUI

/// One smart-queue rule. Pushed from the New Queue sheet. Controls use the app
/// tint; the queue's colour is not a control colour.
struct SmartQueueRuleEditor: View {
    @Binding var rule: SmartQueueDocument.Rule
    let fandoms: [String]
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @State private var wordsText = ""

    var body: some View {
        List {
            Group {
            switch rule.kind {
            case .length:
                lengthControls
            case .readingStatus:
                optionList(SmartQueueReadingStatus.allCases, title: \.title) { picked in
                    rule.readingStatus = picked
                } isSelected: { picked in
                    rule.readingStatus == picked
                }
            case .progress:
                optionList(SmartQueueDocument.Rule.Progress.allCases, title: \.title) { picked in
                    rule.progress = picked
                } isSelected: { picked in
                    rule.progress == picked
                }
            case .completion:
                optionList(SmartQueueDocument.Rule.Completion.allCases, title: \.title) { picked in
                    rule.completion = picked
                } isSelected: { picked in
                    rule.completion == picked
                }
            case .fandom:
                fandomControls
            }
            Section {
                Button("Delete Rule", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .accessibilityLabel("Delete Rule")
            }
            }
            .appThemedRows()
        }
        .cardList()
        .appThemedScroll()
        .environment(\.defaultMinListRowHeight, 0)
        .navigationTitle(rule.kind.rowLabel)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .screenTint(theme.scopePalette)
        .onAppear {
            if rule.kind == .length {
                wordsText = String(rule.words ?? 20_000)
            }
        }
    }

    private var lengthControls: some View {
        Section {
            SubjectFormRow(label: "Comparison", arrangement: .control) {
                SubjectSegmentedControl(
                    options: SmartQueueDocument.Rule.LengthComparison.allCases,
                    title: \.title,
                    selection: lengthComparison
                )
            }
            .accessibilityLabel("Comparison")
            SubjectFormRow(label: "Words", arrangement: .control) {
                TextField("Words", text: $wordsText)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Words")
                    .onChange(of: wordsText) { _, newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue { wordsText = digits }
                        rule.words = Int(digits)
                    }
            }
        }
    }

    private var lengthComparison: Binding<SmartQueueDocument.Rule.LengthComparison> {
        Binding(
            get: { rule.lengthComparison ?? .under },
            set: { rule.lengthComparison = $0 }
        )
    }

    private var fandomControls: some View {
        Section {
            SubjectFormRow(label: "Fandom", arrangement: .control) {
                TextField("Fandom", text: fandomText)
                    .accessibilityLabel("Fandom")
            }
            if !fandoms.isEmpty {
                ForEach(fandoms, id: \.self) { name in
                    Button {
                        rule.fandom = name
                    } label: {
                        HStack {
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if fandomMatches(name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(fandomMatches(name) ? .isSelected : [])
                }
            }
        }
    }

    private var fandomText: Binding<String> {
        Binding(
            get: { rule.fandom ?? "" },
            set: { rule.fandom = $0 }
        )
    }

    private func fandomMatches(_ name: String) -> Bool {
        (rule.fandom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(name) == .orderedSame
    }

    private func optionList<Option: Hashable>(
        _ options: [Option],
        title: @escaping (Option) -> String,
        pick: @escaping (Option) -> Void,
        isSelected: @escaping (Option) -> Bool
    ) -> some View {
        Section {
            ForEach(options, id: \.self) { option in
                Button {
                    pick(option)
                } label: {
                    HStack {
                        Text(title(option))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isSelected(option) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(isSelected(option) ? .isSelected : [])
            }
        }
    }
}
