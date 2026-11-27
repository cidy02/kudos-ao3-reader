import SwiftUI

/// A single work's files (`Studio-Work-Files`): header with state, Chapters with
/// status badges and context menu (open, rename, duplicate, move up/down, delete),
/// private Story Notes (574a), and For AO3 → Work details.
///
/// Exports section is omitted because Kudos does not persist per-work writing export files.
struct StudioWorkFilesView: View {
    let initialWork: StudioWorkItem
    let store: WritingDocumentStore
    var onChanged: () -> Void = {}
    var onAO3Write: () -> Void = {}

    @Environment(AO3AuthService.self) var auth
    @Environment(ThemeManager.self) var theme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @State var localWork: WritingWork?
    @State var localChapters: [WritingChapter] = []
    @State var storyNotes: [WritingStoryNote] = []
    @State var ao3Chapters: [AO3ChapterRef] = []
    @State var isLoadingAO3Chapters = false
    @State var ao3ChaptersError: String?
    @State var ao3ChapterLoadID = 0

    @State var activeChapterRoute: LocalChapterOpenRoute?
    @State var activeAO3ChapterRoute: AO3ChapterOpenRoute?
    @State var showingWorkDetails = false

    @State var renamingChapter: StudioWorkChapterItem?
    @State var renameChapterText = ""
    @State var deletingChapter: StudioWorkChapterItem?
    @State var deletingNote: WritingStoryNote?

    @State var showingRenameWork = false
    @State var renameWorkText = ""

    @State var noteSheetMode: StoryNoteSheetMode?
    @State var errorMessage: String?

    struct LocalChapterOpenRoute: Identifiable, Hashable {
        let workID: UUID
        let chapterID: UUID
        let workTitle: String
        var id: UUID { chapterID }
    }

    struct AO3ChapterOpenRoute: Identifiable, Hashable {
        let workID: Int
        let workTitle: String
        let chapterID: Int?
        let chapterCount: Int?
        var id: String { "\(workID)-\(chapterID ?? -1)" }
    }

    enum StoryNoteSheetMode: Identifiable {
        case create
        case edit(WritingStoryNote)

        var id: String {
            switch self {
            case .create: "create"
            case let .edit(note): note.id.uuidString
            }
        }
    }

    init(
        work: StudioWorkItem,
        store: WritingDocumentStore,
        onChanged: @escaping () -> Void = {},
        onAO3Write: @escaping () -> Void = {}
    ) {
        self.initialWork = work
        self.store = store
        self.onChanged = onChanged
        self.onAO3Write = onAO3Write
        _localWork = State(initialValue: work.localWork)
        _localChapters = State(initialValue: work.localChapters)
        _storyNotes = State(initialValue: work.storyNotes)
    }

    var currentWork: StudioWorkItem {
        var merged = initialWork
        merged.localWork = localWork
        merged.localChapters = localChapters
        merged.storyNotes = storyNotes
        return merged
    }

    var mergedChapters: [StudioWorkChapterItem] {
        StudioWorkFilesLogic.mergeChapters(
            localWorkID: localWork?.id,
            localChapters: localChapters,
            ao3WorkID: currentWork.ao3WorkID,
            ao3Chapters: ao3Chapters,
            isAO3DraftWork: currentWork.isAO3Draft && !currentWork.isPostedOnAO3,
            ao3DraftWordCount: currentWork.ao3DraftWork?.words,
            ao3DraftDateText: currentWork.ao3DraftWork?.dateUpdated
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                chaptersSection
                notesSection
                if currentWork.ao3WorkID != nil {
                    forAO3Section
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(theme.appTheme.contentBackdrop.ignoresSafeArea())
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .navigationDestination(item: $activeChapterRoute) { route in
            LocalChapterEditorScreen(
                workID: route.workID,
                chapterID: route.chapterID,
                initialWorkTitle: route.workTitle,
                store: store
            )
        }
        .navigationDestination(item: $activeAO3ChapterRoute) { route in
            if route.chapterID == nil, currentWork.isAO3Draft, !currentWork.isPostedOnAO3 {
                WritingWorkDestination(workID: route.workID) {
                    onAO3Write()
                    Task { await loadAO3Chapters(force: true) }
                }
            } else {
                WritingChapterDestination(
                    workID: route.workID,
                    workTitle: route.workTitle,
                    chapterID: route.chapterID,
                    chapterCount: route.chapterCount
                ) {
                    onAO3Write()
                    Task { await loadAO3Chapters(force: true) }
                }
            }
        }
        .navigationDestination(isPresented: $showingWorkDetails) {
            if let ao3WorkID = currentWork.ao3WorkID {
                StudioWorkDetailsDestination(
                    workID: ao3WorkID,
                    workTitle: currentWork.title,
                    subtitleText: currentWork.manuscriptStateLine(deviceName: ThisDevice.name)
                ) {
                    onAO3Write()
                    Task { await loadAO3Chapters(force: true) }
                }
            }
        }
        .task(id: auth.sessionGeneration) {
            await reloadLocal()
            await loadAO3Chapters(force: false)
        }
        .refreshable {
            await reloadLocal()
            await loadAO3Chapters(force: true)
        }
        .sheet(item: $noteSheetMode) { mode in
            StudioStoryNoteEditorSheet(mode: mode) { kind, name, detail, pinned, existing in
                Task {
                    await saveStoryNote(
                        kind: kind, name: name, detail: detail, pinned: pinned, existing: existing
                    )
                }
            }
        }
        .alert(
            "Rename Chapter",
            isPresented: Binding(
                get: { renamingChapter != nil },
                set: { if !$0 { renamingChapter = nil } }
            )
        ) {
            TextField("Chapter title", text: $renameChapterText)
            Button("Cancel", role: .cancel) { renamingChapter = nil }
            Button("Save") {
                guard let chapter = renamingChapter else { return }
                let nextTitle = renameChapterText
                renamingChapter = nil
                Task { await performRenameChapter(chapter, title: nextTitle) }
            }
        }
        .alert("Rename Folder", isPresented: $showingRenameWork) {
            TextField("Work title", text: $renameWorkText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let nextTitle = renameWorkText
                Task { await performRenameWork(title: nextTitle) }
            }
        }
        .alert(
            "Delete Chapter?",
            isPresented: Binding(
                get: { deletingChapter != nil },
                set: { if !$0 { deletingChapter = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { deletingChapter = nil }
            Button("Delete", role: .destructive) {
                guard let chapter = deletingChapter else { return }
                deletingChapter = nil
                Task { await performDeleteChapter(chapter) }
            }
        } message: {
            let name = deletingChapter?.shortTitle ?? "this chapter"
            Text("Moves \"\(name)\" to Recently Deleted for 30 days.")
        }
        .alert(
            "Delete Note?",
            isPresented: Binding(
                get: { deletingNote != nil },
                set: { if !$0 { deletingNote = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { deletingNote = nil }
            Button("Delete", role: .destructive) {
                guard let note = deletingNote else { return }
                deletingNote = nil
                Task { await deleteNote(note) }
            }
        } message: {
            let trimmed = deletingNote?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = trimmed.isEmpty ? "this note" : trimmed
            Text("Deletes \"\(name)\" from this work. This cannot be undone.")
        }
        .alert(
            "Couldn't Update Work",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await addChapter() }
            } label: {
                Label("Add Chapter", systemImage: "plus")
            }
            .accessibilityLabel("Add chapter to \(currentWork.title)")

            Menu {
                Button {
                    noteSheetMode = .create
                } label: {
                    Label("New Story Note", systemImage: "note.text.badge.plus")
                }
                if localWork != nil {
                    Button {
                        renameWorkText = currentWork.title
                        showingRenameWork = true
                    } label: {
                        Label("Rename Folder", systemImage: "pencil")
                    }
                }
                if currentWork.ao3WorkID != nil, auth.isLoggedIn {
                    Button {
                        showingWorkDetails = true
                    } label: {
                        Label("Work Details on AO3", systemImage: "list.bullet.rectangle")
                    }
                }
            } label: {
                Label("More options", systemImage: "ellipsis")
            }
            .accessibilityLabel("More options for \(currentWork.title)")
        }
    }
}

// MARK: - Actions & Loading

extension StudioWorkFilesView {

    func reloadLocal() async {
        guard let workID = localWork?.id else { return }
        do {
            let loadedWork = try await store.openWork(workID)
            let loadedChapters = try await store.listChapters(workID: workID)
            let loadedNotes = try await store.listStoryNotes(workID: workID)
            guard !Task.isCancelled else { return }
            localWork = loadedWork
            localChapters = loadedChapters
            storyNotes = loadedNotes
        } catch {
            // Keep prior snapshot on transient disk error.
        }
    }

    func loadAO3Chapters(force: Bool) async {
        guard let ao3WorkID = currentWork.ao3WorkID,
              currentWork.isPostedOnAO3,
              auth.isLoggedIn else {
            ao3Chapters = []
            ao3ChaptersError = nil
            isLoadingAO3Chapters = false
            return
        }
        ao3ChapterLoadID += 1
        let loadID = ao3ChapterLoadID
        let session = auth.sessionGeneration
        let cache = StudioAO3LoadCache.shared
        if let cached = cache.chapters(workID: ao3WorkID, session: session) {
            ao3Chapters = cached.chapters
            ao3ChaptersError = cached.chapters.isEmpty ? cached.error : nil
            if !force && !StudioAO3Freshness.isStale(cached.loadedAt) {
                isLoadingAO3Chapters = false
                return
            }
        }
        guard loadID == ao3ChapterLoadID else { return }
        isLoadingAO3Chapters = ao3Chapters.isEmpty
        do {
            let request = try auth.authenticatedRequest(for: AO3Client.chapterIndexURL(workID: ao3WorkID))
            let loaded = try await AO3Client.shared.chapterIndex(workID: ao3WorkID, request: request)
            guard loadID == ao3ChapterLoadID, !Task.isCancelled, session == auth.sessionGeneration else {
                if loadID == ao3ChapterLoadID { isLoadingAO3Chapters = false }
                return
            }
            ao3Chapters = loaded
            ao3ChaptersError = nil
            cache.storeChapters(
                workID: ao3WorkID,
                session: session,
                chapters: loaded,
                error: nil,
                loadedAt: Date()
            )
        } catch {
            guard loadID == ao3ChapterLoadID, !Task.isCancelled, session == auth.sessionGeneration else {
                if loadID == ao3ChapterLoadID { isLoadingAO3Chapters = false }
                return
            }
            let message = UserFacingError.message(for: error)
            if ao3Chapters.isEmpty {
                ao3ChaptersError = message
            }
            cache.storeChapters(
                workID: ao3WorkID,
                session: session,
                chapters: ao3Chapters.isEmpty ? [] : nil,
                error: ao3Chapters.isEmpty ? message : nil,
                loadedAt: Date()
            )
        }
        isLoadingAO3Chapters = false
    }

    func openChapter(_ chapter: StudioWorkChapterItem) {
        if let localWorkID = chapter.localWorkID, let localChapterID = chapter.localChapterID {
            activeChapterRoute = LocalChapterOpenRoute(
                workID: localWorkID,
                chapterID: localChapterID,
                workTitle: currentWork.title
            )
        } else if let ao3WorkID = chapter.ao3WorkID, auth.isLoggedIn {
            activeAO3ChapterRoute = AO3ChapterOpenRoute(
                workID: ao3WorkID,
                workTitle: currentWork.title,
                chapterID: chapter.ao3ChapterID,
                chapterCount: mergedChapters.count
            )
        }
    }

    func addChapter() async {
        do {
            let outcome = try await StudioAddChapterPlanner.perform(
                work: currentWork,
                isSignedIn: auth.isLoggedIn,
                store: store,
                ao3ChapterCount: mergedChapters.count
            )
            switch outcome {
            case let .openedLocal(workID, chapterID, workTitle):
                if localWork?.id != workID {
                    localWork = try await store.openWork(workID)
                }
                await reloadLocal()
                onChanged()
                activeChapterRoute = LocalChapterOpenRoute(
                    workID: workID,
                    chapterID: chapterID,
                    workTitle: workTitle
                )
            case let .openAO3(workID, workTitle, chapterCount):
                activeAO3ChapterRoute = AO3ChapterOpenRoute(
                    workID: workID,
                    workTitle: workTitle,
                    chapterID: nil,
                    chapterCount: chapterCount
                )
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func performRenameChapter(_ chapter: StudioWorkChapterItem, title: String) async {
        guard let workID = chapter.localWorkID, let chapterID = chapter.localChapterID else { return }
        do {
            _ = try await StudioWorkFilesLogic.renameChapter(
                in: store, workID: workID, chapterID: chapterID, title: title
            )
            await reloadLocal()
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func performDuplicateChapter(_ chapter: StudioWorkChapterItem) async {
        guard let workID = chapter.localWorkID, let chapterID = chapter.localChapterID else { return }
        do {
            _ = try await StudioWorkFilesLogic.duplicateChapter(
                in: store, workID: workID, chapterID: chapterID
            )
            await reloadLocal()
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func performMoveChapter(
        _ chapter: StudioWorkChapterItem,
        direction: StudioWorkFilesLogic.MoveDirection
    ) async {
        guard let workID = chapter.localWorkID, let chapterID = chapter.localChapterID else { return }
        do {
            _ = try await StudioWorkFilesLogic.moveChapter(
                in: store, workID: workID, chapterID: chapterID, direction: direction
            )
            await reloadLocal()
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func performDeleteChapter(_ chapter: StudioWorkChapterItem) async {
        guard let workID = chapter.localWorkID, let chapterID = chapter.localChapterID else { return }
        do {
            try await StudioWorkFilesLogic.deleteChapter(in: store, workID: workID, chapterID: chapterID)
            await reloadLocal()
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func performRenameWork(title: String) async {
        guard let workID = localWork?.id else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            localWork = try await store.renameWork(workID, title: trimmed)
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func saveStoryNote(
        kind: WritingStoryNoteKind,
        name: String,
        detail: String,
        pinned: Bool,
        existing: WritingStoryNote?
    ) async {
        do {
            let workID: UUID = if let existingID = localWork?.id {
                existingID
            } else {
                try await createCompanionLocalWork()
            }
            if var note = existing {
                note.kind = kind
                note.name = name
                note.detail = detail
                note.pinned = pinned
                _ = try await store.updateStoryNote(workID: workID, note: note)
            } else {
                _ = try await store.addStoryNote(
                    workID: workID, kind: kind, name: name, detail: detail, pinned: pinned
                )
            }
            await reloadLocal()
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func togglePin(_ note: WritingStoryNote) async {
        guard let workID = localWork?.id else { return }
        var updated = note
        updated.pinned.toggle()
        do {
            _ = try await store.updateStoryNote(workID: workID, note: updated)
            await reloadLocal()
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func deleteNote(_ note: WritingStoryNote) async {
        guard let workID = localWork?.id else { return }
        do {
            try await store.deleteStoryNote(workID: workID, noteID: note.id)
            await reloadLocal()
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func createCompanionLocalWork() async throws -> UUID {
        if let existing = StudioAddChapterPlanner.existingLocalWorkID(
            ao3WorkID: currentWork.ao3WorkID,
            in: try await store.listWorks()
        ) {
            localWork = try await store.openWork(existing)
            return existing
        }
        let created = try await store.createWork(
            title: currentWork.title,
            ao3WorkID: currentWork.ao3WorkID
        )
        localWork = created
        return created.id
    }
}
