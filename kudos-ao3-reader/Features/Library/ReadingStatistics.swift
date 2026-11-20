import Foundation
import SwiftData

/// Local-only reading insights derived from the Library's `SavedWork` records.
/// The app does not track sessions or per-word progress, so "words read" counts
/// only finished works whose AO3 word count is known.
struct ReadingStatistics {
    struct FandomCount: Identifiable, Equatable {
        let name: String
        let count: Int

        var id: String {
            name
        }
    }

    let totalWorks: Int
    let startedWorks: Int
    let finishedWorks: Int
    let inProgressWorks: Int
    let wordsRead: Int
    let openedLast7Days: Int
    let openedLast30Days: Int
    let latestReadDate: Date?
    let topFandoms: [FandomCount]

    var completionRate: Double {
        guard startedWorks > 0 else { return 0 }
        return Double(finishedWorks) / Double(startedWorks)
    }

    init(
        works: [SavedWork],
        now: Date = Date(),
        calendar: Calendar = .current,
        aliases: TagAliasResolver = .empty
    ) {
        var started: [SavedWork] = []
        for work in works where Self.hasStarted(work) {
            started.append(work)
        }
        let finished = works.filter(\.isFinished)
        let inProgress = started.filter { !$0.isFinished }

        totalWorks = works.count
        startedWorks = started.count
        finishedWorks = finished.count
        inProgressWorks = inProgress.count
        wordsRead = finished.filter { $0.wordUnit == .words }.reduce(0) { total, work in
            total + max(0, work.wordCount)
        }
        latestReadDate = works.compactMap(\.lastReadDate).max()

        let startOfToday = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: startOfToday)
            ?? startOfToday
        let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: startOfToday)
            ?? startOfToday
        openedLast7Days = Self.countOpened(works, since: sevenDayStart, through: now)
        openedLast30Days = Self.countOpened(works, since: thirtyDayStart, through: now)
        topFandoms = Self.fandomCounts(in: started, aliases: aliases)
    }

    /// Finished counts as started even when the progress fields were reset. Defers
    /// to the model's canonical `hasStartedReading` — a private re-listing of its
    /// fields here once drifted (it missed the Readium reader's locator, undercounting
    /// works read only on iOS).
    private static func hasStarted(_ work: SavedWork) -> Bool {
        work.isFinished || work.hasStartedReading
    }

    private static func countOpened(
        _ works: [SavedWork],
        since start: Date,
        through end: Date
    ) -> Int {
        works.reduce(into: 0) { count, work in
            guard let date = work.lastReadDate, date >= start, date <= end else { return }
            count += 1
        }
    }

    private static func fandomCounts(
        in works: [SavedWork],
        aliases: TagAliasResolver = .empty
    ) -> [FandomCount] {
        var counts: [String: Int] = [:]
        for work in works {
            let uniqueFandoms = aliases.resolvedUnique(work.workFandoms, kind: .fandom)
            for fandom in uniqueFandoms {
                counts[fandom, default: 0] += 1
            }
        }
        return counts
            .map(FandomCount.init(name:count:))
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

/// Figures for Home's stats line under the title (T-487):
/// "4 h 10 m this week · 2 finished · 9-day streak"
struct HomeReadingStats: Equatable, Sendable {
    var durationSeconds: Double
    var finishedCount: Int
    var streakDays: Int

    init(durationSeconds: Double = 0, finishedCount: Int = 0, streakDays: Int = 0) {
        self.durationSeconds = durationSeconds
        self.finishedCount = finishedCount
        self.streakDays = streakDays
    }

    /// "4 h 10 m", "35 m", "2 h", or "0 m"
    var formattedDuration: String {
        let totalMinutes = Int((max(0, durationSeconds) / 60).rounded())
        if totalMinutes < 60 {
            return "\(totalMinutes) m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) m"
    }

    /// "4 hours 10 minutes" for VoiceOver
    var spokenDuration: String {
        let totalMinutes = Int((max(0, durationSeconds) / 60).rounded())
        guard totalMinutes > 0 else { return "0 minutes" }
        var parts: [String] = []
        if totalMinutes >= 60 {
            let h = totalMinutes / 60
            parts.append("\(h) hour\(h == 1 ? "" : "s")")
        }
        let m = totalMinutes % 60
        if m > 0 {
            parts.append("\(m) minute\(m == 1 ? "" : "s")")
        }
        return parts.joined(separator: " ")
    }

    /// "9-day"
    var formattedStreak: String {
        "\(streakDays)-day"
    }

    /// Spoken label for VoiceOver accessibility
    var accessibilityLabel: String {
        "\(spokenDuration) this week, \(finishedCount) finished, \(streakDays)-day streak"
    }

    /// Calculates the weekly duration, works finished this week, and current streak
    /// from reading session facts.
    static func calculate(
        facts: [ReadingSessionFacts],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HomeReadingStats {
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let weekFacts = facts.filter { fact in
            guard let weekInterval else { return false }
            return weekInterval.contains(fact.startedAt)
        }
        let durationSeconds = weekFacts.reduce(0) { $0 + $1.durationSeconds }
        let finishedCount = Set(weekFacts.filter(\.didFinish).map(\.workID)).count
        let streakDays = ReadingHistoryTimeline.streak(
            through: now,
            isToday: true,
            facts: facts,
            calendar: calendar
        )
        return HomeReadingStats(
            durationSeconds: durationSeconds,
            finishedCount: finishedCount,
            streakDays: streakDays
        )
    }

    /// Library and Home Reading Insights visible work filter.
    /// Excludes queue-only works and concealed mature works (whether in Hide or Blur mode).
    static func insightsWorks(
        from works: [SavedWork],
        gate: PrivacyGate,
        hideMature: Bool
    ) -> [SavedWork] {
        works.filter { !$0.isQueueOnlyWork && !gate.isConcealed($0, enabled: hideMature) }
    }

    /// The works Insights' Hidden section holds: every adult-rated work while Hide Mature
    /// is on, whatever has been revealed this session, so the main figures do not change
    /// when the gate opens. Queue-only works are not singled out: their reading counts
    /// (owner, 2026-11-19). Needs the UNFILTERED library: on an already-filtered list it
    /// is always empty.
    static func insightsHiddenWorkIDs(
        from libraryWorks: [SavedWork],
        hideMature: Bool
    ) -> Set<UUID> {
        guard hideMature else { return [] }
        return Set(libraryWorks.lazy.filter(\.isAdult).map(\.id))
    }

    /// Adult-rated works sitting in Recently Deleted (`isPendingDeletion == true`).
    /// Needed so pre-D1 sessions (blank snapshot rating) of soft-deleted mature works
    /// still classify as hidden while locked and appear in Hidden when revealed.
    @MainActor
    static func softDeletedAdultWorkIDs(in context: ModelContext) -> Set<UUID> {
        let deleted = (try? context.fetch(
            FetchDescriptor<SavedWork>(predicate: #Predicate { $0.isPendingDeletion })
        )) ?? []
        return Set(deleted.lazy.filter(\.isAdult).map(\.id))
    }

    /// Whether Library's `•••` menu offers "Reading Insights": whenever the user has
    /// any live work (saved, queue-only, or mature-only) or any recorded reading
    /// sessions, independent of the privacy gate so toggling Show Mature neither
    /// hides the entry nor leaks library composition.
    static func showsReadingInsightsMenuEntry(
        liveWorkCount: Int,
        sessionCount: Int
    ) -> Bool {
        liveWorkCount > 0 || sessionCount > 0
    }

    /// What one Insights scope counts. `revealed` is `PrivacyGate.revealAll`: while it is
    /// false the Hidden scope is empty and the combined scope is the main one, so nothing
    /// hidden is computed or exported.
    static func insightsScope(
        _ scope: InsightsScope,
        from libraryWorks: [SavedWork],
        hideMature: Bool,
        revealed: Bool
    ) -> InsightsScopeSelection {
        let hidden = insightsHiddenWorkIDs(from: libraryWorks, hideMature: hideMature)
        let liveWorks = libraryWorks.filter { !$0.isPendingDeletion }
        let liveIDs = Set(liveWorks.map(\.id))
        switch scope {
        case .hidden where !revealed:
            return InsightsScopeSelection(
                libraryWorks: [],
                readingWorks: [],
                excludedWorkIDs: [],
                onlyWorkIDs: [],
                scope: .hidden,
                hideMature: hideMature,
                revealed: false,
                hiddenWorkIDs: hidden,
                liveWorkIDs: liveIDs
            )
        case .hidden:
            let reading = liveWorks.filter { hidden.contains($0.id) }
            return InsightsScopeSelection(
                libraryWorks: reading.filter { !$0.isQueueOnlyWork },
                readingWorks: reading,
                excludedWorkIDs: [],
                onlyWorkIDs: hidden,
                scope: .hidden,
                hideMature: hideMature,
                revealed: true,
                hiddenWorkIDs: hidden,
                liveWorkIDs: liveIDs
            )
        case .combined where revealed:
            return InsightsScopeSelection(
                libraryWorks: liveWorks.filter { !$0.isQueueOnlyWork },
                readingWorks: liveWorks,
                excludedWorkIDs: [],
                onlyWorkIDs: nil,
                scope: .combined,
                hideMature: hideMature,
                revealed: true,
                hiddenWorkIDs: hidden,
                liveWorkIDs: liveIDs
            )
        case .main, .combined:
            let reading = liveWorks.filter { !hidden.contains($0.id) }
            return InsightsScopeSelection(
                libraryWorks: reading.filter { !$0.isQueueOnlyWork },
                readingWorks: reading,
                excludedWorkIDs: hidden,
                onlyWorkIDs: nil,
                scope: scope,
                hideMature: hideMature,
                revealed: revealed,
                hiddenWorkIDs: hidden,
                liveWorkIDs: liveIDs
            )
        }
    }

    /// Revision key for Home weekly reading stats. Incorporates the start of today
    /// so the stats recalculate across the midnight boundary.
    static func revisionKey(
        sessionCount: Int,
        newestModified: TimeInterval,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let day = calendar.startOfDay(for: now).timeIntervalSince1970
        return "\(sessionCount)|\(newestModified)|\(day)"
    }
}

/// Which reading Insights counts (owner, 2026-11-19): `main` leaves out the works Hide
/// Mature conceals, `hidden` is only those (the Hidden section), `combined` is both.
enum InsightsScope: Equatable, Sendable {
    case main
    case hidden
    case combined
}

/// The works and sittings one `InsightsScope` counts.
struct InsightsScopeSelection {
    /// Saved-library works (never queue-only): the library-inventory figures (statuses,
    /// unread backlog, WIP freshness, stopped works, preserved stats) and export statuses.
    var libraryWorks: [SavedWork]
    /// Every work whose sittings count, queue-only included: reading time, words,
    /// fandom shares, taste, habits, finished works.
    var readingWorks: [SavedWork]
    /// These works' sittings never count.
    var excludedWorkIDs: Set<UUID>
    /// When set, only these works' sittings count (the Hidden section).
    var onlyWorkIDs: Set<UUID>?
    var scope: InsightsScope = .main
    var hideMature: Bool = false
    var revealed: Bool = false
    /// Known adult-rated work IDs while `hideMature` is on (live works; augmented
    /// with soft-deleted adult works and adult-rated session snapshots at filter time).
    var hiddenWorkIDs: Set<UUID> = []
    /// Every live (not pending deletion) work, queue-only included. A live work is
    /// classified by its current rating, so a sitting's recorded rating never
    /// overrides a re-rating; snapshots only classify works no longer live.
    var liveWorkIDs: Set<UUID> = []

    /// Filters a set of sessions to this scope. Classifies sessions of deleted and
    /// soft-deleted mature works using `ModelContext` (soft-deleted `SavedWork`s)
    /// and any adult `ReadingSession.rating` snapshot for that `workID`, so every
    /// sitting of a deleted mature work stays out of locked views and lands in Hidden
    /// when revealed. A live work follows its current rating instead (`liveWorkIDs`):
    /// re-rated General/Teen, its old Explicit sittings return to main.
    @MainActor
    func sessions(
        _ all: [ReadingSession],
        in context: ModelContext? = nil
    ) -> [ReadingSession] {
        if scope == .hidden && !revealed { return [] }
        guard hideMature else {
            return all.filter { session in
                if excludedWorkIDs.contains(session.workID) { return false }
                if let onlyWorkIDs { return onlyWorkIDs.contains(session.workID) }
                return true
            }
        }
        if scope == .combined && revealed { return all }
        var allHiddenIDs = hiddenWorkIDs
        if let context {
            allHiddenIDs.formUnion(HomeReadingStats.softDeletedAdultWorkIDs(in: context))
        }
        for session in all
        where !liveWorkIDs.contains(session.workID) && MatureContentRating.isAdult(session.rating) {
            allHiddenIDs.insert(session.workID)
        }
        return scope == .hidden
            ? all.filter { allHiddenIDs.contains($0.workID) }
            : all.filter { !allHiddenIDs.contains($0.workID) }
    }
}

/// View-level scope, re-lock, subtitle and Hidden cache state for `ReadingInsightsView`.
/// Extracted so lock → reveal → Include Hidden → re-lock transitions are unit-testable
/// and never paint stale combined mature data across a re-lock.
struct ReadingInsightsScopeState {
    var includeHidden = false
    var loadedScope: InsightsScope = .main
    var hiddenInsights: ReadingInsights?
    var hiddenMasker: InsightsDiscreetMasker = .empty

    func canIncludeHidden(hideMature: Bool, revealed: Bool) -> Bool {
        hideMature && revealed
    }

    func screenScope(hideMature: Bool, revealed: Bool) -> InsightsScope {
        includeHidden && revealed && hideMature ? .combined : .main
    }

    func scopeSuffix(hideMature: Bool, revealed: Bool) -> String {
        screenScope(hideMature: hideMature, revealed: revealed) == .combined ? " · incl. hidden" : ""
    }

    /// Prevents painting stale `.combined` mature figures/titles on a render pass
    /// after the privacy gate re-locks before the synchronous reload completes.
    func mayDisplayLoadedData(hideMature: Bool, revealed: Bool) -> Bool {
        !(hideMature && !revealed && loadedScope == .combined)
    }

    /// In combined Discreet Mode, the Hidden section shares the main/combined masker
    /// so every fandom keeps one placeholder letter across the screen.
    func hiddenSectionMasker(
        mainMasker: InsightsDiscreetMasker,
        hideMature: Bool,
        revealed: Bool
    ) -> InsightsDiscreetMasker {
        screenScope(hideMature: hideMature, revealed: revealed) == .combined
            ? mainMasker
            : hiddenMasker
    }

    mutating func clearHiddenCache() {
        hiddenInsights = nil
        hiddenMasker = .empty
    }

    /// Called synchronously when `PrivacyGate.revealAll` changes.
    /// Returns `true` when the caller should reload immediately.
    @discardableResult
    mutating func handleRevealChange(revealed: Bool, hideMature: Bool) -> Bool {
        if !revealed {
            let needsReload = includeHidden || loadedScope == .combined || hiddenInsights != nil
            includeHidden = false
            clearHiddenCache()
            return needsReload
        }
        return hideMature
    }

    /// Called synchronously when `hideMatureContent` toggles.
    mutating func handleHideMatureChange(hideMature: Bool, revealed: Bool) {
        if !hideMature || !revealed {
            includeHidden = false
            clearHiddenCache()
        }
    }

    mutating func recordGather(
        scope: InsightsScope,
        hiddenInsights: ReadingInsights?,
        hiddenMasker: InsightsDiscreetMasker
    ) {
        loadedScope = scope
        self.hiddenInsights = hiddenInsights
        self.hiddenMasker = hiddenMasker
    }
}
