import SwiftUI

/// One smart-queue rule. Pushed from the New Queue sheet. Controls use the app
/// tint; the queue's colour is not a control colour.
struct SmartQueueRuleEditor: View {
    @Binding var rule: SmartQueueDocument.Rule
    let fandoms: [String]
    var aliases: TagAliasResolver = .empty
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme
    @State private var wordsText = ""

    var body: some View {
        List {
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
                SubjectFormRow(label: "Delete Rule", isDestructive: true, action: {
                    onDelete()
                    dismiss()
                }) {
                    EmptyView()
                }
                .accessibilityLabel("Delete Rule")
                .subjectPanel()
                .pageBodyRow(top: 12, gutter: SubjectMetrics.gutter)
            }
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
                wordsText = rule.words.map(String.init) ?? ""
            }
        }
    }

    private var lengthControls: some View {
        Section {
            VStack(spacing: 0) {
                SubjectFormRow(label: "Comparison", arrangement: .control) {
                    SubjectSegmentedControl(
                        options: SmartQueueDocument.Rule.LengthComparison.allCases,
                        title: \.title,
                        selection: lengthComparison
                    )
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Comparison")
                SubjectRowSeparator()
                SubjectFormRow(label: "Words", arrangement: .control) {
                    TextField("Words", text: $wordsText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                        .accessibilityLabel("Words")
                        .onChange(of: wordsText) { _, newValue in
                            let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(18))
                            if digits != newValue { wordsText = digits }
                            rule.words = Int(digits)
                        }
                }
            }
            .subjectPanel()
            .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
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
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .accessibilityLabel("Fandom")
            }
            .subjectPanel()
            .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            if !fandoms.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(fandoms.enumerated()), id: \.element) { index, name in
                        if index > 0 { SubjectRowSeparator() }
                        SubjectFormRow(label: name, action: { rule.fandom = name }) {
                            if fandomMatches(name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(fandomMatches(name) ? .isSelected : [])
                    }
                }
                .subjectPanel()
                .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
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
        let wanted = aliases.resolveIgnoringCase(rule.fandom ?? "", kind: .fandom)
        guard !wanted.isEmpty else { return false }
        return aliases.resolveIgnoringCase(name, kind: .fandom).caseInsensitiveCompare(wanted) == .orderedSame
    }

    private func optionList<Option: Hashable>(
        _ options: [Option],
        title: @escaping (Option) -> String,
        pick: @escaping (Option) -> Void,
        isSelected: @escaping (Option) -> Bool
    ) -> some View {
        Section {
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    if index > 0 { SubjectRowSeparator() }
                    SubjectFormRow(label: title(option), action: { pick(option) }) {
                        if isSelected(option) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(title(option))
                    .accessibilityAddTraits(isSelected(option) ? .isSelected : [])
                }
            }
            .subjectPanel()
            .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
        }
    }
}
