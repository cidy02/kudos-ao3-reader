import Foundation

/// How a copy of a work first reached the library (Insights D8, "How Finished Works Arrived").
///
/// One fact, stored once on the work (`SavedWork.importSourceRaw`). T-528's queue membership
/// origin (`ReadingQueueMembershipOrigin`) is the same fact seen from a queue, so a queue add
/// maps onto this enum (`init(origin:)`) instead of keeping a second taxonomy. Raw values are
/// the board's strings and travel in backups; a value this build does not know is kept as
/// written and shown as `unknown` (`init(storedRaw:)`).
nonisolated enum WorkImportSource: String, CaseIterable, Codable, Sendable {
    case search
    case browse
    case fandom
    case author
    case series
    case subscription
    case markedForLater
    case ao3History
    case shareSheet
    case pastedLink
    case fileImport
    case backupRestore
    case unknown

    /// Card-sized name for the "How Finished Works Arrived" figure.
    var label: String {
        switch self {
        case .search: "Search"
        case .browse: "Browsing"
        case .fandom: "A fandom page"
        case .author: "An author page"
        case .series: "A series"
        case .subscription: "A subscription"
        case .markedForLater: "Marked for Later"
        case .ao3History: "AO3 History"
        case .shareSheet: "Share sheet"
        case .pastedLink: "A pasted link"
        case .fileImport: "A file"
        case .backupRestore: "A backup"
        case .unknown: "Somewhere else"
        }
    }

    /// The queue-membership origin (T-528) as an import source. A manual add says nothing
    /// about where the work was found, so it maps to nil and the import path decides.
    init?(origin: ReadingQueueMembershipOrigin?) {
        guard let origin else { return nil }
        if let hint = origin.importSourceHint {
            self = hint
            return
        }
        switch origin.kind {
        case .search, .source: self = .search
        case .link: self = .pastedLink
        case .manual: return nil
        }
    }

    /// A stored raw string as a source: nil for "never recorded", `.unknown` for a value an
    /// older or newer build wrote that this one has no case for.
    init?(storedRaw: String?) {
        guard let storedRaw, !storedRaw.isEmpty else { return nil }
        self = Self(rawValue: storedRaw) ?? .unknown
    }
}

/// AO3's figures for a work at the moment it was first saved (Insights D9, "Found Early").
nonisolated struct WorkStatsAtSave: Equatable, Sendable {
    var kudos: Int?
    var hits: Int?
    var bookmarks: Int?
    var fandomWorks: Int?

    var isEmpty: Bool { kudos == nil && hits == nil && bookmarks == nil }

    /// The blurb's figures plus, when the save came from a fandom page that had loaded that
    /// fandom's total, the fandom's size. Used only when the page's fandom is one the work is in.
    init(summary: AO3WorkSummary, origin: ReadingQueueMembershipOrigin?) {
        let fandom = origin?.label?.lowercased()
        let matches = origin?.importSourceHint == .fandom
            && fandom.map { name in summary.fandoms.contains { $0.lowercased() == name } } == true
        self.init(summary: summary, fandomWorks: matches ? origin?.fandomWorks : nil)
    }

    /// The figures a search or listing blurb printed: AO3's own at the time of the save.
    init(summary: AO3WorkSummary, fandomWorks: Int? = nil) {
        self.init(
            kudos: summary.kudos, hits: summary.hits, bookmarks: summary.bookmarks, fandomWorks: fandomWorks
        )
    }

    init(kudos: Int?, hits: Int?, bookmarks: Int?, fandomWorks: Int?) {
        self.kudos = kudos
        self.hits = hits
        self.bookmarks = bookmarks
        self.fandomWorks = fandomWorks
    }
}

extension SavedWork {
    /// How long a work counts as "just saved" for the first stats a metadata fetch brings
    /// (D9). The import itself carries no kudos or hits, so the refresh that follows seconds
    /// later is the first time AO3's figures are seen; a refresh after this window is "now",
    /// and must never become "when saved".
    nonisolated static let saveStatsWindow: TimeInterval = 15 * 60

    /// AO3 prints a posting date as a calendar day with no zone; `WorkStat.date(from:)` reads
    /// it as midnight GMT, so ages are counted in GMT days too.
    nonisolated static let postingCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    // MARK: D8

    var importSource: WorkImportSource? {
        WorkImportSource(storedRaw: importSourceRaw)
    }

    /// Sets the arrival path once, when the work is created. A recorded path is never
    /// replaced: a second import of the same work, a restore or a refresh says nothing
    /// new about how it first arrived. `nil` means "this path does not know": it records
    /// `.unknown`, so the "since" date still marks when recording began.
    @discardableResult
    func recordImportSource(_ source: WorkImportSource?, at date: Date = Date()) -> Bool {
        guard importSourceRaw == nil else { return false }
        importSourceRaw = (source ?? .unknown).rawValue
        importSourceSince = date
        return true
    }

    /// A work created from a remote blurb: how it arrived (D8) and AO3's figures from that
    /// same blurb (D9). Set once; a work that already has either is left as it was.
    func recordArrival(
        source: WorkImportSource?,
        summary: AO3WorkSummary? = nil,
        origin: ReadingQueueMembershipOrigin? = nil,
        at date: Date = Date()
    ) {
        recordImportSource(source, at: date)
        if let summary { recordStatsAtSave(WorkStatsAtSave(summary: summary, origin: origin), at: date) }
    }

    // MARK: D9

    /// Writes the at-save figures once. Fields already recorded stay; `ageDaysAtSave`
    /// comes from the posting date as AO3 printed it, and is left empty when it did not parse.
    @discardableResult
    func recordStatsAtSave(
        _ stats: WorkStatsAtSave,
        at date: Date = Date(),
        calendar: Calendar = SavedWork.postingCalendar
    ) -> Bool {
        guard statsSavedAt == nil, !stats.isEmpty else { return false }
        kudosAtSave = stats.kudos.map { max(0, $0) }
        hitsAtSave = stats.hits.map { max(0, $0) }
        bookmarksAtSave = stats.bookmarks.map { max(0, $0) }
        fandomWorksAtSave = stats.fandomWorks.map { max(0, $0) }
        statsSavedAt = date
        // The age is the work's age on the day it was saved (`dateAdded`), not on the day a
        // refresh happened to see its figures: a window that crosses midnight must not add a day.
        if let published = WorkStat.date(from: datePublished) {
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: published), to: calendar.startOfDay(for: dateAdded)
            ).day
            ageDaysAtSave = days.map { max(0, $0) }
        }
        return true
    }

    /// A metadata fetch that just brought AO3's figures. Records them as "when saved" only
    /// while the work is new (`saveStatsWindow` after `dateAdded`) and nothing was recorded;
    /// a later refresh returns false and leaves the at-save fields alone.
    @discardableResult
    func recordStatsAtSaveIfJustSaved(
        kudos: Int?,
        hits: Int?,
        bookmarks: Int?,
        now: Date = Date(),
        calendar: Calendar = SavedWork.postingCalendar
    ) -> Bool {
        // Only a work this build created (it recorded how it arrived) is eligible: a work saved
        // before recording began must never gain an at-save snapshot from a later refresh. The
        // elapsed time must also be inside the window and not negative (a future `dateAdded`).
        guard statsSavedAt == nil, importSourceRaw != nil,
              (0 ... Self.saveStatsWindow).contains(now.timeIntervalSince(dateAdded))
        else { return false }
        return recordStatsAtSave(
            WorkStatsAtSave(kudos: kudos, hits: hits, bookmarks: bookmarks, fandomWorks: nil),
            at: now,
            calendar: calendar
        )
    }

    /// Fills the age at save from the posting date once the work page brings it, for a work
    /// whose blurb carried none. The age is measured to `dateAdded`, so it stays the age
    /// at save however late the date arrives. Touches no other at-save field.
    @discardableResult
    func completeAgeAtSave(calendar: Calendar = SavedWork.postingCalendar) -> Bool {
        guard ageDaysAtSave == nil, statsSavedAt != nil,
              let published = WorkStat.date(from: datePublished),
              let days = calendar.dateComponents(
                  [.day], from: calendar.startOfDay(for: published), to: calendar.startOfDay(for: dateAdded)
              ).day
        else { return false }
        ageDaysAtSave = max(0, days)
        return true
    }
}

extension ReadingQueueMembershipOrigin {
    /// A fandom page's loaded total describes the fandom only while the list is that fandom's own:
    /// one fandom, no filter beyond it (D9). Anything else carries no size.
    static func fandomTotal(_ total: Int?, filtered: Bool, fandomCount: Int) -> Int? {
        filtered || fandomCount != 1 ? nil : total
    }
}
