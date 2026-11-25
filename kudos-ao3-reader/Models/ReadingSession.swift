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
    /// D7: seconds of active reading in each chapter this sitting, `{"<spineIndex>": seconds}`.
    /// nil = not recorded (older rows, Android, a sitting with no chapter signal).
    var chapterSecondsJSON: String? = nil
    /// D7: words in each chapter the sitting read whole (entered from the one before and
    /// left for the one after), `{"<spineIndex>": words}`. Only chapters whose count was
    /// known in words; the pace and skim judgements read these.
    var chapterWordsJSON: String? = nil
    /// D7: spine indexes judged skimmed when the sitting was saved (`ChapterTiming`), as a JSON
    /// `[Int]`. Stored, so a later change of pace never re-judges a past sitting. nil = not judged.
    var skimmedChaptersJSON: String? = nil
    /// D7: whether the sitting stopped at the end of a chapter. nil = not recorded.
    var endedAtChapterEnd: Bool? = nil
    /// D7: whether the sitting jumped to the work's last chapter before the halfway mark.
    var peekedAtEnding: Bool? = nil

    /// D7: the same judgement by AO3 story chapter (1-based), so the words-read calculator, which
    /// knows chapters and not spine items, can leave a skimmed chapter's coverage uncredited.
    var skimmedStoryChaptersJSON: String? = nil

    var skimmedStoryChapters: [Int] {
        get { ChapterTiming.decodeList(skimmedStoryChaptersJSON) }
        set { skimmedStoryChaptersJSON = ChapterTiming.encode(list: newValue) }
    }

    var chapterSeconds: [Int: Double] {
        get { ChapterTiming.decodeDoubles(chapterSecondsJSON) }
        set { chapterSecondsJSON = ChapterTiming.encode(newValue) }
    }

    var chapterWords: [Int: Int] {
        get { ChapterTiming.decodeInts(chapterWordsJSON) }
        set { chapterWordsJSON = ChapterTiming.encode(newValue) }
    }

    var skimmedChapters: [Int] {
        get { ChapterTiming.decodeList(skimmedChaptersJSON) }
        set { skimmedChaptersJSON = ChapterTiming.encode(list: newValue) }
    }

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
        // Only a registered AO3 username is an account. A byline may be an
        // anonymous/orphan pseud, so never turn that text into an author account.
        authorAccounts = Array(Set(work.verifiedAuthorIdentities.compactMap { identity -> String? in
            guard identity.kind == .registered, let username = identity.username,
                  !username.isEmpty, username != "orphan_account" else { return nil }
            return username
        })).sorted()
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
