import Foundation
import SwiftData

/// One stretch of actually reading a work. History is keyed by `workID` (the
/// `SavedWork.id` UUID) plus denormalised identity — never a SwiftData
/// relationship — so a later soft-delete of the EPUB cannot cascade-delete the
/// log. Insights (hours, pace, words-per-hour) and History (Finished is a
/// filter) both read this table; screens must not invent a second model.
@Model final class ReadingSession {
    var id: UUID = UUID()
    /// `SavedWork.id`. Grouping key for history; never the title.
    var workID: UUID = UUID()
    var ao3WorkID: Int? = nil
    var sourceURL: String = ""
    /// Snapshot so a deleted work still has a history row.
    var workTitle: String = ""
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    /// Wall time actually reading, clamped ≥ 0. Not a raw `endedAt - startedAt`
    /// when the session was paused in the background.
    var durationSeconds: Double = 0
    var lastSpineIndex: Int = 0
    /// Publication label from the stored Readium locator (`WorkReadingPosition`).
    var chapterTitle: String = ""
    /// 0…1 at session end.
    var endingProgress: Double = 0
    /// Work word count at session end, so words-per-hour does not drift if the
    /// work is later updated on AO3.
    var wordCount: Int = 0
    /// Posted chapter count at this visit, for "changed since" (1ah).
    var chapterCountAtVisit: Int = 0
    /// True when this session ended with the work marked finished. Reread
    /// count is the count of finishing sessions.
    var didFinish: Bool = false
    var lastModifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        workID: UUID,
        ao3WorkID: Int? = nil,
        sourceURL: String = "",
        workTitle: String = "",
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Double,
        lastSpineIndex: Int = 0,
        chapterTitle: String = "",
        endingProgress: Double = 0,
        wordCount: Int = 0,
        chapterCountAtVisit: Int = 0,
        didFinish: Bool = false,
        lastModifiedAt: Date? = nil
    ) {
        self.id = id
        self.workID = workID
        self.ao3WorkID = ao3WorkID
        self.sourceURL = sourceURL
        self.workTitle = workTitle
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = max(0, durationSeconds)
        self.lastSpineIndex = lastSpineIndex
        self.chapterTitle = chapterTitle
        self.endingProgress = min(1, max(0, endingProgress))
        self.wordCount = wordCount
        self.chapterCountAtVisit = chapterCountAtVisit
        self.didFinish = didFinish
        self.lastModifiedAt = lastModifiedAt ?? endedAt
    }
}
