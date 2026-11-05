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
    @Environment(ThemeManager.self) private var themeManager
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
                                .padding(.leading, 14)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(annotation.displayTint)
                                        .frame(width: 4)
                                        .accessibilityHidden(true)
                                }
                                .listRowBackground(highlightedCardBackground)
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
                    Button {
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
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        finished = true
                        keepDraft()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .sheetConfirmStyle()
                    .accessibilityLabel("Done")
                }
            }
        }
        .environment(\.customColorWellSession, colorWellSession)
        .presentationBackground {
            themeManager.appTheme.cardBackdrop
                .ignoresSafeArea()
        }
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

    @ViewBuilder
    private var highlightedCardBackground: some View {
        let theme = themeManager.appTheme
        let palette = SubjectPalette(color: annotation.displayTint, theme: theme)
        if Self.canCarryReadableText(tint: annotation.displayTint, on: theme) {
            ZStack {
                theme.cardSurface
                palette.rowWash
            }
        } else {
            theme.cardSurface
        }
    }

    /// Verifies that `tint` composited as a wash over `theme.cardSurface` retains
    /// WCAG minimum contrast (4.5:1) for body text across all four themes.
    /// If an edge-case colour cannot guarantee readable text, callers fall back
    /// to the plain unwashed card.
    static func canCarryReadableText(tint: Color, on theme: ReaderTheme) -> Bool {
        let alpha = theme.isDarkFamily ? 0.30 : 0.18
        let baseSurfaceColor: Color = {
            switch theme {
            case .light: Color(red: 1.0, green: 1.0, blue: 1.0)
            case .sepia: Color(red: 0.984, green: 0.941, blue: 0.851)
            case .dark: Color(red: 0.133, green: 0.133, blue: 0.157)
            case .oled: Color(red: 0.110, green: 0.110, blue: 0.118)
            }
        }()
        let platformSurface = UIColor(baseSurfaceColor)
        let platformTint = UIColor(tint)
        var surfaceRed: CGFloat = 0, surfaceGreen: CGFloat = 0, surfaceBlue: CGFloat = 0, surfaceAlpha: CGFloat = 0
        var tintRed: CGFloat = 0, tintGreen: CGFloat = 0, tintBlue: CGFloat = 0, tintAlpha: CGFloat = 0
        guard platformSurface.getRed(&surfaceRed, green: &surfaceGreen, blue: &surfaceBlue, alpha: &surfaceAlpha),
              platformTint.getRed(&tintRed, green: &tintGreen, blue: &tintBlue, alpha: &tintAlpha) else {
            return true
        }
        let blendedRed = surfaceRed * (1 - alpha) + tintRed * alpha
        let blendedGreen = surfaceGreen * (1 - alpha) + tintGreen * alpha
        let blendedBlue = surfaceBlue * (1 - alpha) + tintBlue * alpha
        let blended = Color(red: Double(blendedRed), green: Double(blendedGreen), blue: Double(blendedBlue))
        let textColor: Color = theme.isDarkFamily ? .white : .black
        return textColor.contrastRatio(on: blended) >= 4.5
    }
}
#endif
