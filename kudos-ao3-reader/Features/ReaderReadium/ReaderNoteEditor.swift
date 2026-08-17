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
                                        .fill(annotation.color.tint)
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
                        ReadingAnnotationColorPicker(selected: annotation.color) { option in
                            annotation.color = option
                            annotation.markModified()
                            ReadingAnnotationColor.lastUsed = option
                            onCommit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    Section {
                        Button(role: .destructive) {
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        annotation.note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        annotation.markModified()
                        onCommit()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
        .onAppear {
            draft = annotation.note
            isEditorFocused = true
        }
    }
}
#endif
