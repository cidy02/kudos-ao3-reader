import Foundation

/// Badge status for a chapter inside `StudioWorkFilesView` (`Studio-Work-Files`).
nonisolated enum StudioChapterBadgeStatus: String, Equatable, Hashable, Sendable {
    case posted
    case ao3Draft
    case onDevice
    case planned

    func label(deviceName: String) -> String {
        switch self {
        case .posted: "Posted"
        case .ao3Draft: "AO3 draft"
        case .onDevice: deviceName
        case .planned: "Not started"
        }
    }
}

/// One chapter row in `StudioWorkFilesView` (and the featured Manuscript card on Pages).
nonisolated struct StudioWorkChapterItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var position: Int
    var title: String
    var badge: StudioChapterBadgeStatus
    var wordCount: Int?
    var dateText: String?
    var updatedAt: Date?
    var localWorkID: UUID?
    var localChapterID: UUID?
    var ao3WorkID: Int?
    var ao3ChapterID: Int?

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(position). \(trimmed.isEmpty ? "Untitled" : trimmed)"
    }

    var shortTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var canEditLocally: Bool {
        localWorkID != nil && localChapterID != nil
    }

    var metaLine: String {
        if badge == .planned { return "Planned" }
        var parts: [String] = []
        if let wordCount, wordCount > 0 {
            parts.append(StudioWorkItem.wordCountLabel(wordCount))
        }
        if let dateText, !dateText.isEmpty {
            let formatted = WorkStat.displayDate(dateText)
            parts.append(badge == .posted ? "Posted \(formatted)" : formatted)
        } else if let updatedAt {
            parts.append("edited \(WorkStat.displayDate(updatedAt))")
        }
        return parts.isEmpty ? "Ready to edit" : parts.joined(separator: " · ")
    }
}

/// Pure chapter merging and local store operations for `StudioWorkFilesView`.
nonisolated enum StudioWorkFilesLogic {
    enum MoveDirection: Equatable, Sendable {
        case up
        case down
    }

    static func mergeChapters(
        localWorkID: UUID?,
        localChapters: [WritingChapter],
        ao3WorkID: Int?,
        ao3Chapters: [AO3ChapterRef],
        isAO3DraftWork: Bool,
        ao3DraftWordCount: Int? = nil,
        ao3DraftDateText: String? = nil
    ) -> [StudioWorkChapterItem] {
        var matchedLocalIDs: Set<UUID> = []
        var result: [StudioWorkChapterItem] = []

        for ref in ao3Chapters {
            let matchedLocal = localChapters.first { $0.ao3ChapterID == ref.id }
            if let matchedLocal { matchedLocalIDs.insert(matchedLocal.id) }
            let status: StudioChapterBadgeStatus = if let matchedLocal {
                badgeStatus(for: matchedLocal)
            } else {
                ref.dateText.isEmpty && isAO3DraftWork ? .ao3Draft : .posted
            }
            let cleanedTitle = cleanedAO3ChapterTitle(ref.title, position: ref.position)
            let title = matchedLocal.flatMap {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.title
            } ?? cleanedTitle

            result.append(StudioWorkChapterItem(
                id: "ao3-ch-\(ref.id)",
                position: result.count + 1,
                title: title,
                badge: status,
                wordCount: matchedLocal?.wordCount,
                dateText: ref.dateText.isEmpty ? nil : ref.dateText,
                updatedAt: matchedLocal?.updatedAt,
                localWorkID: matchedLocal != nil ? localWorkID : nil,
                localChapterID: matchedLocal?.id,
                ao3WorkID: ao3WorkID,
                ao3ChapterID: ref.id
            ))
        }

        for local in localChapters where !matchedLocalIDs.contains(local.id) {
            result.append(StudioWorkChapterItem(
                id: "local-ch-\(local.id.uuidString)",
                position: result.count + 1,
                title: local.title,
                badge: badgeStatus(for: local),
                wordCount: local.wordCount,
                dateText: nil,
                updatedAt: local.updatedAt,
                localWorkID: localWorkID,
                localChapterID: local.id,
                ao3WorkID: ao3WorkID,
                ao3ChapterID: local.ao3ChapterID
            ))
        }

        if result.isEmpty, isAO3DraftWork, let ao3WorkID {
            result.append(StudioWorkChapterItem(
                id: "ao3-draft-work-\(ao3WorkID)",
                position: 1,
                title: "Draft",
                badge: .ao3Draft,
                wordCount: ao3DraftWordCount,
                dateText: ao3DraftDateText,
                updatedAt: nil,
                localWorkID: nil,
                localChapterID: nil,
                ao3WorkID: ao3WorkID,
                ao3ChapterID: nil
            ))
        }

        return result
    }

    static func badgeStatus(for chapter: WritingChapter) -> StudioChapterBadgeStatus {
        switch chapter.status {
        case .posted: .posted
        case .ao3Draft: .ao3Draft
        case .local: chapter.wordCount == 0 ? .planned : .onDevice
        }
    }

    static func canMove(
        chapterID: UUID,
        direction: MoveDirection,
        in localChapters: [WritingChapter]
    ) -> Bool {
        guard let index = localChapters.firstIndex(where: { $0.id == chapterID }) else {
            return false
        }
        switch direction {
        case .up: return index > 0
        case .down: return index < localChapters.count - 1
        }
    }

    static func renameChapter(
        in store: WritingDocumentStore,
        workID: UUID,
        chapterID: UUID,
        title: String
    ) async throws -> WritingChapter {
        let document = try await store.loadChapter(workID: workID, chapterID: chapterID)
        var updated = document.chapter
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = try await store.saveChapter(
            workID: workID,
            chapter: updated,
            bodyHTML: document.bodyHTML
        )
        return saved.chapter
    }

    static func duplicateChapter(
        in store: WritingDocumentStore,
        workID: UUID,
        chapterID: UUID
    ) async throws -> WritingChapter {
        let source = try await store.loadChapter(workID: workID, chapterID: chapterID)
        let workBefore = try await store.openWork(workID)
        let baseTitle = source.chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let copyTitle = baseTitle.isEmpty ? "Copy" : "\(baseTitle) Copy"

        var copy = try await store.addChapter(workID: workID, title: copyTitle)
        copy.summary = source.chapter.summary
        copy.notesBefore = source.chapter.notesBefore
        copy.notesAfter = source.chapter.notesAfter
        copy.status = .local
        copy.ao3ChapterID = nil
        let saved = try await store.saveChapter(
            workID: workID,
            chapter: copy,
            bodyHTML: source.bodyHTML
        )

        if let sourceIndex = workBefore.chapterOrder.firstIndex(of: chapterID) {
            var nextOrder = workBefore.chapterOrder
            nextOrder.insert(saved.chapter.id, at: sourceIndex + 1)
            _ = try await store.reorderChapters(workID: workID, order: nextOrder)
        }
        return saved.chapter
    }

    static func moveChapter(
        in store: WritingDocumentStore,
        workID: UUID,
        chapterID: UUID,
        direction: MoveDirection
    ) async throws -> WritingWork {
        let work = try await store.openWork(workID)
        guard let index = work.chapterOrder.firstIndex(of: chapterID) else {
            throw WritingDocumentError.chapterNotFound(chapterID)
        }
        let targetIndex = direction == .up ? index - 1 : index + 1
        guard work.chapterOrder.indices.contains(targetIndex) else { return work }
        var order = work.chapterOrder
        order.swapAt(index, targetIndex)
        return try await store.reorderChapters(workID: workID, order: order)
    }

    static func deleteChapter(
        in store: WritingDocumentStore,
        workID: UUID,
        chapterID: UUID
    ) async throws {
        try await store.deleteChapter(workID: workID, chapterID: chapterID)
    }

    static func storyNoteKindTitle(_ kind: WritingStoryNoteKind) -> String {
        switch kind {
        case .character: "Character"
        case .place: "Place"
        case .canon: "Canon"
        case .timeline: "Timeline"
        case .other: "Note"
        }
    }

    private static func cleanedAO3ChapterTitle(_ title: String, position: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "Chapter \(position)" { return "" }
        return trimmed
    }
}
