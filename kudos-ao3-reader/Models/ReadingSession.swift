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
    var ao3WorkID: Int?
    var sourceURL: String = ""
    /// Snapshot so a deleted work still has a history row.
    var workTitle: String = ""
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    /// Wall time actually reading, clamped ≥ 0. Not a raw `endedAt - startedAt`
    /// when the session was paused in the background.
    var durationSeconds: Double = 0
    var tzOffsetSeconds: Int? = nil
    var startProgress: Double? = nil
    var startSpineIndex: Int? = nil
    var modeRaw: String = "read"
    var playbackRate: Double? = nil
    var activeSeconds: Double? = nil
    var deviceID: String = ""
    var rulesVersion: Int = 0
    enum Mode: String, Equatable { case read, listen }
    var mode: Mode { Mode(rawValue: modeRaw) ?? .read }
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
    var fandoms: [String] = []
    var relationships: [String] = []
    var characters: [String] = []
    var freeformTags: [String] = []
    var rating: String = ""
    var warnings: [String] = []
    var categories: [String] = []
    var authorAccounts: [String] = []
    var language: String = ""
    var isCompleteAtVisit: Bool = false
    var metadataSnapshotRecorded: Bool = false
    var ao3SeriesID: Int? = nil
    var seriesPosition: Int = 0
    var publishedYear: Int? = nil

    var hasMetadataSnapshot: Bool {
        metadataSnapshotRecorded || !fandoms.isEmpty || !relationships.isEmpty || !characters.isEmpty
            || !freeformTags.isEmpty || !rating.isEmpty || !warnings.isEmpty
            || !categories.isEmpty || !authorAccounts.isEmpty || !language.isEmpty
            || isCompleteAtVisit || ao3SeriesID != nil || seriesPosition > 0
            || publishedYear != nil
    }

    func snapshot(from work: SavedWork) {
        metadataSnapshotRecorded = true
        fandoms = work.workFandoms
        relationships = work.workRelationships
        characters = work.workCharacters
        freeformTags = work.workFreeforms
        rating = work.rating
        warnings = work.workWarnings
        categories = work.workCategories
        let verified = work.verifiedAuthorIdentities.map(\.displayName)
        authorAccounts = verified.isEmpty
            ? work.author.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            : verified
        language = work.language
        isCompleteAtVisit = work.isComplete
        ao3SeriesID = work.ao3SeriesID
        seriesPosition = work.seriesPosition
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        publishedYear = WorkStat.date(from: work.datePublished).map { utc.component(.year, from: $0) }
    }
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
        tzOffsetSeconds: Int? = nil,
        startProgress: Double? = nil,
        startSpineIndex: Int? = nil,
        modeRaw: String = "read",
        playbackRate: Double? = nil,
        activeSeconds: Double? = nil,
        deviceID: String = "",
        rulesVersion: Int = 0,
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
        self.tzOffsetSeconds = tzOffsetSeconds
        self.startProgress = startProgress
        self.startSpineIndex = startSpineIndex
        self.modeRaw = modeRaw
        self.playbackRate = playbackRate
        self.activeSeconds = activeSeconds
        self.deviceID = deviceID
        self.rulesVersion = rulesVersion
        self.lastSpineIndex = lastSpineIndex
        self.chapterTitle = chapterTitle
        self.endingProgress = min(1, max(0, endingProgress))
        self.wordCount = wordCount
        self.chapterCountAtVisit = chapterCountAtVisit
        self.didFinish = didFinish
        self.lastModifiedAt = lastModifiedAt ?? endedAt
    }
}
