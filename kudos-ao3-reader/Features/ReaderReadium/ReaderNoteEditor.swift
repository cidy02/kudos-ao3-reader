#if os(iOS)
import SwiftUI

/// Writes or edits the note attached to a highlight, and picks its colour.
///
/// The highlighted passage is shown but not editable — it's a snapshot of what
/// the book said when the mark was made, not something the reader authored.
struct ReaderNoteEditor: View {
    @Bindable var annotation: ReadingAnnotation
    let onCommit: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    /// The raw colour on open, including a well colour's `#RRGGBB`. Cancel
    /// writes this back; going through `color` would turn a custom colour yellow.
    @State private var colorRawOnOpen: String?
    /// Only Cancel throws a typed note away. A swipe down dismissed the sheet and
    /// lost it; it is kept now, as the colour already was.
    @State private var finished = false
    @State private var colorWellSession = CustomColorWellSession()
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if !annotation.selectedText.isEmpty {
                        Section("Highlighted") {
                            Text(annotation.selectedText)
                                .font(.callout)
                                .padding(.leading, 10)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(annotation.displayTint)
                                        .frame(width: 3)
                                }
                        }
                    }

                    Section("Note") {
                        TextEditor(text: $draft)
                            .frame(minHeight: 120)
                            .focused($isEditorFocused)
                    }

                    Section("Colour") {
                        ReadingAnnotationColorPicker(selectedRaw: annotation.colorRaw) { raw in
                            annotation.colorRaw = ReadingAnnotationColorStorage.normalizedRaw(raw)
                            annotation.markModified()
                            ReadingAnnotationColor.lastUsedRaw = annotation.colorRaw
                            onCommit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    Section {
                        Button(role: .destructive) {
                            finished = true
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete Highlight", systemImage: "trash")
                        }
                    }
                }
                .appThemedRows()
            }
            .appThemedScroll()
            .navigationTitle(annotation.hasNote ? "Edit Note" : "Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        finished = true
                        // Drop an unfinished drag so the well's disappear flush
                        // cannot write back a colour Cancel just threw away.
                        colorWellSession.discard()
                        // A swatch writes straight to the highlight so the page shows
                        // it at once; Cancel has to take that back too (audit A12-6).
                        if let colorRawOnOpen, annotation.colorRaw != colorRawOnOpen {
                            annotation.colorRaw = colorRawOnOpen
                            onCommit()
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        finished = true
                        keepDraft()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
        .environment(\.customColorWellSession, colorWellSession)
        .onAppear {
            draft = annotation.note
            colorRawOnOpen = annotation.colorRaw
            isEditorFocused = true
        }
        .onDisappear {
            if !finished { keepDraft() }
        }
    }

    private func keepDraft() {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != annotation.note else { return }
        annotation.note = typed
        annotation.markModified()
        onCommit()
    }
}
#endif
