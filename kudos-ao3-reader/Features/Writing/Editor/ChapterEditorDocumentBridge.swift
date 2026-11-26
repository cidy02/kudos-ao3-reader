import Foundation
import Observation

/// Identifies which local `WritingDocumentStore` work and chapter a `ChapterEditorScreen`
/// mirrors or owns directly.
nonisolated enum ChapterEditorDocumentTarget: Equatable, Hashable, Sendable {
    /// Mirrors an AO3 chapter or work draft into a local device copy under `WritingDocumentStore`.
    case ao3Mirror(ao3WorkID: Int?, ao3ChapterID: Int?, isChapterOne: Bool)
    /// Opens or creates a standalone manuscript stored only on this device (no AO3 account needed).
    case local(workID: UUID?, chapterID: UUID?)
}

/// Snapshot of editable chapter fields written to `WritingDocumentStore`.
nonisolated struct ChapterEditorChapterPayload: Equatable, Sendable {
    var workTitle: String
    var chapterTitle: String
    var summary: String
    var notesBefore: String
    var notesAfter: String
    var bodyHTML: String
    var ao3ChapterID: Int?
    var status: WritingChapterStatus
}

/// Loaded local state returned when `ChapterEditorDocumentBridge.open` completes.
nonisolated struct ChapterEditorDocumentSnapshot: Equatable, Sendable {
    var work: WritingWork
    var activeChapter: WritingChapter
    var activeBodyHTML: String
    var chapters: [WritingChapter]
    var storyNotes: [WritingStoryNote]
    var annotationCount: Int
    var tkCount: Int
    var versionCount: Int
}

/// Bridges `ChapterEditorScreen` to the off-main-thread `WritingDocumentStore` actor.
/// Saves every chapter written in the screen as a device-local copy and supports
/// account-free local manuscripts, story notes, and chapter switching.
@MainActor @Observable
final class ChapterEditorDocumentBridge {
    @ObservationIgnored let store: WritingDocumentStore

    private(set) var workID: UUID?
    private(set) var chapterID: UUID?
    private(set) var activeChapter: WritingChapter?
    private(set) var chapters: [WritingChapter] = []
    private(set) var storyNotes: [WritingStoryNote] = []
    private(set) var annotationCount = 0
    private(set) var tkCount = 0
    private(set) var versionCount = 0
    private(set) var syncState: EditorSyncState = .saved
    private(set) var lastError: String?

    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?

    init(store: WritingDocumentStore = WritingDocumentStore(root: WritingDocumentStore.defaultRoot)) {
        self.store = store
    }

    /// Maps stored local chapters to `ChapterSwitcherMenu` summaries in work order.
    var chapterSummaries: [EditorChapterSummary] {
        chapters.enumerated().map { index, chapter in
            EditorChapterSummary(
                id: chapter.id.uuidString,
                number: index + 1,
                title: chapter.title,
                wordCount: chapter.wordCount,
                status: Self.switcherStatus(for: chapter.status)
            )
        }
    }

    /// Resolves or creates the local work and chapter for `target`.
    /// For `.ao3Mirror`, writes `initialPayload` so this device immediately has a copy.
    /// For `.local`, loads any existing chapter text from disk or initializes a new chapter.
    @discardableResult
    func open(
        target: ChapterEditorDocumentTarget,
        initialPayload: ChapterEditorChapterPayload
    ) async -> ChapterEditorDocumentSnapshot? {
        syncState = .saving
        lastError = nil
        do {
            let work = try await resolveWork(for: target, title: initialPayload.workTitle)
            let chapterDoc = try await resolveChapter(
                in: work,
                target: target,
                initialPayload: initialPayload
            )
            workID = work.id
            chapterID = chapterDoc.chapter.id
            activeChapter = chapterDoc.chapter
            let snapshot = try await refreshSnapshot(work: work, activeDocument: chapterDoc)
            syncState = .localOnly
            return snapshot
        } catch {
            lastError = UserFacingError.message(for: error)
            syncState = .unsaved
            return nil
        }
    }

    /// Persists the current chapter fields and canonical HTML body on the store actor.
    /// Serialized so back-to-back checkpoints reach disk in order.
    func save(
        _ payload: ChapterEditorChapterPayload,
        kind: WritingChapterSaveKind = .edit
    ) async {
        let previous = pendingSaveTask
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.performSave(payload, kind: kind)
        }
        pendingSaveTask = task
        await task.value
    }

    /// Saves the active chapter and loads `nextChapterID` in local multi-chapter mode.
    func switchChapter(
        to nextChapterID: UUID,
        savingCurrent payload: ChapterEditorChapterPayload
    ) async -> WritingChapterDocument? {
        await save(payload, kind: .edit)
        guard let workID else { return nil }
        lastError = nil
        do {
            let work = try await store.openWork(workID)
            let loaded = try await store.loadChapter(workID: workID, chapterID: nextChapterID)
            chapterID = loaded.chapter.id
            activeChapter = loaded.chapter
            _ = try await refreshSnapshot(work: work, activeDocument: loaded)
            syncState = .localOnly
            return loaded
        } catch {
            lastError = UserFacingError.message(for: error)
            return nil
        }
    }

    /// Saves the active chapter, creates a new local chapter, and makes it active.
    func addChapter(
        savingCurrent payload: ChapterEditorChapterPayload,
        title: String = ""
    ) async -> WritingChapterDocument? {
        await save(payload, kind: .edit)
        guard let workID else { return nil }
        lastError = nil
        do {
            let created = try await store.addChapter(workID: workID, title: title)
            let work = try await store.openWork(workID)
            let loaded = WritingChapterDocument(chapter: created, bodyHTML: "")
            chapterID = created.id
            activeChapter = created
            _ = try await refreshSnapshot(work: work, activeDocument: loaded)
            syncState = .localOnly
            return loaded
        } catch {
            lastError = UserFacingError.message(for: error)
            return nil
        }
    }

    /// Moves the active local chapter to Recently Deleted and switches to a sibling chapter.
    /// Returns `nil` if the work has no other chapters or if deletion fails.
    func deleteActiveChapter() async -> WritingChapterDocument? {
        guard let workID, let chapterID, chapters.count > 1 else { return nil }
        lastError = nil
        do {
            let remainingIDs = chapters.map(\.id).filter { $0 != chapterID }
            try await store.deleteChapter(workID: workID, chapterID: chapterID)
            guard let fallbackID = remainingIDs.first else { return nil }
            let work = try await store.openWork(workID)
            let loaded = try await store.loadChapter(workID: workID, chapterID: fallbackID)
            self.chapterID = loaded.chapter.id
            activeChapter = loaded.chapter
            _ = try await refreshSnapshot(work: work, activeDocument: loaded)
            syncState = .localOnly
            return loaded
        } catch {
            lastError = UserFacingError.message(for: error)
            return nil
        }
    }

    // MARK: - Story Notes (device-local, never sent to AO3)

    func addStoryNote(
        kind: WritingStoryNoteKind,
        name: String,
        detail: String,
        pinned: Bool
    ) async {
        guard let workID else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        lastError = nil
        do {
            _ = try await store.addStoryNote(
                workID: workID,
                kind: kind,
                name: trimmedName,
                detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                pinned: pinned
            )
            storyNotes = try await store.listStoryNotes(workID: workID)
        } catch {
            lastError = UserFacingError.message(for: error)
        }
    }

    func togglePinStoryNote(_ note: WritingStoryNote) async {
        guard let workID else { return }
        lastError = nil
        do {
            var updated = note
            updated.pinned.toggle()
            _ = try await store.updateStoryNote(workID: workID, note: updated)
            storyNotes = try await store.listStoryNotes(workID: workID)
        } catch {
            lastError = UserFacingError.message(for: error)
        }
    }

    func deleteStoryNote(_ noteID: UUID) async {
        guard let workID else { return }
        lastError = nil
        do {
            try await store.deleteStoryNote(workID: workID, noteID: noteID)
            storyNotes = try await store.listStoryNotes(workID: workID)
        } catch {
            lastError = UserFacingError.message(for: error)
        }
    }

    nonisolated static func switcherStatus(for status: WritingChapterStatus) -> EditorChapterStatus {
        switch status {
        case .local: .writing
        case .ao3Draft: .ao3Draft
        case .posted: .posted
        }
    }

    // MARK: - Internals

    private func performSave(
        _ payload: ChapterEditorChapterPayload,
        kind: WritingChapterSaveKind
    ) async {
        guard let workID, let chapterID else { return }
        syncState = .saving
        lastError = nil
        do {
            let trimmedWorkTitle = payload.workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedWorkTitle.isEmpty {
                _ = try await store.renameWork(workID, title: trimmedWorkTitle)
            }
            let current = try await store.loadChapter(workID: workID, chapterID: chapterID).chapter
            var updated = current
            updated.title = payload.chapterTitle
            updated.summary = payload.summary
            updated.notesBefore = payload.notesBefore
            updated.notesAfter = payload.notesAfter
            if let ao3ChapterID = payload.ao3ChapterID {
                updated.ao3ChapterID = ao3ChapterID
            }
            updated.status = payload.status
            let saved = try await store.saveChapter(
                workID: workID,
                chapter: updated,
                bodyHTML: payload.bodyHTML,
                kind: kind
            )
            activeChapter = saved.chapter
            chapters = try await store.listChapters(workID: workID)
            versionCount = try await store.listVersions(workID: workID, chapterID: chapterID).count
            syncState = .localOnly
        } catch {
            lastError = UserFacingError.message(for: error)
            syncState = .unsaved
        }
    }

    private func resolveWork(
        for target: ChapterEditorDocumentTarget,
        title: String
    ) async throws -> WritingWork {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : title
        switch target {
        case let .ao3Mirror(ao3WorkID, _, _):
            if let ao3WorkID,
               let existing = try await store.listWorks().first(where: { $0.ao3WorkID == ao3WorkID }) {
                if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   existing.title != title {
                    return try await store.renameWork(existing.id, title: title)
                }
                return existing
            }
            return try await store.createWork(title: resolvedTitle, ao3WorkID: ao3WorkID)
        case let .local(existingWorkID, _):
            if let existingWorkID {
                return try await store.openWork(existingWorkID)
            }
            return try await store.createWork(title: resolvedTitle, ao3WorkID: nil)
        }
    }

    private func resolveChapter(
        in work: WritingWork,
        target: ChapterEditorDocumentTarget,
        initialPayload: ChapterEditorChapterPayload
    ) async throws -> WritingChapterDocument {
        let existingChapters = try await store.listChapters(workID: work.id)
        switch target {
        case let .ao3Mirror(_, ao3ChapterID, isChapterOne):
            let matched: WritingChapter?
            if let ao3ChapterID {
                matched = existingChapters.first(where: { $0.ao3ChapterID == ao3ChapterID })
            } else if isChapterOne {
                matched = existingChapters.first
            } else {
                matched = nil
            }
            var chapter = if let matched {
                matched
            } else {
                try await store.addChapter(workID: work.id, title: initialPayload.chapterTitle)
            }
            chapter.title = initialPayload.chapterTitle
            chapter.summary = initialPayload.summary
            chapter.notesBefore = initialPayload.notesBefore
            chapter.notesAfter = initialPayload.notesAfter
            chapter.ao3ChapterID = ao3ChapterID ?? chapter.ao3ChapterID
            chapter.status = initialPayload.status
            return try await store.saveChapter(
                workID: work.id,
                chapter: chapter,
                bodyHTML: initialPayload.bodyHTML,
                kind: .edit
            )

        case let .local(_, requestedChapterID):
            if let requestedChapterID {
                return try await store.loadChapter(workID: work.id, chapterID: requestedChapterID)
            }
            if let first = existingChapters.first {
                return try await store.loadChapter(workID: work.id, chapterID: first.id)
            }
            let created = try await store.addChapter(workID: work.id, title: initialPayload.chapterTitle)
            if initialPayload.bodyHTML.isEmpty,
               initialPayload.summary.isEmpty,
               initialPayload.notesBefore.isEmpty,
               initialPayload.notesAfter.isEmpty {
                return WritingChapterDocument(chapter: created, bodyHTML: "")
            }
            var updated = created
            updated.summary = initialPayload.summary
            updated.notesBefore = initialPayload.notesBefore
            updated.notesAfter = initialPayload.notesAfter
            updated.status = .local
            return try await store.saveChapter(
                workID: work.id,
                chapter: updated,
                bodyHTML: initialPayload.bodyHTML,
                kind: .edit
            )
        }
    }

    private func refreshSnapshot(
        work: WritingWork,
        activeDocument: WritingChapterDocument
    ) async throws -> ChapterEditorDocumentSnapshot {
        let listedChapters = try await store.listChapters(workID: work.id)
        let notes = try await store.listStoryNotes(workID: work.id)
        let annotations = try await store.listAnnotations(
            workID: work.id,
            chapterID: activeDocument.chapter.id
        )
        let versions = try await store.listVersions(
            workID: work.id,
            chapterID: activeDocument.chapter.id
        )
        let unresolved = annotations.filter { $0.resolvedAt == nil }
        let noteTotal = unresolved.filter { $0.kind == .note }.count
        let tkTotal = unresolved.filter { $0.kind == .tk }.count

        chapters = listedChapters
        storyNotes = notes
        annotationCount = noteTotal
        tkCount = tkTotal
        versionCount = versions.count

        return ChapterEditorDocumentSnapshot(
            work: work,
            activeChapter: activeDocument.chapter,
            activeBodyHTML: activeDocument.bodyHTML,
            chapters: listedChapters,
            storyNotes: notes,
            annotationCount: noteTotal,
            tkCount: tkTotal,
            versionCount: versions.count
        )
    }
}
