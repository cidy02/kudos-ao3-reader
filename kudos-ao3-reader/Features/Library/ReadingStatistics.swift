import Foundation

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
        calendar: Calendar = .current
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
        wordsRead = finished.reduce(0) { total, work in
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
        topFandoms = Self.fandomCounts(in: started)
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

    private static func fandomCounts(in works: [SavedWork]) -> [FandomCount] {
        var counts: [String: Int] = [:]
        for work in works {
            let uniqueFandoms = Set(work.workFandoms.compactMap { raw -> String? in
                let fandom = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return fandom.isEmpty ? nil : fandom
            })
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
