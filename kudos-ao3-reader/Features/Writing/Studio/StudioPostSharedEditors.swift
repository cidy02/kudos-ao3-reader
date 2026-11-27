import SwiftUI

/// Focused work-title editor pushed from `StudioPostNewWorkSheet` and `StudioWorkDetailsView`.
struct StudioWorkTitleEditorView: View {
    @Binding var title: String

    @Environment(ThemeManager.self) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        List {
            Section {
                TextField(
                    "Work title",
                    text: $title,
                    prompt: theme.appTheme.sepiaPrompt("Work title"),
                    axis: .vertical
                )
                .font(.body)
                .focused($isFocused)
                .lineLimit(1 ... 4)
                .accessibilityLabel("Work title")
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .subjectPanel()
                .pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
            }
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: "Title", palette: theme.scopePalette)
        .hidesFloatingTabBarInEditor()
        .onAppear { isFocused = true }
    }
}

/// Focused work beginning/end notes screen reusing `WritingTextEditorRow`.
struct StudioWorkNotesEditorView: View {
    @Binding var notes: String
    @Binding var endnotes: String
    let target: String

    @Environment(ThemeManager.self) private var theme

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                WritingTextEditorRow(
                    title: "Beginning Notes",
                    text: $notes,
                    target: target,
                    field: "notes",
                    previewsText: true
                )
                .panelSegment(0, of: 2, gutter: gutter)

                WritingTextEditorRow(
                    title: "End Notes",
                    text: $endnotes,
                    target: target,
                    field: "endnotes",
                    previewsText: true
                )
                .panelSegment(1, of: 2, gutter: gutter)
            }
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: "Notes", palette: theme.scopePalette)
        .hidesFloatingTabBarInEditor()
    }
}
