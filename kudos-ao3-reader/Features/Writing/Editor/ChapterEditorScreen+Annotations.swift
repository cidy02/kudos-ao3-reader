import SwiftUI

/// Captured selection anchor waiting for the writer to finish composing a new note.
nonisolated struct PendingNoteAnchor: Identifiable, Equatable, Sendable {
    let id = UUID()
    let html: String
    let anchor: WritingAnnotationAnchor
}

/// Active modal sheet presented for anchored chapter notes in `ChapterEditorScreen`.
nonisolated enum ChapterEditorAnnotationSheet: Identifiable, Equatable, Sendable {
    case addNote(PendingNoteAnchor)
    case inspect(WritingAnnotation)

    var id: String {
        switch self {
        case let .addNote(pending): "add-\(pending.id.uuidString)"
        case let .inspect(annotation): "inspect-\(annotation.id.uuidString)"
        }
    }
}

// MARK: - Notes in the text, TK markers, and story-note name suggestions (T-576d)

extension ChapterEditorScreen {
    /// Up to three story-note name chips for the word before the caret in Rich Text.
    /// Returns empty for AO3-only chapters with no local work or no story notes.
    var nameSuggestions: [String] {
        guard isRichMode, documentBridge.workID != nil else { return [] }
        return ChapterEditorNameMatcher.suggestions(
            for: session?.wordAtCaret,
            names: documentBridge.storyNoteNames
        )
    }

    /// Best known chapter HTML for computing `"Paragraph N"` labels in the Notes sheet.
    var currentAnnotationHTML: String {
        latestAnnotationHTML.isEmpty ? (session?.text ?? content) : latestAnnotationHTML
    }

    @ViewBuilder
    var tkPromptBanner: some View {
        if tkTracker.activeTK != nil {
            ChapterEditorTKPromptBanner(
                descriptionText: $tkDescriptionText,
                onSave: { savePendingTK() },
                onCancel: { cancelPendingTK() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    var bottomFooter: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            if isRichMode {
                let suggestions = nameSuggestions
                WritingKeysBar(
                    formatState: session?.formatState ?? FormatState(),
                    showsLeadingContent: !suggestions.isEmpty,
                    onAction: { action in
                        _ = handleHostCommand(RichEditorHostCommand.from(action))
                    },
                    leadingSlot: {
                        WritingNameSuggestionChips(suggestions: suggestions) { selected in
                            applyNameSuggestion(selected)
                        }
                    }
                )
            }
            #endif
            EditorStatusLine(
                summary: statusSummary,
                onTapNotes: { notesSheetTab = .chapterNotes }
            )
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.vertical, 8)
            .background(footerBackground)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(appTheme.appSeparator ?? appTheme.glassStroke(0.14))
                    .frame(height: 0.5)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    var footerBackground: some View {
        if let base = appTheme.appBaseBackground {
            base.opacity(0.96)
        } else {
            Rectangle().fill(.bar)
        }
    }

    @ViewBuilder
    func annotationSheetView(for sheet: ChapterEditorAnnotationSheet) -> some View {
        switch sheet {
        case let .addNote(pending):
            ChapterEditorAddNoteSheet(
                quotePreview: ChapterEditorAnnotationAnchoring.plainQuotePreview(
                    from: pending.anchor.quote
                ),
                onSave: { noteText in
                    saveNewNote(pending: pending, text: noteText)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)

        case let .inspect(annotation):
            let paragraph: Int? = documentBridge.lostAnnotationIDs.contains(annotation.id)
                ? nil
                : ChapterEditorAnnotationAnchoring.paragraphNumber(
                    atUTF16Offset: annotation.utf16Offset,
                    in: currentAnnotationHTML
                )
            ChapterEditorAnnotationDetailSheet(
                annotation: annotation,
                paragraphNumber: paragraph,
                onToggleResolved: { target, resolved in
                    let updated = await documentBridge.setAnnotationResolved(
                        target,
                        resolved: resolved
                    )
                    await syncAnnotationsToRichEditor(useCurrentHTML: true)
                    return updated
                },
                onSaveText: { target, text in
                    var edited = target
                    edited.text = text
                    let updated = await documentBridge.updateAnnotation(edited)
                    await syncAnnotationsToRichEditor(useCurrentHTML: true)
                    return updated
                },
                onDelete: { target in
                    _ = await documentBridge.deleteAnnotation(target.id)
                    await syncAnnotationsToRichEditor(useCurrentHTML: true)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    func beginAddingNote() {
        guard let session, isRichMode else { return }
        Task {
            guard let selection = await session.selectionForAnchoring(),
                  let anchor = ChapterEditorAnnotationAnchoring.anchorForSelection(
                      html: selection.html,
                      range: selection.range
                  ) else {
                showTransientStatus("Select text in the chapter to add a note")
                return
            }
            latestAnnotationHTML = selection.html
            activeAnnotationSheet = .addNote(
                PendingNoteAnchor(html: selection.html, anchor: anchor)
            )
        }
    }

    func saveNewNote(pending: PendingNoteAnchor, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            guard await documentBridge.addAnnotation(
                anchor: pending.anchor,
                text: trimmed,
                kind: .note
            ) != nil else { return }
            let liveHTML = await session?.currentHTML() ?? pending.html
            await syncAnnotationsToRichEditor(htmlOverride: liveHTML)
        }
    }

    func handleAnnotationTap(_ tap: DraftAnnotationTap?) {
        guard let tappedID = annotationTapTracker.receive(tap),
              let uuid = UUID(uuidString: tappedID),
              let annotation = documentBridge.annotations.first(where: { $0.id == uuid }) else {
            return
        }
        activeAnnotationSheet = .inspect(annotation)
    }

    func handleTypedTK(_ typedTK: DraftTypedTK?) {
        guard isRichMode else { return }
        withAnimationUnlessReduced(.snappy(duration: 0.2), reduceMotion: reduceMotion) {
            if tkTracker.receive(typedTK) {
                tkDescriptionText = ""
            }
        }
    }

    func savePendingTK() {
        guard let pending = tkTracker.activeTK, let session else { return }
        let description = tkDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimationUnlessReduced(.snappy(duration: 0.2), reduceMotion: reduceMotion) {
            tkTracker.dismiss()
        }
        tkDescriptionText = ""
        Task {
            guard let html = await session.currentHTML() else { return }
            guard let anchor = ChapterEditorAnnotationAnchoring.anchorForTK(
                html: html,
                range: pending.range
            ) else {
                showTransientStatus("Couldn’t find TK in the chapter")
                return
            }
            guard await documentBridge.addAnnotation(
                anchor: anchor,
                text: description,
                kind: .tk
            ) != nil else { return }
            await syncAnnotationsToRichEditor(htmlOverride: html)
        }
    }

    func cancelPendingTK() {
        withAnimationUnlessReduced(.snappy(duration: 0.2), reduceMotion: reduceMotion) {
            tkTracker.dismiss()
        }
        tkDescriptionText = ""
    }

    func applyNameSuggestion(_ name: String) {
        session?.completeWord(name)
    }

    func syncKeysAccessorySuggestions() {
        #if os(iOS)
        syncWritingKeysPhoneActions()
        guard let accessory = richHost?.webView.keysAccessoryView else { return }
        let suggestions = nameSuggestions
        if suggestions.isEmpty {
            accessory.clearLeadingSlot()
        } else {
            let activeSession = session
            accessory.updateLeadingSlot(hasContent: true) {
                WritingNameSuggestionChips(suggestions: suggestions) { [weak activeSession] selected in
                    activeSession?.completeWord(selected)
                }
            }
        }
        #endif
    }

    func clearKeysAccessorySuggestions() {
        #if os(iOS)
        richHost?.webView.keysAccessoryView?.clearLeadingSlot()
        syncWritingKeysPhoneActions()
        #endif
    }

    func scheduleAnnotationSync(htmlOverride: String? = nil, useCurrentHTML: Bool = false) {
        annotationSyncTask?.cancel()
        annotationSyncGeneration += 1
        let generation = annotationSyncGeneration
        annotationSyncTask = Task {
            await syncAnnotationsToRichEditor(
                htmlOverride: htmlOverride,
                useCurrentHTML: useCurrentHTML,
                generation: generation
            )
        }
    }

    func syncAnnotationsToRichEditor(
        htmlOverride: String? = nil,
        useCurrentHTML: Bool = false,
        generation: Int? = nil
    ) async {
        guard let session, session.owner == .rich, documentBridge.chapterID != nil else { return }
        let bodyHTML: String
        if let htmlOverride {
            bodyHTML = htmlOverride
        } else if useCurrentHTML {
            bodyHTML = await session.currentHTML() ?? session.text
        } else {
            bodyHTML = session.text
        }
        guard !Task.isCancelled else { return }
        if let generation, generation != annotationSyncGeneration { return }

        latestAnnotationHTML = bodyHTML
        guard let report = await documentBridge.reanchorAnnotations(in: bodyHTML) else { return }
        guard !Task.isCancelled, session.owner == .rich else { return }
        if let generation, generation != annotationSyncGeneration { return }

        let items = ChapterEditorAnnotationAnchoring.bridgeItems(from: report.placed)
        _ = await session.setAnnotations(items)
    }

    func refreshChapterAnnotationsForNotesSheet() {
        guard documentBridge.chapterID != nil else { return }
        Task {
            let bodyHTML: String
            if let session, session.owner == .rich {
                bodyHTML = await session.currentHTML() ?? session.text
            } else {
                bodyHTML = session?.text ?? content
            }
            latestAnnotationHTML = bodyHTML
            _ = await documentBridge.reanchorAnnotations(in: bodyHTML)
        }
    }
}
