import Foundation

/// Local manuscripts for the Writing Studio (T-574a).
///
/// One folder per work under Application Support `Writing/`. AO3 ids are optional,
/// so a document exists with no account. Annotations are private: nothing in this
/// module posts them. Every record carries `updatedAt` and `updatedBy` (this
/// install's device id) so a later sync can stamp the file without a migration.
/// `bodySavedAt` is the chapter-text clock for the ten-minute version rule; a
/// title or notes edit does not move it.

nonisolated enum WritingDocumentError: Error, Equatable {
    case workNotFound(UUID)
    case chapterNotFound(UUID)
    case versionNotFound(UUID)
    case storyNoteNotFound(UUID)
    case annotationNotFound(UUID)
    case notInRecentlyDeleted(UUID)
    case chapterOrderMismatch
    case invalidAnchor
    case corrupt(String)
}

nonisolated enum WritingChapterStatus: String, Codable, Sendable {
    case local
    case ao3Draft
    case posted
}

/// Why a chapter save is happening. Destructive saves always keep the previous text.
nonisolated enum WritingChapterSaveKind: Sendable {
    /// Snapshot the previous body only when this is the first text save in ten minutes.
    case edit
    /// Replacing the text from outside the editor: paste-report undo, a beta's copy,
    /// or restoring an older version. The previous body is kept for 30 days.
    case destructive
}

nonisolated enum WritingVersionCause: String, Codable, Sendable {
    case automatic
    case destructive
}

nonisolated enum WritingStoryNoteKind: String, Codable, Sendable {
    case character
    case place
    case canon
    case timeline
    case other
}

nonisolated enum WritingAnnotationKind: String, Codable, Sendable {
    case note
    case tk
}

nonisolated struct WritingWork: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var ao3WorkID: Int?
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var chapterOrder: [UUID]
}

nonisolated struct WritingChapter: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var summary: String
    var notesBefore: String
    var notesAfter: String
    var ao3ChapterID: Int?
    var status: WritingChapterStatus
    /// AO3's word count of `body.html`, so a chapter list does not reread the text.
    var wordCount: Int
    /// When `body.html` was last written. The ten-minute rule reads this, not `updatedAt`.
    var bodySavedAt: Date
    var updatedAt: Date
    var updatedBy: String
}

nonisolated struct WritingChapterDocument: Equatable, Sendable {
    var chapter: WritingChapter
    var bodyHTML: String
}

nonisolated struct WritingChapterVersion: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var cause: WritingVersionCause
    var updatedAt: Date
    var updatedBy: String
}

nonisolated struct WritingStoryNote: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var kind: WritingStoryNoteKind
    var name: String
    var detail: String
    var pinned: Bool
    var updatedAt: Date
    var updatedBy: String
}

/// A private note anchored in `body.html`. The quote is a slice of that HTML, tags
/// included. `utf16Offset` is only a hint: placement uses the quote, then the
/// prefix and suffix.
nonisolated struct WritingAnnotation: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var chapterID: UUID
    var quote: String
    var prefix: String
    var suffix: String
    var utf16Offset: Int
    var text: String
    var createdAt: Date
    var resolvedAt: Date?
    var kind: WritingAnnotationKind
    var updatedAt: Date
    var updatedBy: String

    var anchor: WritingAnnotationAnchor {
        WritingAnnotationAnchor(quote: quote, prefix: prefix, suffix: suffix, utf16Offset: utf16Offset)
    }
}

nonisolated struct WritingAnnotationAnchor: Equatable, Sendable {
    var quote: String
    var prefix: String
    var suffix: String
    var utf16Offset: Int
}

nonisolated enum WritingReanchorOutcome: Equatable, Sendable {
    case placed(WritingAnnotationAnchor)
    case lost
}

nonisolated struct WritingStoryNotesFile: Codable, Equatable, Sendable {
    var notes: [WritingStoryNote]
}

nonisolated struct WritingAnnotationsFile: Codable, Equatable, Sendable {
    var annotations: [WritingAnnotation]
}

nonisolated struct WritingDeletionMarker: Codable, Equatable, Sendable {
    var deletedAt: Date
    var updatedAt: Date
    var updatedBy: String
    var workID: UUID?
    var chapterIndex: Int?
}

nonisolated struct WritingDeletedItem: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case work
        /// `workID` is nil only when a crashed delete left the chapter with no marker.
        case chapter(workID: UUID?)
    }

    var id: UUID
    var kind: Kind
    var title: String
    var deletedAt: Date
}

nonisolated struct WritingAnnotationReanchorReport: Equatable, Sendable {
    var placed: [WritingAnnotation]
    var lost: [WritingAnnotation]
}
