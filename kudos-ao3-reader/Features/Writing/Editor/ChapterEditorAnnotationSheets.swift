import SwiftUI

// MARK: - Shared visual badge styling (`Editor-Annotations.dc.html`)

/// Shared badge colors for Note, TK, and Resolved tags across Light, Sepia, Dark, and OLED.
struct ChapterEditorAnnotationBadge: View {
    let kind: ChapterEditorAnnotationGroupKind

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }

    var body: some View {
        Text(kind.badgeTitle)
            .font(.caption.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
            .fixedSize()
    }

    private var foregroundColor: Color {
        switch kind {
        case .note, .tk:
            appTheme.isDarkFamily ? Color.subjectAmber : AO3TagPalette.teenTextOnLight
        case .resolved:
            appTheme.statusSuccessColor
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .note:
            if appTheme.isDarkFamily {
                return Color.subjectAmber.opacity(0.22)
            }
            return appTheme.favoriteColor.opacity(0.20)
        case .tk:
            return Color.subjectAmber.opacity(appTheme.isDarkFamily ? 0.28 : 0.22)
        case .resolved:
            return appTheme.statusSuccessColor.opacity(appTheme.isDarkFamily ? 0.22 : 0.14)
        }
    }
}

// MARK: - Story-note name chips for WritingKeysBar (`Editor-Names.dc.html`)

/// Leading-slot name chips shown on `WritingKeysBar` while typing a story-note prefix.
struct WritingNameSuggestionChips: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var accentInk: Color { themeManager?.accentInk ?? effectiveTint }

    var body: some View {
        if !suggestions.isEmpty {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { name in
                    chipButton(name)
                }
            }
        }
    }

    private func chipButton(_ name: String) -> some View {
        Button {
            onSelect(name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentInk)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.system(.callout, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 44 : 36)
            .background(appTheme.cardSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
            .shadow(
                color: appTheme.isDarkFamily ? .clear : Color.black.opacity(0.10),
                radius: 2,
                y: 1
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Insert \(name), from story notes")
    }
}

// MARK: - New Note sheet (`Editor-Annotations.dc.html`)

/// Small native sheet opened after selecting text and choosing Note.
struct ChapterEditorAddNoteSheet: View {
    let quotePreview: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?

    @State private var noteText = ""

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var trimmedText: String { noteText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if !quotePreview.isEmpty {
                    Section("Selected Text") {
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.subjectAmber)
                                .frame(width: 3)
                                .accessibilityHidden(true)
                            Text("“\(quotePreview)”")
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(appTheme.appElevatedBackground)
                }

                Section {
                    TextField(
                        "Write a note to yourself…",
                        text: $noteText,
                        prompt: appTheme.sepiaPrompt("Write a note to yourself…"),
                        axis: .vertical
                    )
                    .lineLimit(3 ... 8)
                    .accessibilityLabel("Note text")
                } header: {
                    Text("Your Note")
                } footer: {
                    Text("Notes stay on this \(ThisDevice.name) and never go to AO3.")
                }
                .listRowBackground(appTheme.appElevatedBackground)
            }
            .scrollContentBackground(appTheme.appBaseBackground == nil ? .automatic : .hidden)
            .background((appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle("Add Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let text = trimmedText
                        guard !text.isEmpty else { return }
                        onSave(text)
                        dismiss()
                    }
                    .disabled(trimmedText.isEmpty)
                    .accessibilityLabel("Save note")
                }
            }
        }
    }
}

// MARK: - Annotation detail & edit sheet (`Editor-Annotations.dc.html`)

/// Sheet opened when tapping a highlight in Rich Text or a row in the `In Chapter` list.
/// Supports resolving/reopening, editing the note text, and deleting the annotation.
struct ChapterEditorAnnotationDetailSheet: View {
    @State private var annotation: WritingAnnotation
    let paragraphNumber: Int?
    let onToggleResolved: (WritingAnnotation, Bool) async -> WritingAnnotation?
    let onSaveText: (WritingAnnotation, String) async -> WritingAnnotation?
    let onDelete: (WritingAnnotation) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isEditing = false
    @State private var draftText: String
    @State private var isWorking = false

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var isResolved: Bool { annotation.resolvedAt != nil }

    private var statusDotColor: Color {
        if isResolved { return appTheme.statusSuccessColor }
        return appTheme.isDarkFamily ? Color.subjectAmber : appTheme.favoriteColor
    }

    private var quotePreview: String {
        ChapterEditorAnnotationAnchoring.plainQuotePreview(from: annotation.quote)
    }

    private var trimmedDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveEdit: Bool {
        annotation.kind == .tk || !trimmedDraft.isEmpty
    }

    init(
        annotation: WritingAnnotation,
        paragraphNumber: Int?,
        onToggleResolved: @escaping (WritingAnnotation, Bool) async -> WritingAnnotation?,
        onSaveText: @escaping (WritingAnnotation, String) async -> WritingAnnotation?,
        onDelete: @escaping (WritingAnnotation) async -> Void
    ) {
        _annotation = State(initialValue: annotation)
        self.paragraphNumber = paragraphNumber
        self.onToggleResolved = onToggleResolved
        self.onSaveText = onSaveText
        self.onDelete = onDelete
        _draftText = State(initialValue: annotation.text)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerMetadata
                    quoteBlock
                    noteBodySection
                    if !isEditing {
                        actionButtons
                    }
                    Text("Notes and TK markers stay on this \(ThisDevice.name) and never go to AO3.")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(appTheme.cardBackdrop.ignoresSafeArea())
            .navigationTitle(annotation.kind == .tk ? "TK Marker" : "Your Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Done")
                }
            }
        }
    }

    private var headerMetadata: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(metadataLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metadataLabel: String {
        let date = annotation.resolvedAt ?? annotation.createdAt
        return ChapterEditorAnnotationCopy.detailHeaderLabel(
            kind: annotation.kind,
            isResolved: isResolved,
            dateText: ChapterEditorAnnotationListBuilder.shortDateString(date),
            paragraphNumber: paragraphNumber
        )
    }

    @ViewBuilder
    private var quoteBlock: some View {
        if annotation.kind == .note, !quotePreview.isEmpty {
            let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(statusDotColor)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                Text("“\(quotePreview)”")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appTheme.cardSurface, in: shape)
            .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var noteBodySection: some View {
        let cardShape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        if isEditing {
            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    annotation.kind == .tk ? "What’s to come? (optional)" : "Your note",
                    text: $draftText,
                    prompt: appTheme.sepiaPrompt(
                        annotation.kind == .tk ? "What’s to come? (optional)" : "Your note"
                    ),
                    axis: .vertical
                )
                .font(.body)
                .lineLimit(3 ... 8)
                .padding(12)
                .background(appTheme.cardSurface, in: cardShape)
                .overlay(cardShape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
                .accessibilityLabel(annotation.kind == .tk ? "TK description" : "Note text")

                FlowLayout(spacing: 8, rowSpacing: 8) {
                    pillActionButton(
                        title: "Save",
                        accessibilityLabel: "Save changes",
                        style: .primary,
                        isDisabled: !canSaveEdit || isWorking
                    ) {
                        saveEdit()
                    }
                    pillActionButton(
                        title: "Cancel",
                        accessibilityLabel: "Cancel editing",
                        style: .secondary,
                        isDisabled: isWorking
                    ) {
                        draftText = annotation.text
                        isEditing = false
                    }
                }
            }
        } else {
            let trimmed = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = trimmed.isEmpty
                ? (annotation.kind == .tk ? "No description yet" : "Empty note")
                : trimmed
            Text(display)
                .font(.body)
                .foregroundStyle(trimmed.isEmpty ? AnyShapeStyle(.secondaryInk) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(appTheme.cardSurface, in: cardShape)
                .overlay(cardShape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
        }
    }

    /// The labels name what this is: a note or a TK (wave 48 review).
    private var kindNoun: String { annotation.kind == .tk ? "TK" : "note" }

    private var actionButtons: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            pillActionButton(
                title: isResolved ? "Reopen" : "Resolve",
                accessibilityLabel: isResolved ? "Reopen \(kindNoun)" : "Resolve \(kindNoun)",
                style: .primary,
                isDisabled: isWorking
            ) {
                toggleResolved()
            }
            pillActionButton(
                title: "Edit",
                accessibilityLabel: "Edit \(kindNoun)",
                style: .secondary,
                isDisabled: isWorking
            ) {
                draftText = annotation.text
                isEditing = true
            }
            pillActionButton(
                title: "Delete",
                accessibilityLabel: "Delete \(kindNoun)",
                style: .destructive,
                isDisabled: isWorking
            ) {
                deleteNote()
            }
        }
    }

    private enum PillStyle {
        case primary
        case secondary
        case destructive
    }

    private func pillActionButton(
        title: String,
        accessibilityLabel: String,
        style: PillStyle,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        let foreground: Color = switch style {
        case .primary: ThemeManager.label(on: effectiveTint)
        case .secondary: Color.primary
        case .destructive: appTheme.errorColor
        }
        let background: Color = switch style {
        case .primary: effectiveTint
        case .secondary, .destructive: appTheme.glassFill(0.10)
        }
        return Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 34)
                .background(background, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .minimumHitTarget(44)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private func toggleResolved() {
        isWorking = true
        let nextResolved = !isResolved
        let current = annotation
        Task {
            if let updated = await onToggleResolved(current, nextResolved) {
                annotation = updated
            }
            isWorking = false
            dismiss()
        }
    }

    private func saveEdit() {
        guard canSaveEdit else { return }
        isWorking = true
        let text = trimmedDraft
        let current = annotation
        Task {
            if let updated = await onSaveText(current, text) {
                annotation = updated
                draftText = updated.text
            }
            isWorking = false
            isEditing = false
        }
    }

    private func deleteNote() {
        isWorking = true
        let current = annotation
        Task {
            await onDelete(current)
            isWorking = false
            dismiss()
        }
    }
}

// MARK: - Typed TK "What's to come?" prompt banner (`Editor-Annotations.dc.html`)

/// Compact non-blocking prompt shown above the editor footer when the writer finishes typing `"TK"`.
/// Saving creates a `.tk` annotation with an optional description; Cancel leaves `"TK"` as plain letters.
struct ChapterEditorTKPromptBanner: View {
    @Binding var descriptionText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                ChapterEditorAnnotationBadge(kind: .tk)
                Text("What’s to come?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondaryInk)
                        .frame(width: 28, height: 28)
                        .background(appTheme.glassFill(0.10), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .minimumHitTarget(44)
                .accessibilityLabel("Cancel TK marker")
            }

            TextField(
                "e.g. the boat’s name (optional)",
                text: $descriptionText,
                prompt: appTheme.sepiaPrompt("e.g. the boat’s name (optional)")
            )
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(appTheme.glassFill(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onSubmit(onSave)
            .accessibilityLabel("What’s to come")

            FlowLayout(spacing: 8, rowSpacing: 8) {
                Button(action: onSave) {
                    Text("Mark TK")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ThemeManager.label(on: effectiveTint))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(minHeight: 34)
                        .background(effectiveTint, in: SubjectMetrics.controlShape(dynamicTypeSize))
                        .contentShape(SubjectMetrics.controlShape(dynamicTypeSize))
                }
                .buttonStyle(.plain)
                .minimumHitTarget(44)
                .accessibilityLabel("Save TK marker")

                Button(action: onCancel) {
                    Text("Keep as Text")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 34)
                        .background(appTheme.glassFill(0.10), in: SubjectMetrics.controlShape(dynamicTypeSize))
                        .contentShape(SubjectMetrics.controlShape(dynamicTypeSize))
                }
                .buttonStyle(.plain)
                .minimumHitTarget(44)
                .accessibilityLabel("Cancel and keep TK as plain text")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(appTheme.cardSurface, in: shape)
        .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
        .shadow(
            color: appTheme.cardShadow.color,
            radius: max(appTheme.cardShadow.radius, appTheme.isDarkFamily ? 0 : 10),
            y: max(appTheme.cardShadow.y, appTheme.isDarkFamily ? 0 : 4)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
