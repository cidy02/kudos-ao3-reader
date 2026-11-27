import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Actions, command routing & local document persistence

extension ChapterEditorScreen {
    func makeMoreMenuActions() -> EditorMoreMenuActions {
        let handlers = ChapterEditorMoreMenuHandlers(
            postOrUpdate: {
                handlePostOrUpdateAction()
            },
            preview: {
                if let preview = ao3Actions?.preview {
                    commitAndClose(then: preview)
                }
            },
            find: {
                #if os(iOS)
                richHost?.presentFind()
                #endif
            },
            saveAsAO3Draft: {
                handleSaveAsAO3DraftAction()
            },
            chapterMetadata: {
                notesSheetTab = .forAO3
            },
            workDetails: {
                openWorkDetails()
            },
            editTags: {
                openEditTags()
            },
            copyAsAO3HTML: {
                copyAsAO3HTML()
            },
            sendToBeta: {
                showingBetaReadingSheet = true
            },
            addNote: {
                beginAddingNote()
            },
            format: {
                showingFormatPanel = true
            },
            deleteChapter: {
                showingDeleteConfirmation = true
            },
            sprint: {
                sprintController.toggleFromMenu()
            },
            compareWithPosted: {
                togglePostedChangesView()
            },
            discardChanges: {
                showingDiscardChangesConfirmation = true
            }
        )
        return ChapterEditorMoreMenuWiring(
            capabilities: menuCapabilities,
            handlers: handlers
        ).actions()
    }

    func handleHostCommand(_ command: RichEditorHostCommand) -> Bool {
        switch command {
        case .openFormatPanel:
            showingFormatPanel = true
            return true
        case .requestLink:
            showingLinkSheet = true
            return true
        case .presentFind:
            // `RichEditorWebView.presentFindNavigator` presents the iOS 16+ find
            // navigator before emitting `.presentFind`; never call it again here.
            return true
        case .format(.openTableInHTML):
            openTableInHTML()
            return true
        case .requestNote:
            beginAddingNote()
            return true
        default:
            session?.apply(command)
            return true
        }
    }

    func handleFormatCommand(_ command: FormatCommand) {
        if command == .openTableInHTML {
            openTableInHTML()
            return
        }
        session?.apply(command)
    }

    func openTableInHTML() {
        showingFormatPanel = false
        Task { _ = await session?.switchToSource() }
    }

    func openWorkDetails() {
        if let open = ao3Actions?.openWorkDetails {
            commitAndClose(then: open)
        } else if resolvedAO3WorkID != nil,
                  (ao3Actions?.pushesWorkDetailsDestination == true) || (isLocalOnly && isSignedInToAO3) {
            Task {
                _ = await commitAndPersist(kind: .edit)
                showingWorkDetailsDestination = true
            }
        }
    }

    func handlePostOrUpdateAction() {
        switch studioPostRoute {
        case .updatePosted, .fallbackCallback:
            if let postOrUpdate = ao3Actions?.postOrUpdate {
                commitAndClose(then: postOrUpdate)
            }
        case let .postChapter(workID, chapterID):
            openPostSheet(.postChapter(workID: workID, chapterID: chapterID))
        case let .postNewWork(existingDraftWorkID):
            openPostSheet(.postNewWork(existingDraftWorkID: existingDraftWorkID))
        case .unavailable:
            break
        }
    }

    func handleSaveAsAO3DraftAction() {
        if let saveDraft = ao3Actions?.saveAsAO3Draft {
            commitAndClose(then: saveDraft)
            return
        }
        switch studioPostRoute {
        case let .postChapter(workID, chapterID):
            openPostSheet(.postChapter(workID: workID, chapterID: chapterID))
        case let .postNewWork(existingDraftWorkID):
            openPostSheet(.postNewWork(existingDraftWorkID: existingDraftWorkID))
        case .updatePosted, .fallbackCallback, .unavailable:
            break
        }
    }

    func openPostSheet(_ sheet: StudioEditorPostSheet) {
        guard isSignedInToAO3 else { return }
        Task {
            _ = await commitAndPersist(kind: .edit)
            activePostSheet = sheet
        }
    }

    @ViewBuilder
    func studioPostSheetView(for sheet: StudioEditorPostSheet) -> some View {
        if let authService = auth {
            switch sheet {
            case let .postChapter(workID, chapterID):
                StudioPostChapterSheet(
                    workID: workID,
                    chapterID: chapterID,
                    workTitle: resolvedWorkTitle,
                    chapterTitle: $chapterTitle,
                    summary: $summary,
                    notesBefore: $notesBefore,
                    notesAfter: $notesAfter,
                    content: $content,
                    openTKCount: documentBridge.tkCount,
                    openNoteCount: documentBridge.annotationCount
                ) { isDraft in
                    handlePostSheetCompleted(isDraft: isDraft)
                }
                .environment(authService)

            case let .postNewWork(existingDraftWorkID):
                StudioPostNewWorkSheet(
                    existingDraftWorkID: existingDraftWorkID,
                    workTitle: resolvedWorkTitle,
                    chapterTitle: chapterTitle,
                    summary: $summary,
                    notesBefore: $notesBefore,
                    notesAfter: $notesAfter,
                    content: $content
                ) { isDraft in
                    handlePostSheetCompleted(isDraft: isDraft)
                }
                .environment(authService)
            }
        }
    }

    func handlePostSheetCompleted(isDraft: Bool) {
        if let session, session.text != content {
            let wasRich = isRichMode
            session.restoreRecoveryCopy(content)
            if wasRich, session.isRichAvailable {
                Task { _ = await session.switchToRich() }
            }
        }
        initialSnapshot = InitialSnapshot(
            title: chapterTitle,
            summary: summary,
            notesBefore: notesBefore,
            notesAfter: notesAfter,
            content: content
        )
        Task {
            await persistLocalCopy(kind: .edit)
        }
        showTransientStatus(isDraft ? "Saved as AO3 draft" : "Posted to AO3")
        if !isLocalOnly {
            dismiss()
        }
    }

    func togglePostedChangesView() {
        guard isPosted else { return }
        if isComparingPostedChanges {
            isComparingPostedChanges = false
            return
        }
        Task {
            let committed = await commitAndPersist(kind: .edit)
            postedChangesHTMLSnapshot = committed
            isComparingPostedChanges = true
        }
    }

    func discardUnpostedChanges() {
        let wasRich = isRichMode
        chapterTitle = initialSnapshot.title
        summary = initialSnapshot.summary
        notesBefore = initialSnapshot.notesBefore
        notesAfter = initialSnapshot.notesAfter
        content = initialSnapshot.content
        postedChangesHTMLSnapshot = initialSnapshot.content
        session?.restoreRecoveryCopy(initialSnapshot.content)
        isComparingPostedChanges = false
        showTransientStatus("Changes discarded")
        Task {
            await persistLocalCopy(kind: .destructive)
            if wasRich, let session, session.isRichAvailable {
                _ = await session.switchToRich()
            }
        }
    }

    func openEditTags() {
        guard ao3Actions?.canEditTags == true, ao3Actions?.ao3WorkID != nil else { return }
        Task {
            _ = await commitAndPersist(kind: .edit)
            showingEditTagsDestination = true
        }
    }

    func copyAsAO3HTML() {
        Task {
            let committedHTML = await commitAndPersist(kind: .edit)
            #if os(iOS)
            UIPasteboard.general.string = committedHTML
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(committedHTML, forType: .string)
            #endif
            showTransientStatus("Copied AO3 HTML")
        }
    }

    func showTransientStatus(_ message: String) {
        transientStatusMessage = message
        statusClearTask?.cancel()
        statusClearTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            transientStatusMessage = nil
        }
    }

    var deleteAlertTitle: String {
        if let name = ao3Actions?.deleteChapterName {
            return "Delete “\(name)”?"
        }
        return "Delete “\(chapterDisplayTitle)”?"
    }

    var deleteAlertMessage: String {
        if ao3Actions?.deleteChapter != nil {
            return "This will delete all comments on the chapter as well and cannot be undone."
        }
        return "This moves the chapter to Recently Deleted on this \(ThisDevice.name) for 30 days."
    }

    func confirmDeleteChapter() {
        if let deleteChapter = ao3Actions?.deleteChapter {
            commitAndClose(then: deleteChapter)
        } else if let onDeleteLocalChapter {
            Task {
                _ = await commitAndPersist(kind: .edit)
                onDeleteLocalChapter()
            }
        }
    }

    func currentPayload(bodyOverride: String? = nil) -> ChapterEditorChapterPayload {
        ChapterEditorChapterPayload(
            workTitle: workTitle,
            chapterTitle: chapterTitle,
            summary: summary,
            notesBefore: notesBefore,
            notesAfter: notesAfter,
            bodyHTML: bodyOverride ?? content,
            ao3ChapterID: ao3Actions?.ao3ChapterID,
            status: currentChapterStatus
        )
    }

    func openDocumentBridge() async {
        // When an external host (`LocalChapterEditorScreen`) already opened the shared bridge
        // for this exact chapter, reuse its loaded snapshot without reopening on disk.
        if case let .local(workID, chapterID) = localDocumentTarget,
           workID != nil,
           documentBridge.workID == workID,
           documentBridge.chapterID == chapterID,
           let active = documentBridge.activeChapter {
            if let existingWorkID = workID,
               let loadedWork = try? await documentBridge.store.openWork(existingWorkID) {
                localWorkAO3ID = loadedWork.ao3WorkID
            }
            fallbackWordCount = active.wordCount
            if initialWordCount == nil { initialWordCount = active.wordCount }
            if session?.owner == .rich {
                await syncAnnotationsToRichEditor(useCurrentHTML: false)
                syncKeysAccessorySuggestions()
            }
            return
        }
        let snapshot = await documentBridge.open(
            target: currentDocumentTarget,
            initialPayload: currentPayload()
        )
        if let snapshot {
            localWorkAO3ID = snapshot.work.ao3WorkID
            fallbackWordCount = snapshot.activeChapter.wordCount
            if initialWordCount == nil {
                initialWordCount = snapshot.activeChapter.wordCount
            }
            if session?.owner == .rich {
                await syncAnnotationsToRichEditor(useCurrentHTML: false)
                syncKeysAccessorySuggestions()
            }
        }
    }

    func scheduleLocalSave() {
        metadataSaveTask?.cancel()
        metadataSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await persistLocalCopy(kind: .edit)
        }
    }

    @discardableResult
    func commitAndPersist(kind: WritingChapterSaveKind) async -> String {
        metadataSaveTask?.cancel()
        let committedHTML: String
        if let session {
            committedHTML = await session.commit()
            if content != committedHTML {
                content = committedHTML
            }
        } else {
            committedHTML = content
        }
        await documentBridge.save(currentPayload(bodyOverride: committedHTML), kind: kind)
        return committedHTML
    }

    func persistLocalCopy(kind: WritingChapterSaveKind) async {
        await documentBridge.save(currentPayload(), kind: kind)
    }

    func commitAndClose(then action: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        Task {
            _ = await commitAndPersist(kind: .edit)
            dismiss()
            action?()
        }
    }
}
