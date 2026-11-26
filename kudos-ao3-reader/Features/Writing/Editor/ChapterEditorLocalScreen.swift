import SwiftUI

/// Account-free chapter editor backed solely by `WritingDocumentStore`.
/// Opens an existing local manuscript or creates a new one on this device with
/// multi-chapter switching, chapter creation, and local soft-delete support.
struct LocalChapterEditorScreen: View {
    let initialWorkID: UUID?
    let initialChapterID: UUID?
    let initialWorkTitle: String
    let store: WritingDocumentStore

    @State private var bridge: ChapterEditorDocumentBridge
    @State private var workTitle: String
    @State private var activeChapterID: UUID?
    @State private var chapterNumber = 1
    @State private var chapterTitle = ""
    @State private var summary = ""
    @State private var notesBefore = ""
    @State private var notesAfter = ""
    @State private var content = ""
    @State private var isLoaded = false

    init(
        workID: UUID? = nil,
        chapterID: UUID? = nil,
        initialWorkTitle: String = "",
        store: WritingDocumentStore = WritingDocumentStore(root: WritingDocumentStore.defaultRoot)
    ) {
        self.initialWorkID = workID
        self.initialChapterID = chapterID
        self.initialWorkTitle = initialWorkTitle
        self.store = store
        _bridge = State(initialValue: ChapterEditorDocumentBridge(store: store))
        _workTitle = State(initialValue: initialWorkTitle)
    }

    var body: some View {
        Group {
            if isLoaded, let workID = bridge.workID, let chapterID = activeChapterID {
                ChapterEditorScreen(
                    workTitle: workTitle,
                    chapterNumber: chapterNumber,
                    chapterTitle: $chapterTitle,
                    summary: $summary,
                    notesBefore: $notesBefore,
                    notesAfter: $notesAfter,
                    content: $content,
                    account: "local",
                    recoveryTarget: "local:\(workID.uuidString):chapter:\(chapterID.uuidString)",
                    ao3Actions: nil,
                    localDocumentTarget: .local(workID: workID, chapterID: chapterID),
                    documentStore: store,
                    documentBridge: bridge,
                    onSwitchLocalChapter: { nextID in
                        Task { await switchToChapter(nextID) }
                    },
                    onNewLocalChapter: {
                        Task { await createNewChapter() }
                    },
                    onDeleteLocalChapter: {
                        Task { await deleteCurrentChapter() }
                    }
                )
                .id(chapterID)
            } else if let error = bridge.lastError {
                ContentUnavailableView(
                    "Couldn't Open Document",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView("Opening document…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accentFill()
            }
        }
        .task {
            guard !isLoaded else { return }
            let payload = ChapterEditorChapterPayload(
                workTitle: initialWorkTitle,
                chapterTitle: "",
                summary: "",
                notesBefore: "",
                notesAfter: "",
                bodyHTML: "",
                ao3ChapterID: nil,
                status: .local
            )
            if let snapshot = await bridge.open(
                target: .local(workID: initialWorkID, chapterID: initialChapterID),
                initialPayload: payload
            ) {
                workTitle = snapshot.work.title
                applyLoadedDocument(
                    WritingChapterDocument(
                        chapter: snapshot.activeChapter,
                        bodyHTML: snapshot.activeBodyHTML
                    )
                )
                isLoaded = true
            }
        }
    }

    private func currentPayload() -> ChapterEditorChapterPayload {
        ChapterEditorChapterPayload(
            workTitle: workTitle,
            chapterTitle: chapterTitle,
            summary: summary,
            notesBefore: notesBefore,
            notesAfter: notesAfter,
            bodyHTML: content,
            ao3ChapterID: nil,
            status: .local
        )
    }

    private func switchToChapter(_ nextID: UUID) async {
        if let loaded = await bridge.switchChapter(to: nextID, savingCurrent: currentPayload()) {
            applyLoadedDocument(loaded)
        }
    }

    private func createNewChapter() async {
        if let loaded = await bridge.addChapter(savingCurrent: currentPayload()) {
            applyLoadedDocument(loaded)
        }
    }

    private func deleteCurrentChapter() async {
        if let loaded = await bridge.deleteActiveChapter() {
            applyLoadedDocument(loaded)
        }
    }

    private func applyLoadedDocument(_ document: WritingChapterDocument) {
        activeChapterID = document.chapter.id
        chapterTitle = document.chapter.title
        summary = document.chapter.summary
        notesBefore = document.chapter.notesBefore
        notesAfter = document.chapter.notesAfter
        content = document.bodyHTML
        if let index = bridge.chapters.firstIndex(where: { $0.id == document.chapter.id }) {
            chapterNumber = index + 1
        } else {
            chapterNumber = 1
        }
    }
}
