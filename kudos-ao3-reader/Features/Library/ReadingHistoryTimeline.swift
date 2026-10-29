import Foundation

/// Reading History's Week / Month / Year control (T-462; board 02, and the older
/// History-Month and History-Year boards).
nonisolated enum ReadingHistoryScope: String, CaseIterable, Hashable, Sendable {
    case week
    case month
    case year

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    /// The unit one period spans, in the reader's calendar: a week starts on
    /// their first weekday, as Reading Insights' week bars do.
    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// One bar or cell of the scope's chart: a day for Week and Month, a month
    /// for Year.
    var bucketComponent: Calendar.Component {
        self == .year ? .month : .day
    }
}

/// Everything Reading History draws for one period, from the reading log alone.
///
/// Plain values over `ReadingSessionFacts`, like `ReadingInsights`: which day a
/// sitting belongs to, where a streak breaks and which chapters a sitting read
/// are rules, and a rule you can hand fixtures to is a rule you can check.
///
/// **A sitting belongs to the day it started**, whole — the rule Insights' week
/// bars already use. A sitting from 23:30 to 00:40 is the evening's, and its time
/// is not split across midnight: `durationSeconds` leaves out pauses, so the log
/// does not know how much of it fell on either side.
nonisolated struct ReadingHistoryTimeline: Equatable, Sendable {
    var scope: ReadingHistoryScope
    var period: DateInterval
    /// The period holds `now`: there is no next period to step to, and today
    /// does not break the streak before it is over.
    var isCurrent: Bool
    var totalSeconds: Double = 0
    /// Distinct works read in the period.
    var workCount: Int = 0
    /// Distinct works finished in the period: works, not finishing sittings, for
    /// the reason `ReadingInsights.finishRate` gives.
    var finishedCount: Int = 0
    var wordsRead: Int = 0
    /// Consecutive days with reading up to the period's last day (today, for the
    /// current period). It may begin before the period does.
    var streakDays: Int = 0
    /// The longest run inside the period (History-Year's "Longest streak").
    var longestStreakDays: Int = 0
    /// Days in the period with reading, of the days of it that have begun
    /// (History-Month's "read on 24 of 28 days").
    var daysRead: Int = 0
    var daysElapsed: Int = 0
    /// The chart, oldest first: every day of a week or month, every month of a year.
    var buckets: [Bucket] = []
    /// Newest day first, each day's sittings newest first.
    var days: [Day] = []
    /// The period's works by time read, most first (History-Month's "Most Read").
    var mostRead: [WorkTime] = []
    var topFandom: String?
    var longestFinishedWordCount: Int = 0
    var favouriteTime: TimeOfDay?

    nonisolated struct Bucket: Equatable, Sendable, Identifiable {
        var start: Date
        var seconds: Double = 0
        /// Distinct works finished in this bucket (History-Year's bars).
        var finishedCount: Int = 0
        /// Not begun yet: drawn empty and left out of the average.
        var isFuture: Bool = false
        var id: Date { start }
    }

    nonisolated struct Day: Equatable, Sendable, Identifiable {
        var start: Date
        var sittings: [Sitting]
        var totalSeconds: Double { sittings.reduce(0) { $0 + $1.durationSeconds } }
        var id: Date { start }
    }

    nonisolated struct Sitting: Equatable, Sendable, Identifiable {
        var id: UUID
        var workID: UUID
        var title: String
        var fandom: String
        var startedAt: Date
        var durationSeconds: Double
        var endingProgress: Double
        var didFinish: Bool
        /// The first sitting of a read-through: the work's first, or the first
        /// after a sitting that finished it.
        var beginsReadThrough: Bool
        /// 1 the first time through the work, 2 on the reread, …
        var readThrough: Int
        /// `nil` when the log does not know how many chapters the work had.
        var chapters: ChapterSpan?

        /// Finished wins: a one-sitting read both starts and finishes the work,
        /// and finishing is the news.
        var badge: Badge? {
            if didFinish { return .finished }
            return beginsReadThrough ? .started : nil
        }

        /// Board 02's "Chapters 3–4 · 35 min · 58% through".
        var detailLine: String {
            var parts: [String] = []
            if let chapters { parts.append(chapters.label) }
            parts.append(ReadingInsights.durationLabel(durationSeconds))
            if !didFinish, endingProgress > 0 {
                parts.append("\(Int((min(1, endingProgress) * 100).rounded()))% through")
            }
            if readThrough > 1 {
                let ordinal = NumberFormatter.localizedString(from: NSNumber(value: readThrough), number: .ordinal)
                parts.append("\(ordinal) read")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// A sitting's chapters as board 02's cells: read before, this sitting, to come.
    ///
    /// Derived from where the sitting started and ended in the work (0…1) over
    /// its chapter count, because the log keeps positions rather than chapter
    /// numbers. Exact for evenly sized chapters and close otherwise — the cells
    /// are a picture of how far through the work the sitting went.
    nonisolated struct ChapterSpan: Equatable, Sendable {
        var total: Int
        var first: Int
        var last: Int

        var readBefore: Int { first - 1 }
        var thisSitting: Int { last - first + 1 }
        var toCome: Int { total - last }

        /// "One-shot", "Chapter 6 of 12", "Chapters 6–7 of 12".
        var label: String {
            if total == 1 { return "One-shot" }
            if first == last { return "Chapter \(first) of \(total)" }
            return "Chapters \(first)–\(last) of \(total)"
        }

        /// What VoiceOver reads for the cells.
        var accessibilityLabel: String {
            if total == 1 { return "One-shot, read in this sitting" }
            return "\(label), read in this sitting"
        }

        static func make(total: Int, start: Double, end: Double, finished: Bool) -> ChapterSpan? {
            guard total > 0 else { return nil }
            let count = Double(total)
            // A hair of slack either way so 5/12 × 12 lands on 5, not 4.999….
            let before = Int((min(1, max(0, start)) * count + 1e-9).rounded(.down))
            let first = min(total, before + 1)
            let reached = finished
                ? total
                : min(total, max(1, Int((min(1, max(0, end)) * count - 1e-9).rounded(.up))))
            // A sitting that went back still read the chapter it was in.
            return ChapterSpan(total: total, first: first, last: max(first, reached))
        }
    }

    nonisolated enum Badge: Equatable, Sendable {
        case finished
        case started

        var title: String {
            switch self {
            case .finished: "Finished"
            case .started: "Started"
            }
        }
    }

    nonisolated struct WorkTime: Equatable, Sendable, Identifiable {
        var workID: UUID
        var title: String
        var fandom: String
        var seconds: Double
        var id: UUID { workID }
    }

    /// History-Year's "Favourite time", by time read.
    nonisolated enum TimeOfDay: CaseIterable, Equatable, Sendable {
        case morning
        case afternoon
        case evening
        case night

        var title: String {
            switch self {
            case .morning: "Mornings"
            case .afternoon: "Afternoons"
            case .evening: "Evenings"
            case .night: "After 10 pm"
            }
        }

        static func of(hour: Int) -> TimeOfDay {
            switch hour {
            case 5..<12: .morning
            case 12..<17: .afternoon
            case 17..<22: .evening
            default: .night
            }
        }
    }

    // MARK: Building

    /// The period of `scope` holding `reference`, built from `facts`.
    ///
    /// `facts` is **every** sitting of the works on the page, not only this
    /// period's: where a sitting started, whether it began a read-through and
    /// how long the streak runs all look back past the period's first day.
    static func make(
        scope: ReadingHistoryScope,
        containing reference: Date,
        facts: [ReadingSessionFacts],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReadingHistoryTimeline {
        let period = calendar.dateInterval(of: scope.component, for: reference)
            ?? DateInterval(start: calendar.startOfDay(for: reference), duration: 86_400)
        var timeline = ReadingHistoryTimeline(
            scope: scope, period: period, isCurrent: period.start <= now && now < period.end
        )

        let starts = ReadingInsights.startingProgress(of: facts)
        let throughs = readThroughs(of: facts)
        // Half-open, so a sitting at the stroke of the next period is only in that one.
        let inPeriod = facts.indices.filter {
            period.start <= facts[$0].startedAt && facts[$0].startedAt < period.end
        }
        let periodFacts = inPeriod.map { facts[$0] }
        let sittings = inPeriod.map { index in
            let fact = facts[index]
            return Sitting(
                id: fact.sessionID ?? UUID(),
                workID: fact.workID,
                title: fact.title,
                fandom: fact.fandom,
                startedAt: fact.startedAt,
                durationSeconds: fact.durationSeconds,
                endingProgress: fact.endingProgress,
                didFinish: fact.didFinish,
                beginsReadThrough: throughs[index].begins,
                readThrough: throughs[index].count,
                chapters: ChapterSpan.make(
                    total: fact.chapterCount, start: starts[index], end: fact.endingProgress,
                    finished: fact.didFinish
                )
            )
        }

        timeline.totalSeconds = sittings.reduce(0) { $0 + $1.durationSeconds }
        timeline.workCount = Set(sittings.map(\.workID)).count
        timeline.finishedCount = Set(sittings.filter(\.didFinish).map(\.workID)).count
        timeline.wordsRead = periodFacts.reduce(0) { $0 + $1.wordsRead }
        timeline.days = Dictionary(grouping: sittings) { calendar.startOfDay(for: $0.startedAt) }
            .sorted { $0.key > $1.key }
            .map { Day(start: $0.key, sittings: $0.value.sorted { $0.startedAt > $1.startedAt }) }
        timeline.buckets = buckets(for: scope, period: period, sittings: sittings, now: now, calendar: calendar)
        timeline.daysRead = timeline.days.count
        timeline.daysElapsed = elapsedDays(of: period, now: now, calendar: calendar)
        timeline.streakDays = streak(
            through: timeline.isCurrent ? now : period.end.addingTimeInterval(-1),
            isToday: timeline.isCurrent,
            facts: facts,
            calendar: calendar
        )
        timeline.longestStreakDays = ReadingInsights.longestStreak(of: periodFacts, calendar: calendar)
        timeline.mostRead = mostRead(sittings)
        timeline.topFandom = ReadingInsights.fandomShares(from: periodFacts).first { !$0.isRemainder }?.name
        timeline.longestFinishedWordCount = periodFacts.filter(\.didFinish).map(\.wordCount).max() ?? 0
        timeline.favouriteTime = favouriteTime(of: sittings, calendar: calendar)
        return timeline
    }

    /// Per sitting, in `facts` order: whether it begins a read-through, and which
    /// read-through of its work it belongs to.
    private static func readThroughs(of facts: [ReadingSessionFacts]) -> [(begins: Bool, count: Int)] {
        var result = Array(repeating: (begins: true, count: 1), count: facts.count)
        for indices in Dictionary(grouping: facts.indices, by: { facts[$0].workID }).values {
            var finishes = 0
            var previousFinished = true
            for index in indices.sorted(by: { ReadingInsights.sittingOrder(facts[$0], facts[$1]) }) {
                result[index] = (begins: previousFinished, count: finishes + 1)
                if facts[index].didFinish { finishes += 1 }
                previousFinished = facts[index].didFinish
            }
        }
        return result
    }

    private static func buckets(
        for scope: ReadingHistoryScope,
        period: DateInterval,
        sittings: [Sitting],
        now: Date,
        calendar: Calendar
    ) -> [Bucket] {
        var buckets: [Bucket] = []
        var cursor = period.start
        while cursor < period.end, let interval = calendar.dateInterval(of: scope.bucketComponent, for: cursor) {
            buckets.append(Bucket(start: interval.start, isFuture: interval.start > now))
            cursor = interval.end
        }
        let index = Dictionary(
            buckets.enumerated().map { ($1.start, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var finished: [Int: Set<UUID>] = [:]
        for sitting in sittings {
            guard let start = calendar.dateInterval(of: scope.bucketComponent, for: sitting.startedAt)?.start,
                  let position = index[start]
            else { continue }
            buckets[position].seconds += sitting.durationSeconds
            if sitting.didFinish { finished[position, default: []].insert(sitting.workID) }
        }
        for (position, works) in finished {
            buckets[position].finishedCount = works.count
        }
        return buckets
    }

    private static func elapsedDays(of period: DateInterval, now: Date, calendar: Calendar) -> Int {
        var count = 0
        var cursor = period.start
        while cursor < period.end, cursor <= now, let day = calendar.dateInterval(of: .day, for: cursor) {
            count += 1
            cursor = day.end
        }
        return count
    }

    /// Consecutive days with reading, counted back from `lastDay`. When
    /// `lastDay` is today and nothing has been read yet, the run is counted from
    /// yesterday: the day is not over, so it has not broken anything.
    static func streak(
        through lastDay: Date,
        isToday: Bool,
        facts: [ReadingSessionFacts],
        calendar: Calendar
    ) -> Int {
        let readingDays = Set(facts.map { calendar.startOfDay(for: $0.startedAt) })
        var day = calendar.startOfDay(for: lastDay)
        if isToday, !readingDays.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = calendar.startOfDay(for: yesterday)
        }
        var count = 0
        while readingDays.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = calendar.startOfDay(for: previous)
        }
        return count
    }

    private static func mostRead(_ sittings: [Sitting]) -> [WorkTime] {
        var byWork: [UUID: WorkTime] = [:]
        // Newest first, so a retitled work is named as it is now.
        for sitting in sittings.sorted(by: { $0.startedAt > $1.startedAt }) {
            var entry = byWork[sitting.workID]
                ?? WorkTime(workID: sitting.workID, title: sitting.title, fandom: sitting.fandom, seconds: 0)
            entry.seconds += sitting.durationSeconds
            byWork[sitting.workID] = entry
        }
        return byWork.values.sorted { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
            return lhs.title < rhs.title
        }
    }

    private static func favouriteTime(of sittings: [Sitting], calendar: Calendar) -> TimeOfDay? {
        var seconds: [TimeOfDay: Double] = [:]
        for sitting in sittings {
            seconds[TimeOfDay.of(hour: calendar.component(.hour, from: sitting.startedAt)), default: 0]
                += sitting.durationSeconds
        }
        // `max(by:)` keeps the first of equals, so a tie goes to the earlier time.
        return TimeOfDay.allCases
            .filter { (seconds[$0] ?? 0) > 0 }
            .max { (seconds[$0] ?? 0) < (seconds[$1] ?? 0) }
    }

    // MARK: Reading it out

    /// Time a day of the period averages, over the days that have begun — a
    /// Tuesday's average is not divided by the five days still to come.
    var averageBucketSeconds: Double {
        let begun = buckets.filter { !$0.isFuture }.count
        return begun > 0 ? totalSeconds / Double(begun) : 0
    }

    /// The busiest bucket, the earliest on a tie; `nil` when nothing was read.
    var peakBucket: Bucket? {
        buckets.filter { $0.seconds > 0 }.max { $0.seconds < $1.seconds }
    }

    /// The chart as one sentence for VoiceOver ("This week: 4 hours 10 minutes,
    /// most on Tuesday"), instead of a stop per bar.
    func chartSummary(periodName: String, calendar: Calendar) -> String {
        guard totalSeconds > 0, let peak = peakBucket else { return "\(periodName): no reading" }
        let total = Self.spokenDuration(totalSeconds)
        switch scope {
        case .week:
            let weekday = Self.symbol(calendar.weekdaySymbols, calendar.component(.weekday, from: peak.start))
            return "\(periodName): \(total), most on \(weekday)"
        case .month:
            let month = Self.symbol(calendar.monthSymbols, calendar.component(.month, from: peak.start))
            let day = calendar.component(.day, from: peak.start)
            return "\(periodName): \(total), read on \(daysRead) of \(daysElapsed) days, "
                + "most on \(month) \(day) (\(Self.spokenDuration(peak.seconds)))"
        case .year:
            let month = Self.symbol(calendar.monthSymbols, calendar.component(.month, from: peak.start))
            let works = "\(finishedCount) \(finishedCount == 1 ? "work" : "works") finished"
            return "\(periodName): \(total), most in \(month) (\(Self.spokenDuration(peak.seconds))), \(works)"
        }
    }

    /// "4 hours 10 minutes" — spelled out for VoiceOver, where "4h 10m" is read
    /// as letters.
    static func spokenDuration(_ seconds: Double) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        guard minutes > 0 else { return "under a minute" }
        var parts: [String] = []
        if minutes >= 60 { parts.append("\(minutes / 60) hour\(minutes / 60 == 1 ? "" : "s")") }
        if minutes % 60 > 0 { parts.append("\(minutes % 60) minute\(minutes % 60 == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }

    /// A calendar symbol by its 1-based component, or "" for one out of range.
    private static func symbol(_ symbols: [String], _ component: Int) -> String {
        symbols.indices.contains(component - 1) ? symbols[component - 1] : ""
    }
}
