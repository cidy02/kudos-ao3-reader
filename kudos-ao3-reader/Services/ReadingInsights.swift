import Foundation
import SwiftData

/// One reading session, reduced to the fields the statistics need.
///
/// Every rule in `ReadingInsights` works on these rather than on
/// `ReadingSession` directly, for two reasons. `ReadingSession` is a SwiftData
/// `@Model` and therefore main-actor bound, which would drag the arithmetic onto
/// the main actor with it; and a rule that takes plain values can be tested by
/// writing four of them in a line, instead of standing up an in-memory
/// container to assert that a median is a median.
///
/// `fandom` is resolved by the caller, because the session row does not carry
/// one — the log is keyed by work UUID and denormalises only the title, so a
/// deleted work still has history. An empty string means "not attributable",
/// which is a real outcome and not a failure.
nonisolated struct ReadingSessionFacts: Equatable, Sendable {
    var workID: UUID
    var startedAt: Date
    /// Wall-clock end; nil for historical facts that only stored active duration.
    var endedAt: Date? = nil
    var durationSeconds: Double
    var wordCount: Int
    var didFinish: Bool
    var fandom: String = ""
    /// What this sitting read, in words (owner Q27, 2026-10-20): see
    /// `ReadingLogService.wordsRead(sessions:)`.
    var wordsRead: Int = 0
    /// The rest are for Reading History's timeline (T-462), which draws each
    /// sitting rather than a total. Defaulted so the statistics' fixtures need
    /// not spell them out.
    var sessionID: UUID?
    var title: String = ""
    /// 0…1 at the end of the sitting (`ReadingSession.endingProgress`).
    var endingProgress: Double = 0
    /// Chapters posted at this visit; 0 when unknown.
    var chapterCount: Int = 0
    /// 0…1 at the start of the sitting (`ReadingSession.startProgress`), when recorded.
    var startProgress: Double? = nil
    /// Seconds east of UTC when the sitting was read (`ReadingSession.tzOffsetSeconds`), when recorded.
    var tzOffsetSeconds: Int? = nil
    /// Sitting mode (`.read` vs `.listen`), used so Pace excludes listening.
    var mode: ReadingSession.Mode = .read
    /// Measurement unit for the work's counts (`.words` vs `.characters`).
    var wordUnit: SavedWork.WordUnit = .words
    /// Author byline snapshot captured at visit (verified display names or comma-split author); survives deletion of the work.
    var authorAccounts: [String] = []
    /// Playback rate for `.listen` sittings (`ReadingSession.playbackRate`), when recorded (D4).
    var playbackRate: Double? = nil
    /// D1 metadata snapshots captured at visit so deleted works remain in Taste and Series.
    var fandoms: [String] = []
    var relationships: [String] = []
    var characters: [String] = []
    var freeformTags: [String] = []
    var rating: String = ""
    var warnings: [String] = []
    var categories: [String] = []
    var language: String = ""
    var isCompleteAtVisit: Bool = false
    var publishedYear: Int? = nil
    var ao3SeriesID: Int? = nil
    var seriesPosition: Int = 0
    var ao3WorkID: Int? = nil
    /// Source URL snapshot from `ReadingSession.sourceURL` so deleted works still know their origin.
    var sourceURL: String = ""
    /// Live `SavedWork.wordCount` when the work still exists and has a non-zero count, so
    /// Overview's `lengthMix` and Taste's `lengthBands` always bucket the exact same word count.
    var workWordCount: Int? = nil
}

/// What the log knows about one work, for a history or favourites row.
///
/// Spec 1ah puts three of these on every row — total time read, the visit count as
/// "Read ×2", and whether anything is new since the last visit — and a list can be
/// hundreds of rows long. Asking `ReadingLogService` per work would fetch every
/// session row once per work; `summaries(in:)` builds the whole map in one fetch.
nonisolated struct WorkReadingSummary: Equatable, Sendable {
    var totalSeconds: Double = 0
    /// Sessions recorded for this work. The spec's "Read ×2" is `finishCount`, not
    /// this — two sittings of one read-through are one read.
    var visitCount: Int = 0
    /// Sessions that ended with the work finished. This is the reread count.
    var finishCount: Int = 0
    var lastEndedAt: Date?
    /// Posted chapter count as of the most recent visit, for 1ah's "2 new chapters".
    var chapterCountAtLastVisit: Int = 0
}

/// Every figure artboard **1bi** prints, derived from the reading log.
///
/// A plain value over plain arrays rather than a set of `ModelContext` queries:
/// each of these is a rule about what counts, several of the rules are arguable,
/// and a rule you can hand a fixture to is a rule you can check.
///
/// Nothing here counts a session the log did not keep. `ReadingLogService` drops
/// anything under `minimumPersistableDuration`, which is why 1bi's own footnote
/// says a work opened and closed does not read as reading — the footnote is
/// describing that rule, not apologising for it.
nonisolated struct ReadingInsights: Equatable, Sendable {
    /// Seconds read in the period the screen is showing.
    var totalSeconds: Double = 0
    /// Seconds read in the period before it, for the spec's `+3.1 vs Jul`.
    /// `nil` when there is no earlier period to compare against — a first month
    /// has no delta, and printing `+18.4` against nothing would be a lie.
    var previousPeriodSeconds: Double?
    /// One bar per week, oldest first.
    var weeklySeconds: [WeeklyBucket] = []
    /// Where the hours went, largest first, already folded to the spec's three
    /// named fandoms plus `Everything else`.
    var byFandom: [FandomShare] = []
    /// The **median** session, not the mean: one four-hour binge should not move
    /// the number answering "how long do I usually read for".
    var medianSessionSeconds: Double = 0
    var wordsPerHour: Double = 0
    /// Share of *works* started in the period that reached a finish, in 0…1.
    /// `nil` when nothing was started — 0% and "no data" are different answers
    /// and only one of them is discouraging.
    var finishRate: Double?
    /// Longest run of consecutive days carrying at least one session.
    var longestStreakDays: Int = 0

    /// Words read in the period (T-497 Overview).
    var totalWordsRead: Int = 0
    /// Words read in the period before it.
    var previousPeriodWordsRead: Int?
    /// Where the words went by primary fandom (top 4 + remainder).
    var fandomWordsShares: [FandomWordsShare] = []
    /// Daily words breakdown for words-per-day chart and calendar.
    var dailyWords: [DailyWordsBucket] = []
    /// Hourly duration buckets (0...23) for habits time-of-day.
    var hourlyDuration: [HourlyBucket] = []
    /// Sitting duration distribution buckets (<10m, 10–30m, 30–60m, 1–2h, 2h+).
    var sittingBuckets: [SittingBucket] = []
    /// Mix of works by length (<5k, 5k–50k, 50k–150k, 150k+).
    var lengthMix: LengthMixCounts = LengthMixCounts()
    /// Duration spent reading.
    var readingSeconds: Double = 0
    /// Duration spent silently reading (`.read` mode).
    var silentReadingSeconds: Double = 0
    /// Duration spent listening to Read Aloud (`.listen` mode).
    var listeningSeconds: Double = 0
    /// Duration-weighted average Read Aloud playback rate across `.listen` sittings with a recorded rate (D4).
    var listeningPlaybackRate: Double? = nil
    /// Distinct works listened to via Read Aloud in this period (D4).
    var listeningWorksCount: Int = 0
    /// Characters read for no-space script works (`.characters`), never mixed into words.
    var charactersRead: Int = 0
    /// Visual reading pace in characters per hour for `.characters` works.
    var charactersPerHour: Double = 0
    /// Count of distinct works finished in this period.
    var finishedWorksCount: Int = 0
    /// Days with at least one reading session in this period.
    var readingDaysCount: Int = 0
    /// Day with the highest word total in this period.
    var biggestDay: DailyWordsBucket?

    nonisolated struct WeeklyBucket: Equatable, Sendable {
        var weekStart: Date
        var seconds: Double
    }

    nonisolated struct FandomShare: Equatable, Sendable {
        var name: String
        var seconds: Double
        /// True for the folded `Everything else` row, which is a remainder
        /// rather than a fandom and so must not be tappable.
        var isRemainder: Bool = false
    }

    nonisolated struct FandomWordsShare: Equatable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        var words: Int
        var worksCount: Int
        var share: Double
        var isRemainder: Bool = false
    }

    nonisolated struct DailyWordsBucket: Equatable, Sendable, Identifiable {
        var id: Date { date }
        var date: Date
        var dayNumber: Int
        var words: Int
        var isMax: Bool = false
        /// True when at least one sitting occurred on this reading day (including `.characters`
        /// or 0-net-word visits), so calendar reading-day counts agree with `readingDaysCount`.
        var hasReading: Bool = false
    }

    nonisolated struct HourlyBucket: Equatable, Sendable, Identifiable {
        var id: Int { hour }
        var hour: Int
        var seconds: Double
    }

    nonisolated struct SittingBucket: Equatable, Sendable, Identifiable {
        var id: String { label }
        var label: String
        var count: Int
    }

    nonisolated struct LengthMixCounts: Equatable, Sendable {
        var under5k: Int = 0
        var from5kTo50k: Int = 0
        var from50kTo150k: Int = 0
        var over150k: Int = 0
        var totalWorks: Int { under5k + from5kTo50k + from50kTo150k + over150k }
    }

    /// How many named fandoms 1bi lists before folding the rest together.
    static let namedFandomLimit = 3
    /// How many named fandoms Overview's words breakdown lists before folding.
    static let namedWordsFandomLimit = 4
    /// What the folded row is called. Named once so the screen can recognise it
    /// without matching a literal.
    static let remainderName = "Everything else"

    /// Builds every figure in one pass.
    /// `dayRange`: the days Words per Day draws, one slot each (days without reading are
    /// empty slots). Nil draws only the days that have reading.
    static func make(
        facts: [ReadingSessionFacts],
        previousPeriodFacts: [ReadingSessionFacts] = [],
        dayRange: DateInterval? = nil,
        calendar: Calendar = .current,
        aliases: TagAliasResolver = .empty
    ) -> ReadingInsights {
        var insights = ReadingInsights()
        let comparablePrevious = comparablePreviousFacts(
            previousPeriodFacts,
            matching: dayRange,
            calendar: calendar
        )
        insights.totalSeconds = facts.reduce(0) { $0 + $1.durationSeconds }
        insights.previousPeriodSeconds = comparablePrevious.isEmpty
            ? nil
            : comparablePrevious.reduce(0) { $0 + $1.durationSeconds }
        insights.weeklySeconds = weeklyBuckets(from: facts, calendar: calendar)
        insights.byFandom = fandomShares(from: facts, aliases: aliases)
        insights.medianSessionSeconds = medianSeconds(of: facts)
        insights.wordsPerHour = wordsPerHour(of: facts)
        insights.charactersPerHour = charactersPerHour(of: facts)
        insights.finishRate = finishRate(of: facts)
        insights.longestStreakDays = longestStreak(of: facts, calendar: calendar)

        // New redesign figures (T-497, D3/D4 character & listening separation)
        let wordFacts = facts.filter { $0.wordUnit == .words }
        let charFacts = facts.filter { $0.wordUnit == .characters }
        let previousWordFacts = comparablePrevious.filter { $0.wordUnit == .words }
        insights.totalWordsRead = wordFacts.reduce(0) { $0 + $1.wordsRead }
        insights.charactersRead = charFacts.reduce(0) { $0 + $1.wordsRead }
        insights.previousPeriodWordsRead = previousWordFacts.isEmpty
            ? nil
            : previousWordFacts.reduce(0) { $0 + $1.wordsRead }
        insights.fandomWordsShares = fandomWordsShares(from: facts, aliases: aliases)

        // Owner review: include every work read in the period (both `.words` and
        // `.characters`) in Length of What You Read so Overview's works count agrees
        // with Taste's works read. Sort by `sittingOrder` and prefer live `workWordCount`
        // when present so Overview and Taste always bucket the exact same count.
        var wordCountsByWork: [UUID: Int] = [:]
        for f in facts.sorted(by: sittingOrder) {
            if let liveWords = f.workWordCount, liveWords > 0 {
                wordCountsByWork[f.workID] = liveWords
            } else if f.wordCount > 0 || wordCountsByWork[f.workID] == nil {
                wordCountsByWork[f.workID] = f.wordCount
            }
        }
        insights.lengthMix = lengthMix(words: Array(wordCountsByWork.values))

        insights.dailyWords = dailyWordsBuckets(from: facts, in: dayRange, calendar: calendar)
        insights.hourlyDuration = hourlyDurationBuckets(from: facts, calendar: calendar)
        insights.sittingBuckets = sittingBuckets(from: facts)
        insights.readingSeconds = facts.reduce(0) { $0 + $1.durationSeconds }
        insights.silentReadingSeconds = facts.filter { $0.mode == .read }.reduce(0) { $0 + $1.durationSeconds }
        let listenFacts = facts.filter { $0.mode == .listen && $0.durationSeconds > 0 }
        insights.listeningSeconds = listenFacts.reduce(0) { $0 + $1.durationSeconds }
        insights.listeningWorksCount = Set(listenFacts.map(\.workID)).count
        var weightedRateSum = 0.0
        var weightedRateSeconds = 0.0
        for fact in listenFacts {
            if let rate = fact.playbackRate, rate > 0 {
                weightedRateSum += rate * fact.durationSeconds
                weightedRateSeconds += fact.durationSeconds
            }
        }
        insights.listeningPlaybackRate = weightedRateSeconds > 0
            ? weightedRateSum / weightedRateSeconds
            : nil
        insights.finishedWorksCount = Set(facts.filter(\.didFinish).map(\.workID)).count
        insights.readingDaysCount = Set(facts.map { sittingTime(for: $0, calendar: calendar).day }).count
        // Days without reading are empty chart slots, never the biggest day.
        insights.biggestDay = insights.dailyWords.filter { $0.words > 0 }.max(by: { $0.words < $1.words })
        return insights
    }

    // MARK: The rules

    /// The hour at which one reading day ends and the next begins (04:00 local).
    static let dayBoundaryHour = 4

    /// A sitting's 4:00-to-4:00 reading day (at `calendar.startOfDay`) and local wall-clock
    /// hour in the time zone the sitting was read in (`tzOffsetSeconds` when present, else
    /// `calendar.timeZone`). Every period boundary, streak, Reading Days calendar, Time of
    /// Day chart and Fandom Timeline month goes through this one rule.
    static func sittingTime(
        startedAt: Date,
        tzOffsetSeconds: Int?,
        calendar: Calendar = .current
    ) -> (day: Date, hour: Int) {
        var local = calendar
        if let offset = tzOffsetSeconds,
           let timeZone = TimeZone(secondsFromGMT: offset) {
            local.timeZone = timeZone
        }
        let parts = local.dateComponents([.year, .month, .day, .hour], from: startedAt)
        let hour = parts.hour ?? 0
        let rawDay = calendar
            .date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
            .map { calendar.startOfDay(for: $0) }
            ?? calendar.startOfDay(for: startedAt)
        let day = hour < dayBoundaryHour
            ? (calendar.date(byAdding: .day, value: -1, to: rawDay) ?? rawDay)
            : rawDay
        return (day: day, hour: hour)
    }

    static func sittingTime(
        for fact: ReadingSessionFacts,
        calendar: Calendar = .current
    ) -> (day: Date, hour: Int) {
        sittingTime(startedAt: fact.startedAt, tzOffsetSeconds: fact.tzOffsetSeconds, calendar: calendar)
    }

    /// The 4:00-to-4:00 reading day in the zone the sitting was read in.
    static func readingDay(
        for fact: ReadingSessionFacts,
        calendar: Calendar = .current
    ) -> Date {
        sittingTime(for: fact, calendar: calendar).day
    }

    /// The 4:00-to-4:00 reading day for a persisted `ReadingSession`.
    static func readingDay(
        for session: ReadingSession,
        calendar: Calendar = .current
    ) -> Date {
        sittingTime(startedAt: session.startedAt, tzOffsetSeconds: session.tzOffsetSeconds, calendar: calendar).day
    }

    /// Half-open `[start, end)` period membership using the sitting's 4:00-to-4:00
    /// reading day in its recorded time zone (`DateInterval.contains` is closed at `end`,
    /// which would include the next period's first day).
    static func isInPeriod(
        _ fact: ReadingSessionFacts,
        period: DateInterval,
        calendar: Calendar = .current
    ) -> Bool {
        let day = readingDay(for: fact, calendar: calendar)
        return day >= calendar.startOfDay(for: period.start) && day < period.end
    }

    static func isInPeriod(
        _ session: ReadingSession,
        period: DateInterval,
        calendar: Calendar = .current
    ) -> Bool {
        let day = readingDay(for: session, calendar: calendar)
        return day >= calendar.startOfDay(for: period.start) && day < period.end
    }

    /// Like for like: the part of the earlier period `previousPeriodFacts` that spans as many
    /// days as `dayRange` (the days elapsed of the period on screen), counted from the start
    /// of the earlier period. A 10-day partial month is compared with the first 10 days of
    /// the month before, not the whole of it. Without a `dayRange` (a year, or no chart
    /// days) the earlier period is returned whole. The earlier period is taken to start one
    /// month before `dayRange` (the screen only compares months through a day range).
    static func comparablePreviousFacts(
        _ previousPeriodFacts: [ReadingSessionFacts],
        matching dayRange: DateInterval?,
        calendar: Calendar = .current
    ) -> [ReadingSessionFacts] {
        guard let dayRange,
              let previousStart = calendar.date(byAdding: .month, value: -1, to: dayRange.start)
        else { return previousPeriodFacts }
        let elapsed = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: dayRange.start),
            to: dayRange.end
        ).day ?? 0
        let previousFirstDay = calendar.startOfDay(for: previousStart)
        return previousPeriodFacts.filter { fact in
            let index = calendar.dateComponents(
                [.day],
                from: previousFirstDay,
                to: readingDay(for: fact, calendar: calendar)
            ).day ?? 0
            return index >= 0 && index < elapsed
        }
    }

    static func weeklyBuckets(
        from facts: [ReadingSessionFacts],
        calendar: Calendar
    ) -> [WeeklyBucket] {
        var buckets: [Date: Double] = [:]
        for fact in facts {
            let day = readingDay(for: fact, calendar: calendar)
            guard let weekStart = calendar
                .dateInterval(of: .weekOfYear, for: day)?.start
            else { continue }
            buckets[weekStart, default: 0] += fact.durationSeconds
        }
        return buckets.keys.sorted().map {
            WeeklyBucket(weekStart: $0, seconds: buckets[$0] ?? 0)
        }
    }

    /// Attributes each session's whole duration to **one** fandom — the work's
    /// first, the same one its card kicker names.
    ///
    /// Splitting a crossover's time across all of its fandoms was the
    /// alternative and is worse here: this list sits directly under a total, and
    /// shares that count a crossover once per fandom would add up to more than
    /// the hours printed above them. A partition can be read; an over-count
    /// cannot.
    static func fandomShares(
        from facts: [ReadingSessionFacts],
        aliases: TagAliasResolver = .empty
    ) -> [FandomShare] {
        var seconds: [String: Double] = [:]
        var unattributed: Double = 0
        for fact in facts {
            let fandom = aliases.resolve(fact.fandom, kind: .fandom)
            if fandom.isEmpty {
                unattributed += fact.durationSeconds
            } else {
                seconds[fandom, default: 0] += fact.durationSeconds
            }
        }

        let ranked = seconds.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }
        var shares = ranked.prefix(namedFandomLimit).map {
            FandomShare(name: $0.key, seconds: $0.value)
        }
        let remainder = ranked.dropFirst(namedFandomLimit)
            .reduce(0) { $0 + $1.value } + unattributed
        if remainder > 0 {
            shares.append(
                FandomShare(name: remainderName, seconds: remainder, isRemainder: true)
            )
        }
        return shares
    }

    /// Visits closer together than this are one sitting for the median.
    static let sittingMergeGapSeconds: Double = 5 * 60

    /// Median of the sitting durations. Visits (of any work) that start
    /// under 5 minutes after the one before ended are one sitting here (a view over the
    /// stored rows; nothing is merged or rewritten). An even count takes the mean of the
    /// middle two — the ordinary definition, and the one a reader checking the figure by
    /// hand would use.
    static func medianSeconds(of facts: [ReadingSessionFacts]) -> Double {
        let durations = mergedSittingDurations(of: facts).sorted()
        guard !durations.isEmpty else { return 0 }
        let middle = durations.count / 2
        if durations.count.isMultiple(of: 2) {
            return (durations[middle - 1] + durations[middle]) / 2
        }
        return durations[middle]
    }

    /// Durations of the sittings once visits under 5 minutes apart are joined; the joined
    /// sitting's length is the sum of its visits' reading time.
    static func mergedSittingDurations(of facts: [ReadingSessionFacts]) -> [Double] {
        var merged: [Double] = []
        var currentEnd: Date?
        for fact in facts.filter({ $0.durationSeconds > 0 }).sorted(by: sittingOrder) {
            let end = fact.startedAt.addingTimeInterval(fact.durationSeconds)
            if let last = currentEnd, !merged.isEmpty,
               fact.startedAt.timeIntervalSince(last) < sittingMergeGapSeconds {
                merged[merged.count - 1] += fact.durationSeconds
                currentEnd = max(last, end)
            } else {
                merged.append(fact.durationSeconds)
                currentEnd = end
            }
        }
        return merged
    }

    /// Words per hour over the whole period, weighted by time rather than
    /// averaged across sessions. Zero-length rows are dropped so one cannot
    /// divide by zero or dilute the rate. Counts the words each sitting read,
    /// not the whole work's (owner Q27, 2026-10-20).
    static func wordsPerHour(of facts: [ReadingSessionFacts]) -> Double {
        pace(of: facts, unit: .words)
    }

    static func charactersPerHour(of facts: [ReadingSessionFacts]) -> Double {
        pace(of: facts, unit: .characters)
    }

    private static func pace(
        of facts: [ReadingSessionFacts],
        unit: SavedWork.WordUnit
    ) -> Double {
        // D4 & D3: visual reading pace excludes listening sittings and never
        // mixes `.words` with `.characters`.
        let usable = facts.filter {
            $0.durationSeconds > 0 && $0.mode == .read && $0.wordUnit == unit
        }
        let totalSeconds = usable.reduce(0) { $0 + $1.durationSeconds }
        guard totalSeconds > 0 else { return 0 }
        let totalCount = usable.reduce(0) { $0 + $1.wordsRead }
        return Double(totalCount) / (totalSeconds / 3600)
    }

    /// Share of works that reached a finish, counted **per work rather than per
    /// session**. Reading one work four times is one work, not four; counting
    /// sessions would let a single much-reread favourite carry the figure.
    static func finishRate(of facts: [ReadingSessionFacts]) -> Double? {
        let startedWorkIDs = Set(facts.map(\.workID))
        guard !startedWorkIDs.isEmpty else { return nil }
        let finishedWorkIDs = Set(facts.filter(\.didFinish).map(\.workID))
        return Double(finishedWorkIDs.count) / Double(startedWorkIDs.count)
    }

    /// Where each sitting began in its work, 0…1, in `facts` order (owner Q27,
    /// 2026-10-20; T-515, 2026-11-13): its recorded `startProgress` when present,
    /// else where the work's sitting before it ended (in words over this sitting's
    /// word count), or the start for its first sitting and for one after a sitting
    /// that finished a work that has not grown since. A sitting that went back is
    /// where the next one starts from.
    ///
    /// One rule for the words each sitting read (`ReadingLogService.wordsRead`)
    /// and the chapters History draws it reading, so the two cannot disagree.
    static func startingProgress(of facts: [ReadingSessionFacts]) -> [Double] {
        var starts = Array(repeating: 0.0, count: facts.count)
        for indices in Dictionary(grouping: facts.indices, by: { facts[$0].workID }).values {
            var previousEndFraction = 0.0
            var previousEndWords = 0.0
            var previousWords = 0
            var previousFinished = false
            for index in indices.sorted(by: { sittingOrder(facts[$0], facts[$1]) }) {
                let fact = facts[index]
                let words = max(0, fact.wordCount)
                let endFraction = min(1, max(0, fact.endingProgress))
                let startFraction: Double
                if let explicit = fact.startProgress {
                    let clamped = min(1, max(0, explicit))
                    if previousWords > 0 && words > previousWords && clamped == previousEndFraction {
                        startFraction = min(1, max(0, previousEndWords / Double(words)))
                    } else {
                        startFraction = clamped
                    }
                } else if previousFinished && words <= previousWords {
                    startFraction = 0
                } else if words > 0 && previousWords > 0 {
                    startFraction = min(1, max(0, previousEndWords / Double(words)))
                } else {
                    startFraction = previousEndFraction
                }
                starts[index] = startFraction
                previousEndFraction = endFraction
                previousEndWords = endFraction * Double(words)
                previousWords = words
                previousFinished = fact.didFinish
            }
        }
        return starts
    }

    /// Oldest first, the session id breaking a tie so the order is stable.
    static func sittingOrder(_ lhs: ReadingSessionFacts, _ rhs: ReadingSessionFacts) -> Bool {
        (lhs.startedAt, lhs.sessionID?.uuidString ?? "") < (rhs.startedAt, rhs.sessionID?.uuidString ?? "")
    }

    /// Longest run of consecutive calendar days carrying at least one session.
    ///
    /// Days, not sessions: two sessions on one evening are one day of reading.
    /// `calendar` is a parameter because "which day is this" is a timezone
    /// question, and a streak computed in UTC would break for anyone who reads
    /// late at night.
    static func longestStreak(of facts: [ReadingSessionFacts], calendar: Calendar) -> Int {
        let days = Set(facts.map { sittingTime(for: $0, calendar: calendar).day }).sorted()
        guard !days.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for (previous, day) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    // MARK: Display

    /// The spec's `18.4` — hours to one decimal place.
    static func hoursLabel(_ seconds: Double) -> String {
        String(format: "%.1f", max(0, seconds) / 3600)
    }

    /// The spec's `+3.1` / `−0.6`, with an explicit sign so the direction reads
    /// without having to compare two numbers.
    static func signedHoursLabel(_ deltaSeconds: Double) -> String {
        let hours = deltaSeconds / 3600
        return (hours < 0 ? "−" : "+") + String(format: "%.1f", abs(hours))
    }

    /// The spec's `31 min` below an hour, then its compact `3h 20m` (1ah's
    /// facts, 1ak's log line) — the reader keeps its own spelled-out sentence.
    static func durationLabel(_ seconds: Double) -> String {
        let totalMinutes = Int((max(0, seconds) / 60).rounded())
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    /// UTC Gregorian calendar for AO3 posting dates (`WorkStat.date(from:)` produces UTC midnight).
    static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return cal
    }()

    /// Compact word label without truncating small counts to `"0k"`: exact below 1,000,
    /// one decimal in thousands (e.g. `"12.4k"`), one decimal in millions (e.g. `"1.2M"`).
    static func compactWordsLabel(_ words: Int) -> String {
        let clamped = max(0, words)
        if clamped < 1_000 { return clamped.formatted() }
        if clamped < 1_000_000 {
            return String(format: "%.1fk", Double(clamped) / 1_000.0)
        }
        return String(format: "%.1fM", Double(clamped) / 1_000_000.0)
    }

    // MARK: Redesign Helpers (T-497)

    /// Spec: Words read ÷ 70,000, to the nearest half. Hidden under 35,000 words.
    static func novelsWorth(words: Int) -> Double? {
        guard words >= 35_000 else { return nil }
        let raw = Double(words) / 70_000.0
        return (raw * 2.0).rounded() / 2.0
    }

    /// Label matching spec: "About 3 novels’ worth, at 70,000 words a novel"
    static func novelsWorthLabel(words: Int) -> String? {
        guard let n = novelsWorth(words: words) else { return nil }
        let formatted = n.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", n) : String(format: "%.1f", n)
        let noun = n == 1 ? "novel’s" : "novels’"
        return "About \(formatted) \(noun) worth, at 70,000 words a novel"
    }

    /// Buckets words read by length (<5k, 5k–50k, 50k–150k, 150k+).
    static func lengthMix(words: [Int]) -> LengthMixCounts {
        var mix = LengthMixCounts()
        for w in words {
            if w < 5_000 {
                mix.under5k += 1
            } else if w < 50_000 {
                mix.from5kTo50k += 1
            } else if w < 150_000 {
                mix.from50kTo150k += 1
            } else {
                mix.over150k += 1
            }
        }
        return mix
    }

    /// The days a period's Words per Day chart draws: from the period's start to the end of
    /// today (never future days), and only for periods of a month or less — a year of daily
    /// slots would be unreadable. Nil keeps the reading days only.
    static func chartDays(for period: DateInterval, now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? period.end
        let end = min(period.end, tomorrow)
        guard end > period.start else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: period.start), to: end).day ?? 0
        return days <= 31 ? DateInterval(start: period.start, end: end) : nil
    }

    /// Daily words breakdown within an optional date interval.
    static func dailyWordsBuckets(
        from facts: [ReadingSessionFacts],
        in interval: DateInterval? = nil,
        calendar: Calendar = .current
    ) -> [DailyWordsBucket] {
        var wordsByDay: [Date: Int] = [:]
        var daysWithReading: Set<Date> = []
        for fact in facts {
            let day = sittingTime(for: fact, calendar: calendar).day
            daysWithReading.insert(day)
            if fact.wordUnit == .words {
                wordsByDay[day, default: 0] += fact.wordsRead
            }
        }

        guard let interval else {
            let sortedDays = daysWithReading.sorted()
            let maxWords = wordsByDay.values.max() ?? 0
            return sortedDays.map { (day: Date) -> DailyWordsBucket in
                let w = wordsByDay[day] ?? 0
                return DailyWordsBucket(
                    date: day,
                    dayNumber: calendar.component(.day, from: day),
                    words: w,
                    isMax: maxWords > 0 && w == maxWords,
                    hasReading: true
                )
            }
        }

        var buckets: [DailyWordsBucket] = []
        var current = calendar.startOfDay(for: interval.start)
        let latestReadingNextDay = daysWithReading.max().flatMap { (day: Date) -> Date? in
            calendar.date(byAdding: .day, value: 1, to: day)
        }
        let end = latestReadingNextDay.map { max(interval.end, $0) } ?? interval.end
        let maxWords = wordsByDay.values.max() ?? 0

        while current < end {
            let w = wordsByDay[current] ?? 0
            buckets.append(
                DailyWordsBucket(
                    date: current,
                    dayNumber: calendar.component(.day, from: current),
                    words: w,
                    isMax: maxWords > 0 && w == maxWords,
                    hasReading: daysWithReading.contains(current)
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return buckets
    }

    /// Owner review: cap wall-clock spread at 6 hours (the sane-sitting ceiling in
    /// Insights-Metrics) so overnight pauses do not credit sleeping hours to 1:00–5:00
    /// and a corrupted far-future `endedAt` cannot stall the hourly loop.
    static let maxHourlyWallSpreadSeconds: Double = 6 * 3_600

    /// Hourly duration buckets (0...23) for habits time of day.
    static func hourlyDurationBuckets(
        from facts: [ReadingSessionFacts],
        calendar: Calendar = .current
    ) -> [HourlyBucket] {
        var hours: [Double] = Array(repeating: 0, count: 24)
        let maxLoopSpan: Double = 24 * 3_600
        for fact in facts {
            // Active duration can be shorter than wall time after a pause. Allocate
            // it in proportion to each hour's wall-clock overlap, with the last
            // slice taking the rounding remainder so the bars exactly reconcile.
            var local = calendar
            if let offset = fact.tzOffsetSeconds, let zone = TimeZone(secondsFromGMT: offset) {
                local.timeZone = zone
            }
            let start = fact.startedAt
            let duration = max(0, fact.durationSeconds)
            guard duration > 0 else { continue }
            var cursor = start
            let clampedDurationSpan = min(duration, maxLoopSpan)
            let rawWallEnd = fact.endedAt ?? start.addingTimeInterval(clampedDurationSpan)
            let rawWallSeconds = rawWallEnd.timeIntervalSince(start)
            let maxAllowedWall = max(clampedDurationSpan, maxHourlyWallSpreadSeconds)
            let end = (rawWallSeconds > 0 && rawWallSeconds <= maxAllowedWall)
                ? rawWallEnd
                : start.addingTimeInterval(clampedDurationSpan)
            let wallSeconds = end.timeIntervalSince(start)
            guard wallSeconds > 0 else { continue }
            var remaining = duration
            while cursor < end {
                let hour = local.component(.hour, from: cursor)
                let next = local.nextDate(after: cursor, matching: DateComponents(minute: 0, second: 0),
                    matchingPolicy: .nextTime) ?? end
                let boundary = min(end, next)
                guard boundary > cursor else { break }
                let seconds = boundary == end
                    ? remaining
                    : duration * boundary.timeIntervalSince(cursor) / wallSeconds
                hours[hour] += seconds
                remaining -= seconds
                cursor = boundary
            }
        }
        return (0..<24).map { HourlyBucket(hour: $0, seconds: hours[$0]) }
    }

    /// Seconds read during late-night hours (1:00 to 5:00).
    static func lateNightDuration(
        from facts: [ReadingSessionFacts],
        calendar: Calendar = .current
    ) -> Double {
        hourlyDurationBuckets(from: facts, calendar: calendar)
            .filter { $0.hour >= 1 && $0.hour < 5 }
            .reduce(0) { $0 + $1.seconds }
    }

    /// Sittings duration distribution (<10m, 10–30m, 30–60m, 1–2h, 2h+).
    static func sittingBuckets(from facts: [ReadingSessionFacts]) -> [SittingBucket] {
        var b0 = 0
        var b1 = 0
        var b2 = 0
        var b3 = 0
        var b4 = 0

        for fact in facts where fact.durationSeconds > 0 {
            let m = fact.durationSeconds / 60
            if m < 10 {
                b0 += 1
            } else if m < 30 {
                b1 += 1
            } else if m < 60 {
                b2 += 1
            } else if m < 120 {
                b3 += 1
            } else {
                b4 += 1
            }
        }

        return [
            SittingBucket(label: "< 10 m", count: b0),
            SittingBucket(label: "10–30 m", count: b1),
            SittingBucket(label: "30–60 m", count: b2),
            SittingBucket(label: "1–2 h", count: b3),
            SittingBucket(label: "2 h +", count: b4)
        ]
    }

    /// Where the words went: primary fandom shares by word count (top 4 + remainder).
    static func fandomWordsShares(
        from facts: [ReadingSessionFacts],
        aliases: TagAliasResolver = .empty
    ) -> [FandomWordsShare] {
        var wordsMap: [String: Int] = [:]
        var worksMap: [String: Set<UUID>] = [:]
        var unattributedWords: Int = 0
        var unattributedWorks: Set<UUID> = []

        for fact in facts where fact.wordUnit == .words {
            let fandom = aliases.resolve(fact.fandom, kind: .fandom)
            if fandom.isEmpty {
                unattributedWords += fact.wordsRead
                unattributedWorks.insert(fact.workID)
            } else {
                wordsMap[fandom, default: 0] += fact.wordsRead
                worksMap[fandom, default: []].insert(fact.workID)
            }
        }

        let totalWords = max(1, facts.filter { $0.wordUnit == .words }.reduce(0) { $0 + $1.wordsRead })
        let ranked = wordsMap.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }

        var shares: [FandomWordsShare] = ranked.prefix(namedWordsFandomLimit).map {
            let count = worksMap[$0.key]?.count ?? 0
            return FandomWordsShare(
                name: $0.key,
                words: $0.value,
                worksCount: count,
                share: Double($0.value) / Double(totalWords),
                isRemainder: false
            )
        }

        let remWords = ranked.dropFirst(namedWordsFandomLimit).reduce(0) { $0 + $1.value } + unattributedWords
        let remWorks = ranked.dropFirst(namedWordsFandomLimit).reduce(into: Set<UUID>()) { set, pair in
            set.formUnion(worksMap[pair.key] ?? [])
        }.union(unattributedWorks)

        if remWords > 0 || !remWorks.isEmpty {
            shares.append(
                FandomWordsShare(
                    name: remainderName,
                    words: remWords,
                    worksCount: remWorks.count,
                    share: Double(remWords) / Double(totalWords),
                    isRemainder: true
                )
            )
        }
        return shares
    }

    /// Romantic vs Platonic relationship detection.
    static func isRomanticRelationship(_ name: String) -> Bool {
        name.contains("/")
    }

    static func relationshipGlyph(for name: String) -> String {
        name.contains("/") ? "/" : (name.contains("&") ? "&" : "·")
    }

    /// Ship concentration per fandom.
    static func shipConcentrations(
        relationships: [RelationshipShare],
        fandomWords: [String: Int] = [:],
        fandomWorkCounts: [String: Int] = [:]
    ) -> [ShipConcentration] {
        var byFandom: [String: [RelationshipShare]] = [:]
        for rel in relationships where !rel.fandom.isEmpty {
            byFandom[rel.fandom, default: []].append(rel)
        }

        var result: [ShipConcentration] = []
        for (fandom, ships) in byFandom {
            let workCount = fandomWorkCounts[fandom] ?? ships.reduce(0) { $0 + $1.worksCount }
            guard workCount >= 4 else { continue }
            let sorted = ships.sorted { (lhs: RelationshipShare, rhs: RelationshipShare) -> Bool in
                if lhs.words != rhs.words { return lhs.words > rhs.words }
                return lhs.name < rhs.name
            }
            guard let top = sorted.first else { continue }
            let totalWords = max(1, fandomWords[fandom] ?? ships.reduce(0) { $0 + $1.words })
            let pct = min(100, Int((Double(top.words) / Double(totalWords) * 100).rounded()))
            let label = sorted.count == 1
                ? "\(pct)% on one ship"
                : "\(pct)% · \(sorted.count) ships"
            result.append(
                ShipConcentration(
                    fandom: fandom,
                    topShipName: top.name,
                    percentage: pct,
                    shipsCount: sorted.count,
                    label: label
                )
            )
        }
        return result.sorted { (lhs: ShipConcentration, rhs: ShipConcentration) -> Bool in
            if lhs.percentage != rhs.percentage { return lhs.percentage > rhs.percentage }
            return lhs.fandom < rhs.fandom
        }
    }

    /// Freeform tags for tag-only figures (Taste Tags, Often Together, Stopped tags).
    /// Prefers AO3's categorized `workFreeforms`; when empty, strips categorized
    /// fandoms/relationships/characters from flat `workTags` so refreshed works with no
    /// freeform tags never leak other categories while unrefreshed EPUBs keep their tags.
    static func freeformTags(of work: SavedWork) -> [String] {
        if !work.workFreeforms.isEmpty {
            return work.workFreeforms
        }
        let nonFreeform = Set(
            (work.workFandoms + work.workRelationships + work.workCharacters)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        if nonFreeform.isEmpty { return work.workTags }
        return work.workTags.filter { tag in
            !nonFreeform.contains(tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    /// Freeform tags plus Archive Warnings for stop-tag figures (Habits Common in Stopped Works).
    static func stopTags(of work: SavedWork, aliases: TagAliasResolver) -> Set<String> {
        let warnings = work.workWarnings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let freeforms = aliases.resolvedUnique(freeformTags(of: work), kind: .freeform)
        return Set(warnings + freeforms)
    }

    /// Filters anonymous, orphan_account, and deleted bylines at display time in the
    /// Library Authors figure so `ReadingSession.authorAccounts` keeps full creator snapshots.
    static func isExcludedAuthorByline(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        if lower == "orphan_account" || lower == "anonymous" || lower == "deleted" {
            return true
        }
        return lower.hasSuffix("(orphan_account)")
    }

    /// Normalizes a stored `ReadingSession.authorAccounts` display byline to its AO3
    /// account username for `Library → Authors`: extracts the trailing `"pseud (username)"`
    /// account so deleted pseud works merge with live works under the same account, and
    /// drops `orphan_account`, `anonymous`, and `deleted` bylines.
    static func normalizedAO3AuthorAccount(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let account: String
        if trimmed.hasSuffix(")"),
           let openParen = trimmed.lastIndex(of: "("),
           openParen < trimmed.index(before: trimmed.endIndex) {
            let start = trimmed.index(after: openParen)
            let end = trimmed.index(before: trimmed.endIndex)
            let extracted = trimmed[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            account = extracted.isEmpty ? trimmed : extracted
        } else {
            account = trimmed
        }
        guard !isExcludedAuthorByline(account) else { return nil }
        return account
    }

    /// Tag pairs that appear together on >= minimumCount works.
    static func oftenTogetherTags(
        from works: [SavedWork],
        minimumCount: Int = 3,
        aliases: TagAliasResolver = .empty
    ) -> [TagPair] {
        let tagSets = works.map { (work: SavedWork) -> [String] in
            freeformTags(of: work)
        }
        return oftenTogetherTags(fromTagSets: tagSets, minimumCount: minimumCount, aliases: aliases)
    }

    static func oftenTogetherTags(
        fromTagSets tagSets: [[String]],
        minimumCount: Int = 3,
        aliases: TagAliasResolver = .empty
    ) -> [TagPair] {
        let workCount = tagSets.count
        guard workCount >= minimumCount else { return [] }
        var pairCounts: [String: (a: String, b: String, count: Int)] = [:]
        var tagCounts: [String: Int] = [:]
        for rawTags in tagSets {
            let tags = aliases.resolvedUnique(rawTags, kind: .freeform).sorted()
            for tag in tags { tagCounts[tag, default: 0] += 1 }
            guard tags.count >= 2 else { continue }
            for i in 0..<tags.count {
                for j in (i + 1)..<tags.count {
                    let a = tags[i]
                    let b = tags[j]
                    let key = "\(a)||\(b)"
                    let current = pairCounts[key]?.count ?? 0
                    pairCounts[key] = (a: a, b: b, count: current + 1)
                }
            }
        }
        return pairCounts.values
            .filter { (pair: (a: String, b: String, count: Int)) -> Bool in
                pair.count >= minimumCount
                    && Double(pair.count * workCount) >= 1.5 * Double((tagCounts[pair.a] ?? 0) * (tagCounts[pair.b] ?? 0))
            }
            .sorted { (lhs: (a: String, b: String, count: Int), rhs: (a: String, b: String, count: Int)) -> Bool in
                let lhsLift = Double(lhs.count * workCount) / Double(max(1, (tagCounts[lhs.a] ?? 0) * (tagCounts[lhs.b] ?? 0)))
                let rhsLift = Double(rhs.count * workCount) / Double(max(1, (tagCounts[rhs.a] ?? 0) * (tagCounts[rhs.b] ?? 0)))
                if lhsLift != rhsLift { return lhsLift > rhsLift }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                if lhs.a != rhs.a { return lhs.a < rhs.a }
                return lhs.b < rhs.b
            }
            .prefix(4)
            .map { TagPair(tagA: $0.a, tagB: $0.b, worksCount: $0.count) }
    }

    /// Works in progress categorized by time since update (active, quiet, dormant).
    static func wipFreshness(works: [SavedWork], now: Date = Date(), calendar: Calendar = .current) -> WIPFreshness {
        var freshness = WIPFreshness()
        for work in works where !work.isComplete {
            let updateDate = WorkStat.date(from: work.dateUpdated) ?? work.lastModifiedAt
            let days = calendar.dateComponents([.day], from: updateDate, to: now).day ?? 0
            if days <= 180 {
                freshness.active += 1
            } else if days <= 365 {
                freshness.quiet += 1
            } else {
                freshness.dormant += 1
            }
        }
        return freshness
    }

    /// Partitions library works into the 7 standard statuses.
    static func partitionStatuses(works: [SavedWork], now: Date = Date()) -> ReadingStatusPartition {
        var p = ReadingStatusPartition()
        for work in works {
            switch work.insightsReadingStatus {
            case .stopped: p.stoppedCount += 1
            case .onHold: p.onHoldCount += 1
            case .stacking: p.stackingCount += 1
            case .finished: p.finishedCount += 1
            case .caughtUp: p.caughtUpCount += 1
            case .reading: p.readingCount += 1
            case .savedForLater: p.savedForLaterCount += 1
            }
        }
        return p
    }
}

// MARK: - Redesign Metric Types (T-497)

nonisolated struct RelationshipShare: Equatable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var isRomantic: Bool
    var fandom: String
    var worksCount: Int
    var words: Int
    /// True when at least one counted work is measured in `.words` (keeps `.characters`
    /// works out of By Words lists while retaining them in By Works rankings).
    var hasWordUnitWorks: Bool = true
}

nonisolated struct ShipConcentration: Equatable, Sendable, Identifiable {
    var id: String { fandom }
    var fandom: String
    var topShipName: String
    var percentage: Int
    var shipsCount: Int
    var label: String
}

nonisolated struct TagPair: Equatable, Sendable, Identifiable {
    var id: String { "\(tagA)+\(tagB)" }
    var tagA: String
    var tagB: String
    var worksCount: Int
}

nonisolated struct WIPFreshness: Equatable, Sendable {
    var active: Int = 0
    var quiet: Int = 0
    var dormant: Int = 0
    var total: Int { active + quiet + dormant }
}

nonisolated struct ReadingStatusPartition: Equatable, Sendable {
    var readingCount: Int = 0
    var caughtUpCount: Int = 0
    var stackingCount: Int = 0
    var onHoldCount: Int = 0
    var savedForLaterCount: Int = 0
    var finishedCount: Int = 0
    var stoppedCount: Int = 0
    var total: Int {
        readingCount + caughtUpCount + stackingCount + onHoldCount + savedForLaterCount + finishedCount + stoppedCount
    }
}

// MARK: - Taste Insights

nonisolated struct ReadingTasteInsights: Equatable, Sendable {
    nonisolated enum UsualChipKind: String, Equatable, Sendable {
        case metadata
        case fandom
        case tag
        case ship
    }

    nonisolated struct UsualChip: Equatable, Sendable {
        var text: String
        var kind: UsualChipKind
    }

    var usualFicSummary: String = ""
    var usualFicTags: [String] = []
    var usualChips: [UsualChip] = []
    var usualStatus: String = ""
    var usualRating: String = ""
    var usualCategory: String = ""
    var usualLengthBand: String = ""
    var usualSecondTag: String? = nil
    var usualTopTag: String? = nil
    var usualTopFandom: String? = nil
    var usualTopRelationship: String? = nil
    var usualExtraTagNames: [String] = []
    var fandoms: [ReadingInsights.FandomWordsShare] = []
    var relationships: [RelationshipShare] = []
    var shipConcentrations: [ShipConcentration] = []
    var characters: [CharacterShare] = []
    var tags: [TagShare] = []
    var oftenTogether: [TagPair] = []
    var ratings: [CountBreakdown] = []
    var statuses: [CountBreakdown] = []
    var lengthBands: [CountBreakdown] = []
    var categories: [CountBreakdown] = []
    var warnings: [CountBreakdown] = []
    var yearCounts: [YearCount] = []
    var medianYear: Int? = nil
    var crossoverCount: Int = 0
    var totalWorksCount: Int = 0
    var languages: [CountBreakdown] = []
    /// Unfolded per-fandom tallies so `ranked(byWorks:)` can re-fold top 4 + remainder
    /// under either words or works without hiding high-work-count fandoms in the remainder.
    var allFandoms: [FandomTally] = []
    var unattributedFandomWords: Int = 0
    var unattributedFandomWorksCount: Int = 0
    var unattributedFandomWordUnitWorksCount: Int = 0
    /// Unfiltered lists retaining `.characters` works for By Works mode while By Words
    /// filters to `hasWordUnitWorks`.
    var allRelationships: [RelationshipShare] = []
    var allTags: [TagShare] = []

    nonisolated struct FandomTally: Equatable, Sendable {
        var name: String
        var words: Int
        var worksCount: Int
        var wordUnitWorksCount: Int
    }

    nonisolated struct CharacterShare: Equatable, Sendable, Identifiable {
        var id: String { "\(name)-\(fandom)" }
        var name: String
        var count: Int
        var fandom: String
    }

    nonisolated struct TagShare: Equatable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        var words: Int
        var count: Int
        var hasWordUnitWorks: Bool = true
    }

    nonisolated struct CountBreakdown: Equatable, Sendable, Identifiable {
        var id: String { label }
        var label: String
        var count: Int
        var words: Int = 0
    }

    /// Canonical AO3 rating display order for Taste's Rating breakdown.
    static let canonicalRatingsOrder: [String] = [
        "General", "Teen", "Mature", "Explicit", "Not Rated"
    ]

    /// Normalizes AO3 full labels and common shorthands into one bucket before
    /// accumulating counts and words. Unknown non-empty ratings keep their trimmed
    /// label so `ratings` always sums to `totalWorksCount`.
    static func canonicalRating(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Not Rated" }
        let lower = trimmed.lowercased()
        if lower == "g" || lower == "general" || lower.hasPrefix("general audiences") {
            return "General"
        }
        if lower == "t" || lower == "teen" || lower.hasPrefix("teen and up") {
            return "Teen"
        }
        if lower == "m" || lower == "mature" {
            return "Mature"
        }
        if lower == "e" || lower == "explicit" {
            return "Explicit"
        }
        if lower == "nr" || lower == "not rated" || lower == "unrated" {
            return "Not Rated"
        }
        return trimmed
    }

    private static func ratingOrderIndex(for label: String) -> Int {
        canonicalRatingsOrder.firstIndex(of: label) ?? canonicalRatingsOrder.count
    }

    private static func foldFandoms(
        allFandoms: [FandomTally],
        unattributedWords: Int,
        unattributedWorks: Int,
        unattributedWordUnitWorks: Int,
        totalWorksCount: Int,
        byWorks: Bool
    ) -> [ReadingInsights.FandomWordsShare] {
        let limit = ReadingInsights.namedWordsFandomLimit
        if byWorks {
            let ranked = allFandoms.sorted { (lhs: FandomTally, rhs: FandomTally) -> Bool in
                if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
                if lhs.words != rhs.words { return lhs.words > rhs.words }
                return lhs.name < rhs.name
            }
            let totalWorks = max(1, totalWorksCount)
            var shares: [ReadingInsights.FandomWordsShare] = ranked.prefix(limit).map { (tally: FandomTally) in
                ReadingInsights.FandomWordsShare(
                    name: tally.name,
                    words: tally.words,
                    worksCount: tally.worksCount,
                    share: Double(tally.worksCount) / Double(totalWorks),
                    isRemainder: false
                )
            }
            let tail = ranked.dropFirst(limit)
            let remWords = tail.reduce(0) { (sum: Int, tally: FandomTally) -> Int in sum + tally.words } + unattributedWords
            let remWorks = tail.reduce(0) { (sum: Int, tally: FandomTally) -> Int in sum + tally.worksCount } + unattributedWorks
            if remWorks > 0 || remWords > 0 {
                shares.append(ReadingInsights.FandomWordsShare(
                    name: ReadingInsights.remainderName,
                    words: remWords,
                    worksCount: remWorks,
                    share: Double(remWorks) / Double(totalWorks),
                    isRemainder: true
                ))
            }
            return shares
        }

        let eligible = allFandoms.filter { (tally: FandomTally) -> Bool in tally.wordUnitWorksCount > 0 }
        let ranked = eligible.sorted { (lhs: FandomTally, rhs: FandomTally) -> Bool in
            if lhs.words != rhs.words { return lhs.words > rhs.words }
            if lhs.wordUnitWorksCount != rhs.wordUnitWorksCount { return lhs.wordUnitWorksCount > rhs.wordUnitWorksCount }
            return lhs.name < rhs.name
        }
        let namedWords = ranked.reduce(0) { (sum: Int, tally: FandomTally) -> Int in sum + tally.words }
        let totalWords = max(1, namedWords + unattributedWords)
        var shares: [ReadingInsights.FandomWordsShare] = ranked.prefix(limit).map { (tally: FandomTally) in
            ReadingInsights.FandomWordsShare(
                name: tally.name,
                words: tally.words,
                worksCount: tally.wordUnitWorksCount,
                share: Double(tally.words) / Double(totalWords),
                isRemainder: false
            )
        }
        let tail = ranked.dropFirst(limit)
        let remWords = tail.reduce(0) { (sum: Int, tally: FandomTally) -> Int in sum + tally.words } + unattributedWords
        let remWorks = tail.reduce(0) { (sum: Int, tally: FandomTally) -> Int in sum + tally.wordUnitWorksCount } + unattributedWordUnitWorks
        if remWords > 0 || remWorks > 0 {
            shares.append(ReadingInsights.FandomWordsShare(
                name: ReadingInsights.remainderName,
                words: remWords,
                worksCount: remWorks,
                share: Double(remWords) / Double(totalWords),
                isRemainder: true
            ))
        }
        return shares
    }

    /// The tab's single rank toggle applies to every list that has both measures.
    func ranked(byWorks: Bool) -> ReadingTasteInsights {
        var result = self
        if !allFandoms.isEmpty || unattributedFandomWords > 0 || unattributedFandomWorksCount > 0 {
            result.fandoms = Self.foldFandoms(
                allFandoms: allFandoms,
                unattributedWords: unattributedFandomWords,
                unattributedWorks: unattributedFandomWorksCount,
                unattributedWordUnitWorks: unattributedFandomWordUnitWorksCount,
                totalWorksCount: totalWorksCount,
                byWorks: byWorks
            )
        } else {
            result.fandoms = fandoms.sorted { (lhs: ReadingInsights.FandomWordsShare, rhs: ReadingInsights.FandomWordsShare) -> Bool in
                if lhs.isRemainder != rhs.isRemainder { return !lhs.isRemainder }
                if byWorks {
                    if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
                    if lhs.words != rhs.words { return lhs.words > rhs.words }
                } else {
                    if lhs.words != rhs.words { return lhs.words > rhs.words }
                    if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
                }
                return lhs.name < rhs.name
            }
        }

        let sourceRels = allRelationships.isEmpty ? relationships : allRelationships
        let sourceTags = allTags.isEmpty ? tags : allTags
        if byWorks {
            result.relationships = sourceRels.sorted { (lhs: RelationshipShare, rhs: RelationshipShare) -> Bool in
                if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
                if lhs.words != rhs.words { return lhs.words > rhs.words }
                return lhs.name < rhs.name
            }
            result.tags = sourceTags.sorted { (lhs: TagShare, rhs: TagShare) -> Bool in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                if lhs.words != rhs.words { return lhs.words > rhs.words }
                return lhs.name < rhs.name
            }
        } else {
            result.relationships = sourceRels
                .filter(\.hasWordUnitWorks)
                .sorted { (lhs: RelationshipShare, rhs: RelationshipShare) -> Bool in
                    if lhs.words != rhs.words { return lhs.words > rhs.words }
                    if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
                    return lhs.name < rhs.name
                }
            result.tags = sourceTags
                .filter(\.hasWordUnitWorks)
                .sorted { (lhs: TagShare, rhs: TagShare) -> Bool in
                    if lhs.words != rhs.words { return lhs.words > rhs.words }
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                    return lhs.name < rhs.name
                }
        }

        func sorted(_ rows: [CountBreakdown]) -> [CountBreakdown] {
            rows.sorted { (lhs: CountBreakdown, rhs: CountBreakdown) -> Bool in
                if byWorks {
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                    if lhs.words != rhs.words { return lhs.words > rhs.words }
                } else {
                    if lhs.words != rhs.words { return lhs.words > rhs.words }
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                }
                return lhs.label < rhs.label
            }
        }
        // Keep Rating bars in canonical AO3 progression; rank the rest by the active toggle.
        result.ratings = ratings.sorted { (lhs: CountBreakdown, rhs: CountBreakdown) -> Bool in
            let li = Self.ratingOrderIndex(for: lhs.label)
            let ri = Self.ratingOrderIndex(for: rhs.label)
            if li != ri { return li < ri }
            return lhs.label < rhs.label
        }
        result.statuses = sorted(statuses)
        result.lengthBands = sorted(lengthBands)
        result.categories = sorted(categories)
        result.warnings = sorted(warnings)

        guard totalWorksCount >= 5 else {
            result.usualFicSummary = "Read at least five works in this period to find your usual fic."
            result.usualChips = []
            result.usualFicTags = []
            return result
        }
        let totalWeight = max(1, byWorks ? totalWorksCount : result.fandoms.reduce(0) { (sum: Int, share: ReadingInsights.FandomWordsShare) -> Int in sum + share.words })
        func frequent(_ label: String, weight: Int) -> String {
            guard !label.isEmpty else { return "varied" }
            return weight * 10 >= totalWeight * 4 ? label : "varied"
        }
        func top(_ rows: [CountBreakdown]) -> String {
            guard let first = rows.first else { return "varied" }
            return frequent(first.label, weight: byWorks ? first.count : first.words)
        }
        let topRatingRow = result.ratings.min { (lhs: CountBreakdown, rhs: CountBreakdown) -> Bool in
            let lw = byWorks ? lhs.count : lhs.words
            let rw = byWorks ? rhs.count : rhs.words
            if lw != rw { return lw > rw }
            let li = Self.ratingOrderIndex(for: lhs.label)
            let ri = Self.ratingOrderIndex(for: rhs.label)
            if li != ri { return li < ri }
            return lhs.label < rhs.label
        }
        result.usualStatus = top(result.statuses)
        result.usualRating = topRatingRow.map { frequent($0.label, weight: byWorks ? $0.count : $0.words) } ?? "varied"
        result.usualCategory = top(result.categories)
        result.usualLengthBand = top(result.lengthBands)
        let firstFandom = result.fandoms.first { (share: ReadingInsights.FandomWordsShare) -> Bool in !share.isRemainder }
        let fandomWeight = firstFandom.map { byWorks ? $0.worksCount : $0.words } ?? 0
        let fandomName = frequent(firstFandom?.name ?? "", weight: fandomWeight)
        let firstRel = result.relationships.first
        let relWeight = firstRel.map { byWorks ? $0.worksCount : $0.words } ?? 0
        let relationship = frequent(firstRel?.name ?? "", weight: relWeight)
        let tagNames: [String] = Array(result.tags.prefix(2)).map { (tag: TagShare) -> String in
            frequent(tag.name, weight: byWorks ? tag.count : tag.words)
        }
        let firstTag = tagNames.first ?? "varied"
        let secondTag = tagNames.dropFirst().first ?? "varied"
        result.usualTopFandom = fandomName == "varied" ? nil : fandomName
        result.usualTopRelationship = relationship == "varied" ? nil : relationship
        result.usualTopTag = firstTag == "varied" ? nil : firstTag
        result.usualSecondTag = secondTag == "varied" ? nil : secondTag
        result.usualExtraTagNames = result.usualSecondTag.map { [$0] } ?? []
        result.usualChips = [
            UsualChip(text: result.usualStatus, kind: .metadata),
            UsualChip(text: result.usualRating, kind: .metadata),
            UsualChip(text: result.usualCategory, kind: .metadata),
            UsualChip(text: result.usualLengthBand, kind: .metadata),
            UsualChip(text: fandomName, kind: .fandom),
            UsualChip(text: relationship, kind: .ship),
            UsualChip(text: firstTag, kind: .tag),
            UsualChip(text: secondTag, kind: .tag)
        ]
        result.usualFicTags = result.usualChips.map(\.text)
        result.usualFicSummary = "Usually " + result.usualFicTags.joined(separator: " · ") + "."
        return result
    }

    nonisolated struct YearCount: Equatable, Sendable, Identifiable {
        var id: Int { year }
        var year: Int
        var count: Int
    }

    private struct TasteWork {
        var id: UUID
        var fandoms: [String]
        var relationships: [String]
        var characters: [String]
        var freeformTags: [String]
        var rating: String
        var warnings: [String]
        var categories: [String]
        var language: String
        var isComplete: Bool
        var wordCount: Int
        var publishedYear: Int?
        var wordUnit: SavedWork.WordUnit
    }

    private static func tasteWorks(
        from works: [SavedWork],
        facts: [ReadingSessionFacts]
    ) -> [TasteWork] {
        let worksByID = Dictionary(
            works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let factsByWork = Dictionary(grouping: facts, by: \.workID)
        var resolved: [TasteWork] = []
        resolved.reserveCapacity(factsByWork.count)
        let utc = ReadingInsights.utcCalendar

        for (workID, group) in factsByWork {
            let ordered = group.sorted(by: ReadingInsights.sittingOrder)
            let fallbackWordCount = ordered.last(where: { $0.wordCount > 0 })?.wordCount
                ?? ordered.last?.wordCount
                ?? 0
            if let work = worksByID[workID] {
                let pubYear = WorkStat.date(from: work.datePublished).map { utc.component(.year, from: $0) }
                resolved.append(TasteWork(
                    id: work.id,
                    fandoms: work.workFandoms,
                    relationships: work.workRelationships,
                    characters: work.workCharacters,
                    freeformTags: ReadingInsights.freeformTags(of: work),
                    rating: work.rating,
                    warnings: work.workWarnings,
                    categories: work.workCategories,
                    language: work.language,
                    isComplete: work.isComplete,
                    wordCount: work.wordCount > 0 ? work.wordCount : fallbackWordCount,
                    publishedYear: pubYear,
                    wordUnit: work.wordUnit
                ))
            } else {
                // D1 fallback: keep deleted works in Taste via session snapshots.
                guard let latest = ordered.last else { continue }
                let rev = Array(ordered.reversed())
                let snapFandoms = rev.first(where: { !$0.fandoms.isEmpty })?.fandoms
                    ?? (latest.fandom.isEmpty ? [] : [latest.fandom])
                let snapRelationships = rev.first(where: { !$0.relationships.isEmpty })?.relationships ?? []
                let snapCharacters = rev.first(where: { !$0.characters.isEmpty })?.characters ?? []
                let snapFreeforms = rev.first(where: { !$0.freeformTags.isEmpty })?.freeformTags ?? []
                let snapRating = rev.first(where: { !$0.rating.isEmpty })?.rating ?? ""
                let snapWarnings = rev.first(where: { !$0.warnings.isEmpty })?.warnings ?? []
                let snapCategories = rev.first(where: { !$0.categories.isEmpty })?.categories ?? []
                let snapLanguage = rev.first(where: { !$0.language.isEmpty })?.language ?? ""
                let snapPublishedYear = rev.compactMap(\.publishedYear).first
                resolved.append(TasteWork(
                    id: workID,
                    fandoms: snapFandoms,
                    relationships: snapRelationships,
                    characters: snapCharacters,
                    freeformTags: snapFreeforms,
                    rating: snapRating,
                    warnings: snapWarnings,
                    categories: snapCategories,
                    language: snapLanguage,
                    isComplete: latest.isCompleteAtVisit,
                    wordCount: fallbackWordCount,
                    publishedYear: snapPublishedYear,
                    wordUnit: latest.wordUnit
                ))
            }
        }
        return resolved
    }

    static func make(
        works: [SavedWork],
        facts: [ReadingSessionFacts],
        aliases: TagAliasResolver = .empty
    ) -> ReadingTasteInsights {
        let effectiveWorks = tasteWorks(from: works, facts: facts)
        let tasteWorksByID = Dictionary(
            effectiveWorks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var wordsByWork: [UUID: Int] = [:]
        for fact in facts where fact.wordUnit == .words {
            wordsByWork[fact.workID, default: 0] += fact.wordsRead
        }

        // Unfolded fandom tallies across all sittings (words for `.words`, works for all).
        var fandomWordsMap: [String: Int] = [:]
        var fandomAllWorks: [String: Set<UUID>] = [:]
        var fandomWordUnitWorks: [String: Set<UUID>] = [:]
        var unattributedWords = 0
        var unattributedWorks: Set<UUID> = []
        var unattributedWordUnitWorks: Set<UUID> = []

        for fact in facts {
            let fandom = aliases.resolve(fact.fandom, kind: .fandom)
            let isWords = fact.wordUnit == .words
            if fandom.isEmpty {
                unattributedWorks.insert(fact.workID)
                if isWords {
                    unattributedWords += fact.wordsRead
                    unattributedWordUnitWorks.insert(fact.workID)
                }
            } else {
                fandomAllWorks[fandom, default: []].insert(fact.workID)
                if isWords {
                    fandomWordsMap[fandom, default: 0] += fact.wordsRead
                    fandomWordUnitWorks[fandom, default: []].insert(fact.workID)
                }
            }
        }
        var allFandoms: [FandomTally] = []
        allFandoms.reserveCapacity(fandomAllWorks.count)
        for (name, workSet) in fandomAllWorks {
            allFandoms.append(FandomTally(
                name: name,
                words: fandomWordsMap[name] ?? 0,
                worksCount: workSet.count,
                wordUnitWorksCount: fandomWordUnitWorks[name]?.count ?? 0
            ))
        }
        allFandoms.sort { (lhs: FandomTally, rhs: FandomTally) -> Bool in
            if lhs.words != rhs.words { return lhs.words > rhs.words }
            if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
            return lhs.name < rhs.name
        }

        // Global relationship shares (for Relationships list) and per-fandom relationship
        // words (for Ship Concentration, preventing cross-fandom tags from exceeding 100%).
        var relAccum: [String: (fandom: String, works: Set<UUID>, wordUnitWorks: Set<UUID>, words: Int)] = [:]
        var fandomRelWords: [String: [String: (works: Set<UUID>, words: Int)]] = [:]
        for fact in facts {
            let work = tasteWorksByID[fact.workID]
            let resolvedFandom = aliases.resolve(fact.fandom, kind: .fandom)
            let isWords = fact.wordUnit == .words
            let rels = aliases.resolvedUnique(work?.relationships ?? [], kind: .relationship)
            for rel in rels {
                var current = relAccum[rel] ?? (fandom: resolvedFandom, works: [], wordUnitWorks: [], words: 0)
                if current.fandom.isEmpty { current.fandom = resolvedFandom }
                current.works.insert(fact.workID)
                if isWords {
                    current.wordUnitWorks.insert(fact.workID)
                    current.words += fact.wordsRead
                }
                relAccum[rel] = current

                if isWords && !resolvedFandom.isEmpty {
                    var perFandom = fandomRelWords[resolvedFandom] ?? [:]
                    var entry = perFandom[rel] ?? (works: [], words: 0)
                    entry.works.insert(fact.workID)
                    entry.words += fact.wordsRead
                    perFandom[rel] = entry
                    fandomRelWords[resolvedFandom] = perFandom
                }
            }
        }
        var allRelationships: [RelationshipShare] = []
        allRelationships.reserveCapacity(relAccum.count)
        for (key, val) in relAccum {
            allRelationships.append(RelationshipShare(
                name: key,
                isRomantic: ReadingInsights.isRomanticRelationship(key),
                fandom: val.fandom,
                worksCount: val.works.count,
                words: val.words,
                hasWordUnitWorks: !val.wordUnitWorks.isEmpty
            ))
        }
        allRelationships.sort { (lhs: RelationshipShare, rhs: RelationshipShare) -> Bool in
            if lhs.words != rhs.words { return lhs.words > rhs.words }
            if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
            return lhs.name < rhs.name
        }

        var perFandomRelationships: [RelationshipShare] = []
        for (fandom, shipMap) in fandomRelWords {
            for (rel, val) in shipMap {
                perFandomRelationships.append(RelationshipShare(
                    name: rel,
                    isRomantic: ReadingInsights.isRomanticRelationship(rel),
                    fandom: fandom,
                    worksCount: val.works.count,
                    words: val.words
                ))
            }
        }
        let fandomWorkCounts = fandomWordUnitWorks.mapValues { $0.count }
        let shipConcentrations = ReadingInsights.shipConcentrations(
            relationships: perFandomRelationships,
            fandomWords: fandomWordsMap,
            fandomWorkCounts: fandomWorkCounts
        )

        var charCounts: [String: (fandom: String, count: Int)] = [:]
        for work in effectiveWorks {
            let fandom = aliases.resolve(work.fandoms.first ?? "", kind: .fandom)
            for char in aliases.resolvedUnique(work.characters, kind: .character) {
                var cur = charCounts[char] ?? (fandom: fandom, count: 0)
                cur.count += 1
                if cur.fandom.isEmpty { cur.fandom = fandom }
                charCounts[char] = cur
            }
        }
        let characters = charCounts.map { (key: String, val: (fandom: String, count: Int)) -> CharacterShare in
            CharacterShare(name: key, count: val.count, fandom: val.fandom)
        }.sorted { (lhs: CharacterShare, rhs: CharacterShare) -> Bool in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name < rhs.name
        }

        var tagAccum: [String: (words: Int, works: Set<UUID>, wordUnitWorks: Set<UUID>)] = [:]
        for fact in facts {
            let work = tasteWorksByID[fact.workID]
            let isWords = fact.wordUnit == .words
            for tag in aliases.resolvedUnique(work?.freeformTags ?? [], kind: .freeform) {
                var cur = tagAccum[tag] ?? (words: 0, works: [], wordUnitWorks: [])
                cur.works.insert(fact.workID)
                if isWords {
                    cur.words += fact.wordsRead
                    cur.wordUnitWorks.insert(fact.workID)
                }
                tagAccum[tag] = cur
            }
        }
        var allTags: [TagShare] = []
        allTags.reserveCapacity(tagAccum.count)
        for (key, val) in tagAccum {
            allTags.append(TagShare(
                name: key,
                words: val.words,
                count: val.works.count,
                hasWordUnitWorks: !val.wordUnitWorks.isEmpty
            ))
        }
        allTags.sort { (lhs: TagShare, rhs: TagShare) -> Bool in
            if lhs.words != rhs.words { return lhs.words > rhs.words }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name < rhs.name
        }

        let oftenTogether = ReadingInsights.oftenTogetherTags(
            fromTagSets: effectiveWorks.map(\.freeformTags),
            aliases: aliases
        )

        var ratingCounts: [String: Int] = [:]
        var ratingWords: [String: Int] = [:]
        var statusCounts: [String: Int] = [:]
        var statusWords: [String: Int] = [:]
        var lengthCounts: [String: Int] = [:]
        var lengthWords: [String: Int] = [:]
        var catCounts: [String: Int] = [:]
        var catWords: [String: Int] = [:]
        var warnCounts: [String: Int] = [:]
        var warnWords: [String: Int] = [:]
        var yearMap: [Int: Int] = [:]
        var langCounts: [String: Int] = [:]
        let currentYear = ReadingInsights.utcCalendar.component(.year, from: Date())

        for work in effectiveWorks {
            let workWords = wordsByWork[work.id] ?? 0
            let rating = canonicalRating(for: work.rating)
            ratingCounts[rating, default: 0] += 1
            ratingWords[rating, default: 0] += workWords

            let status = work.isComplete ? "Complete" : "Work in Progress"
            statusCounts[status, default: 0] += 1
            statusWords[status, default: 0] += workWords

            let band: String
            switch work.wordCount {
            case ..<5_000: band = "Under 5k"
            case ..<50_000: band = "5–50k"
            case ..<150_000: band = "50–150k"
            default: band = "150k+"
            }
            lengthCounts[band, default: 0] += 1
            lengthWords[band, default: 0] += workWords

            for cat in Set(work.categories) {
                let trimmed = cat.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    catCounts[trimmed, default: 0] += 1
                    catWords[trimmed, default: 0] += workWords
                }
            }

            for w in Set(work.warnings) {
                let trimmed = w.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    warnCounts[trimmed, default: 0] += 1
                    warnWords[trimmed, default: 0] += workWords
                }
            }

            if let y = work.publishedYear, y > 1990 && y <= currentYear {
                yearMap[y, default: 0] += 1
            }

            let l = work.language.trimmingCharacters(in: .whitespacesAndNewlines)
            langCounts[l.isEmpty ? "Unknown" : l, default: 0] += 1
        }

        var ratings: [CountBreakdown] = []
        for label in canonicalRatingsOrder {
            if let count = ratingCounts[label], count > 0 {
                ratings.append(CountBreakdown(label: label, count: count, words: ratingWords[label] ?? 0))
            }
        }
        let extraRatingKeys = ratingCounts.keys
            .filter { (key: String) -> Bool in !canonicalRatingsOrder.contains(key) }
            .sorted()
        for label in extraRatingKeys {
            if let count = ratingCounts[label], count > 0 {
                ratings.append(CountBreakdown(label: label, count: count, words: ratingWords[label] ?? 0))
            }
        }

        let statuses: [CountBreakdown] = statusCounts.map { (label: String, count: Int) in
            CountBreakdown(label: label, count: count, words: statusWords[label] ?? 0)
        }
        let lengthBands: [CountBreakdown] = lengthCounts.map { (label: String, count: Int) in
            CountBreakdown(label: label, count: count, words: lengthWords[label] ?? 0)
        }
        let categories: [CountBreakdown] = catCounts.map { (label: String, count: Int) in
            CountBreakdown(label: label, count: count, words: catWords[label] ?? 0)
        }
        let warnings: [CountBreakdown] = warnCounts.map { (label: String, count: Int) in
            CountBreakdown(label: label, count: count, words: warnWords[label] ?? 0)
        }

        let yearCounts = yearMap.keys.sorted().map { (y: Int) in YearCount(year: y, count: yearMap[y] ?? 0) }
        let allYears = yearMap.flatMap { Array(repeating: $0.key, count: $0.value) }.sorted()
        let medianYear = allYears.isEmpty ? nil : allYears[allYears.count / 2]

        let crossoverCount = effectiveWorks.filter { (work: TasteWork) -> Bool in
            aliases.isCrossover(work.fandoms, bareTitle: FandomDisplayName.bareTitle)
        }.count
        let languages = langCounts.map { (label: String, count: Int) in
            CountBreakdown(label: label, count: count)
        }.sorted { (lhs: CountBreakdown, rhs: CountBreakdown) -> Bool in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.label < rhs.label
        }

        let result = ReadingTasteInsights(
            shipConcentrations: shipConcentrations,
            characters: characters,
            oftenTogether: oftenTogether,
            ratings: ratings,
            statuses: statuses,
            lengthBands: lengthBands,
            categories: categories,
            warnings: warnings,
            yearCounts: yearCounts,
            medianYear: medianYear,
            crossoverCount: crossoverCount,
            totalWorksCount: effectiveWorks.count,
            languages: languages,
            allFandoms: allFandoms,
            unattributedFandomWords: unattributedWords,
            unattributedFandomWorksCount: unattributedWorks.count,
            unattributedFandomWordUnitWorksCount: unattributedWordUnitWorks.count,
            allRelationships: allRelationships,
            allTags: allTags
        )
        return result.ranked(byWorks: false)
    }
}

// MARK: - Habits Insights

nonisolated struct ReadingHabitsInsights: Equatable, Sendable {
    var hourlyDuration: [ReadingInsights.HourlyBucket] = []
    var lateNightDuration: Double = 0
    var lateNightSharePercent: Int = 0
    var calendarDays: [ReadingInsights.DailyWordsBucket] = []
    /// True only when `calendarDays` represents a real contiguous single-month period
    /// (never a Year-mode sparse reading-day list).
    var calendarIsMonthGrid: Bool = false
    var calendarWordThresholds: [Int] = [5_000, 10_000, 20_000]
    var longestStreak: Int = 0
    var sittingBuckets: [ReadingInsights.SittingBucket] = []
    var typicalSittingSeconds: Double = 0
    /// Medians come from the stored dates and log; nil when the data cannot say.
    var savedToOpenedMedianDays: Int?
    var openedToFinishedMedianDays: Int?
    var savedToOpenedCount: Int = 0
    var openedToFinishedCount: Int = 0
    var rereads: [RereadWork] = []
    var rereadTimeShare: Double? = nil
    var fandomTimeline: [FandomTimelineLane] = []
    var fandomTimelineYear: Int = 0
    var stoppedCount: Int = 0
    var stoppedInPeriodCount: Int = 0
    var stopReasons: [StopReasonCount] = []
    var stoppedMedianProgress: Double?
    var commonStopTags: [(name: String, count: Int)] = []

    static func == (lhs: ReadingHabitsInsights, rhs: ReadingHabitsInsights) -> Bool {
        lhs.hourlyDuration == rhs.hourlyDuration
            && lhs.lateNightDuration == rhs.lateNightDuration
            && lhs.lateNightSharePercent == rhs.lateNightSharePercent
            && lhs.calendarDays == rhs.calendarDays
            && lhs.calendarIsMonthGrid == rhs.calendarIsMonthGrid
            && lhs.calendarWordThresholds == rhs.calendarWordThresholds
            && lhs.longestStreak == rhs.longestStreak
            && lhs.sittingBuckets == rhs.sittingBuckets
            && lhs.typicalSittingSeconds == rhs.typicalSittingSeconds
            && lhs.savedToOpenedMedianDays == rhs.savedToOpenedMedianDays
            && lhs.openedToFinishedMedianDays == rhs.openedToFinishedMedianDays
            && lhs.savedToOpenedCount == rhs.savedToOpenedCount
            && lhs.openedToFinishedCount == rhs.openedToFinishedCount
            && lhs.rereads == rhs.rereads
            && lhs.rereadTimeShare == rhs.rereadTimeShare
            && lhs.fandomTimeline == rhs.fandomTimeline
            && lhs.fandomTimelineYear == rhs.fandomTimelineYear
            && lhs.stoppedCount == rhs.stoppedCount
            && lhs.stoppedInPeriodCount == rhs.stoppedInPeriodCount
            && lhs.stopReasons == rhs.stopReasons
            && lhs.stoppedMedianProgress == rhs.stoppedMedianProgress
            && lhs.commonStopTags.elementsEqual(rhs.commonStopTags, by: { $0.name == $1.name && $0.count == $1.count })
    }

    nonisolated struct RereadWork: Equatable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var fandom: String
        var totalWordsAcrossReads: Int
        var finishCount: Int
    }

    nonisolated struct StopReasonCount: Equatable, Sendable, Identifiable {
        var id: String { reason }
        var reason: String
        var count: Int

        var label: String {
            switch reason {
            case "lostInterest": "Lost interest"
            case "tooLong": "Too long"
            case "writingStyle": "Writing style"
            case "tagDealbreaker": "Tag dealbreaker"
            case "gotSpoiled": "Got spoiled"
            case "other": "Other"
            default: reason
            }
        }
    }

    nonisolated struct FandomTimelineLane: Equatable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        var monthlyActivity: [Int]
        /// Exact words behind the heat cells, including months deliberately shown blank.
        var monthlyWords: [Int]
    }

    /// Median of the values; nil when there are none.
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func calendarThresholds(
        allFacts: [ReadingSessionFacts],
        through end: Date,
        calendar: Calendar = .current
    ) -> [Int] {
        let start = calendar.date(byAdding: .month, value: -12, to: end) ?? end
        let window = DateInterval(start: min(start, end), end: max(start, end))
        let historical = allFacts.filter { ReadingInsights.isInPeriod($0, period: window, calendar: calendar) }
        let words = ReadingInsights.dailyWordsBuckets(from: historical, calendar: calendar)
            .map(\.words).filter { $0 > 0 }.sorted()
        guard words.count >= 20 else { return [5_000, 10_000, 20_000] }
        return [words[words.count / 4], words[words.count / 2], words[words.count * 3 / 4]]
    }

    /// `works` are the works whose sittings count (rereads, saved-to-finished);
    /// `libraryWorks` (default `works`) is the saved library the stopped figures describe.
    static func make(
        works: [SavedWork],
        libraryWorks: [SavedWork]? = nil,
        facts: [ReadingSessionFacts],
        allFacts: [ReadingSessionFacts],
        periodInterval: DateInterval? = nil,
        calendar: Calendar = .current,
        aliases: TagAliasResolver = .empty,
        now: Date = Date()
    ) -> ReadingHabitsInsights {
        let hourly = ReadingInsights.hourlyDurationBuckets(from: facts, calendar: calendar)
        let lateNightSec = hourly
            .filter { (bucket: ReadingInsights.HourlyBucket) -> Bool in bucket.hour >= 1 && bucket.hour < 5 }
            .reduce(0.0) { (sum: Double, bucket: ReadingInsights.HourlyBucket) -> Double in sum + bucket.seconds }
        let totalSec = max(1, facts.reduce(0) { $0 + $1.durationSeconds })
        let lateNightPct = Int((lateNightSec / totalSec * 100).rounded())

        let calendarRange = periodInterval.flatMap { (interval: DateInterval) -> DateInterval? in
            ReadingInsights.chartDays(for: interval, now: now, calendar: calendar)
        }
        let calDays = ReadingInsights.dailyWordsBuckets(from: facts, in: calendarRange, calendar: calendar)
        let latestReadingEnd = allFacts
            .map { (fact: ReadingSessionFacts) -> Date in ReadingInsights.readingDay(for: fact, calendar: calendar) }
            .max()
            .flatMap { (day: Date) -> Date? in calendar.date(byAdding: .day, value: 1, to: day) }
        let thresholdEnd = periodInterval?.end ?? latestReadingEnd ?? now
        let thresholds = calendarThresholds(allFacts: allFacts, through: thresholdEnd, calendar: calendar)
        let streak = ReadingInsights.longestStreak(of: facts, calendar: calendar)
        let sittings = ReadingInsights.sittingBuckets(from: facts)
        let typicalSec = ReadingInsights.medianSeconds(of: facts)

        let worksByID = Dictionary(works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var finishCountsByWork: [UUID: (title: String, fandom: String, words: Int, count: Int)] = [:]
        var allWordsByWork: [UUID: Int] = [:]
        for fact in allFacts where fact.wordUnit == .words {
            allWordsByWork[fact.workID, default: 0] += fact.wordsRead
        }
        for fact in allFacts where fact.didFinish {
            guard let work = worksByID[fact.workID] else { continue }
            let cur = finishCountsByWork[fact.workID] ?? (
                title: work.title,
                fandom: aliases.resolve(work.workFandoms.first ?? "", kind: .fandom),
                words: 0,
                count: 0
            )
            finishCountsByWork[fact.workID] = (
                title: cur.title,
                fandom: cur.fandom,
                words: allWordsByWork[fact.workID] ?? 0,
                count: cur.count + 1
            )
        }
        let rereads = finishCountsByWork.filter { $0.value.count > 1 }.map { key, val in
            RereadWork(
                id: key,
                title: val.title,
                fandom: val.fandom,
                totalWordsAcrossReads: val.words,
                finishCount: val.count
            )
        }.sorted { (lhs: RereadWork, rhs: RereadWork) -> Bool in
            if lhs.finishCount != rhs.finishCount { return lhs.finishCount > rhs.finishCount }
            if lhs.totalWordsAcrossReads != rhs.totalWordsAcrossReads { return lhs.totalWordsAcrossReads > rhs.totalWordsAcrossReads }
            return lhs.title < rhs.title
        }

        let periodSessionIDs = Set(facts.compactMap(\.sessionID))
        var alreadyFinished: Set<UUID> = []
        var rereadSeconds = 0.0
        let orderedFacts = allFacts.sorted(by: ReadingInsights.sittingOrder)
        for fact in orderedFacts {
            if let sessionID = fact.sessionID, periodSessionIDs.contains(sessionID),
               alreadyFinished.contains(fact.workID) {
                rereadSeconds += fact.durationSeconds
            }
            if fact.didFinish { alreadyFinished.insert(fact.workID) }
        }
        let rereadShare: Double? = facts.isEmpty ? nil : rereadSeconds / totalSec

        // Fandom Timeline: top 4 named fandoms by words across `timelineYear` (plus remainder),
        // with each month shaded by share of that month's total words (blank below 5,000 words).
        let fallbackTimelineDate = facts.first.map { (fact: ReadingSessionFacts) -> Date in
            ReadingInsights.readingDay(for: fact, calendar: calendar)
        } ?? now
        let timelineYear = calendar.component(.year, from: periodInterval?.start ?? fallbackTimelineDate)
        var totalWordsByMonth = Array(repeating: 0, count: 12)
        var wordsByFandomMonth: [String: [Int]] = [:]
        var yearWordsByFandom: [String: Int] = [:]
        for fact in allFacts where fact.wordUnit == .words {
            let day = ReadingInsights.readingDay(for: fact, calendar: calendar)
            guard calendar.component(.year, from: day) == timelineYear else { continue }
            let month = calendar.component(.month, from: day) - 1
            guard (0..<12).contains(month) else { continue }
            totalWordsByMonth[month] += fact.wordsRead
            let fandom = aliases.resolve(fact.fandom, kind: .fandom)
            if !fandom.isEmpty {
                var monthly = wordsByFandomMonth[fandom] ?? Array(repeating: 0, count: 12)
                monthly[month] += fact.wordsRead
                wordsByFandomMonth[fandom] = monthly
                yearWordsByFandom[fandom, default: 0] += fact.wordsRead
            }
        }
        let topFandomNames: [String] = yearWordsByFandom
            .sorted { (lhs: (key: String, value: Int), rhs: (key: String, value: Int)) -> Bool in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(ReadingInsights.namedWordsFandomLimit)
            .map(\.key)
        func timelineTiers(for monthlyWords: [Int]) -> [Int] {
            monthlyWords.enumerated().map { (index: Int, words: Int) -> Int in
                let monthTotal = totalWordsByMonth[index]
                guard monthTotal >= 5_000, words > 0 else { return 0 }
                let share = Double(words) / Double(monthTotal)
                if share < 0.25 { return 1 }
                if share < 0.60 { return 2 }
                return 3
            }
        }
        var timelineLanes: [FandomTimelineLane] = topFandomNames.map { (name: String) -> FandomTimelineLane in
            let months = wordsByFandomMonth[name] ?? Array(repeating: 0, count: 12)
            return FandomTimelineLane(
                name: name,
                monthlyActivity: timelineTiers(for: months),
                monthlyWords: months
            )
        }
        var remainderWords = totalWordsByMonth
        for lane in timelineLanes {
            for index in 0..<12 { remainderWords[index] -= lane.monthlyWords[index] }
        }
        if remainderWords.contains(where: { (w: Int) -> Bool in w > 0 }) {
            timelineLanes.append(FandomTimelineLane(
                name: ReadingInsights.remainderName,
                monthlyActivity: timelineTiers(for: remainderWords),
                monthlyWords: remainderWords
            ))
        }

        let stoppedWorks = (libraryWorks ?? works).filter { $0.insightsReadingStatus == .stopped }
        let stoppedCount = stoppedWorks.count
        let stoppedInPeriod = stoppedWorks.filter { (work: SavedWork) -> Bool in
            guard let periodInterval, let stoppedAt = work.stoppedAt else { return false }
            return stoppedAt >= periodInterval.start && stoppedAt < periodInterval.end
        }.count
        var reasonCounts: [String: Int] = [:]
        for work in stoppedWorks where !work.stopReasonRaw.isEmpty {
            reasonCounts[work.stopReasonRaw, default: 0] += 1
        }
        var stopReasons: [StopReasonCount] = []
        for (reason, count) in reasonCounts {
            stopReasons.append(StopReasonCount(reason: reason, count: count))
        }
        stopReasons.sort { (lhs: StopReasonCount, rhs: StopReasonCount) -> Bool in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.label < rhs.label
        }

        let stoppedMedianProgress = median(stoppedWorks.compactMap(\.readingProgress))

        let openedWorks = (libraryWorks ?? works).filter(\.hasStartedReading)
        let stoppedOpenedWorks = stoppedWorks.filter(\.hasStartedReading)
        var stopTags: [String: Int] = [:]
        for work in stoppedOpenedWorks {
            for tag in ReadingInsights.stopTags(of: work, aliases: aliases) {
                stopTags[tag, default: 0] += 1
            }
        }
        var openedTagCounts: [String: Int] = [:]
        for work in openedWorks {
            for tag in ReadingInsights.stopTags(of: work, aliases: aliases) {
                openedTagCounts[tag, default: 0] += 1
            }
        }
        let overallStoppedShare = Double(stoppedOpenedWorks.count) / Double(max(1, openedWorks.count))
        let commonStopTags = stopTags.filter { tag, stoppedWithTag in
            guard let openedWithTag = openedTagCounts[tag], openedWithTag >= 5 else { return false }
            let tagStoppedShare = Double(stoppedWithTag) / Double(openedWithTag)
            return tagStoppedShare >= 2 * overallStoppedShare
        }.map { (name: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name < $1.name
            }
            .prefix(3)
            .map { $0 }

        // First sitting and first-ever finish per work from the whole log.
        // Owner review: `openedToFinished` counts only complete works whose *first-ever*
        // finish falls in the period, excluding WIPs and later reread finishes.
        var firstSittingFact: [UUID: ReadingSessionFacts] = [:]
        var firstFinishFact: [UUID: ReadingSessionFacts] = [:]
        for fact in allFacts {
            if let existing = firstSittingFact[fact.workID] {
                if ReadingInsights.sittingOrder(fact, existing) {
                    firstSittingFact[fact.workID] = fact
                }
            } else {
                firstSittingFact[fact.workID] = fact
            }
            if fact.didFinish {
                if let existing = firstFinishFact[fact.workID] {
                    if ReadingInsights.sittingOrder(fact, existing) {
                        firstFinishFact[fact.workID] = fact
                    }
                } else {
                    firstFinishFact[fact.workID] = fact
                }
            }
        }
        let openedInPeriod = Set(facts.map(\.workID))
        let finishedInPeriod = Set(facts.filter(\.didFinish).map(\.workID))
        let secondsPerDay = 86_400.0
        let savedToOpened = works.compactMap { (work: SavedWork) -> Double? in
            guard let firstFact = firstSittingFact[work.id] else { return nil }
            let firstIsInPeriod: Bool = periodInterval.map { (interval: DateInterval) -> Bool in
                ReadingInsights.isInPeriod(firstFact, period: interval, calendar: calendar)
            } ?? openedInPeriod.contains(work.id)
            guard firstIsInPeriod else { return nil }
            return max(0, firstFact.startedAt.timeIntervalSince(work.dateAdded)) / secondsPerDay
        }
        let openedToFinished = works.compactMap { (work: SavedWork) -> Double? in
            guard work.isComplete,
                  let first = firstSittingFact[work.id]?.startedAt,
                  let firstFinish = firstFinishFact[work.id]
            else { return nil }
            let finishIsInPeriod: Bool
            if let interval = periodInterval {
                finishIsInPeriod = ReadingInsights.isInPeriod(firstFinish, period: interval, calendar: calendar)
            } else if let sid = firstFinish.sessionID {
                finishIsInPeriod = periodSessionIDs.contains(sid)
            } else {
                finishIsInPeriod = finishedInPeriod.contains(work.id) && facts.contains(firstFinish)
            }
            guard finishIsInPeriod else { return nil }
            return max(0, firstFinish.startedAt.timeIntervalSince(first)) / secondsPerDay
        }

        return ReadingHabitsInsights(
            hourlyDuration: hourly,
            lateNightDuration: lateNightSec,
            lateNightSharePercent: lateNightPct,
            calendarDays: calDays,
            calendarIsMonthGrid: calendarRange != nil,
            calendarWordThresholds: thresholds,
            longestStreak: streak,
            sittingBuckets: sittings,
            typicalSittingSeconds: typicalSec,
            savedToOpenedMedianDays: median(savedToOpened).map { Int($0.rounded()) },
            openedToFinishedMedianDays: median(openedToFinished).map { Int($0.rounded()) },
            savedToOpenedCount: savedToOpened.count,
            openedToFinishedCount: openedToFinished.count,
            rereads: rereads,
            rereadTimeShare: rereadShare,
            fandomTimeline: timelineLanes,
            fandomTimelineYear: timelineYear,
            stoppedCount: stoppedCount,
            stoppedInPeriodCount: stoppedInPeriod,
            stopReasons: stopReasons,
            stoppedMedianProgress: stoppedMedianProgress,
            commonStopTags: Array(commonStopTags)
        )
    }
}

// MARK: - Library Insights

nonisolated struct ReadingLibraryInsights: Equatable, Sendable {
    nonisolated struct AuthorRow: Equatable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        var works: Int
        var words: Int
        var finished: Int
    }
    nonisolated struct ArrivalRow: Equatable, Sendable, Identifiable {
        var id: String { label }
        var label: String
        var finished: Int
        var saved: Int

        func finishedSharePercent(totalFinished: Int) -> Int {
            guard totalFinished > 0 else { return 0 }
            return Int((Double(finished) / Double(totalFinished) * 100).rounded())
        }

        var finishRatePercent: Int {
            guard saved > 0 else { return 0 }
            return Int((Double(finished) / Double(saved) * 100).rounded())
        }
    }
    nonisolated struct FoundEarlyExample: Equatable, Sendable {
        var workID: UUID
        var title: String
        var kudosAtSave: Int
        var kudosNow: Int
    }

    nonisolated struct LongestFinishedSeries: Equatable, Sendable {
        var seriesID: Int
        var title: String
        var partCount: Int
        var wordCount: Int
    }

    var unreadWords: Int = 0
    var unreadWorksCount: Int = 0
    var monthsToClear: Int? = nil
    var monthsToClearRange: ClosedRange<Int>?
    var addedWordsInPeriod: Int = 0
    var readWordsInPeriod: Int = 0
    var statuses: ReadingStatusPartition = ReadingStatusPartition()
    var stillReadingCandidate: StillReadingCandidate? = nil
    var wipFreshness: WIPFreshness = WIPFreshness()
    var noLongerOnAO3Count: Int = 0
    var noLongerOnAO3Words: Int = 0
    var noLongerOnAO3LastCopies: Int = 0
    /// Share of finished works still on AO3 with known kudos; nil with no eligible works.
    var kudosLeftPercent: Int?
    var bookmarkedPercent: Int?
    var arrivalRows: [ArrivalRow] = []
    var arrivalSince: Date?
    var foundEarlyRecordedFinishedCount: Int = 0
    var foundEarlyCount: Int = 0
    var foundEarlyShare: Double?
    var foundEarlyGrownCount: Int = 0
    var foundEarlyGrowthShare: Double?
    var foundEarlySince: Date?
    var foundEarlyExampleItem: FoundEarlyExample?
    var foundEarlyExample: String?
    var favoriteWithoutKudosCount: Int = 0
    var seriesStartedCount: Int = 0
    var seriesReadToLastCount: Int = 0
    var seriesNextWaitingCount: Int = 0
    var longestFinishedSeries: LongestFinishedSeries?
    var authors: [AuthorRow] = []

    static func == (lhs: ReadingLibraryInsights, rhs: ReadingLibraryInsights) -> Bool {
        lhs.unreadWords == rhs.unreadWords
            && lhs.unreadWorksCount == rhs.unreadWorksCount
            && lhs.monthsToClear == rhs.monthsToClear
            && lhs.monthsToClearRange == rhs.monthsToClearRange
            && lhs.addedWordsInPeriod == rhs.addedWordsInPeriod
            && lhs.readWordsInPeriod == rhs.readWordsInPeriod
            && lhs.statuses == rhs.statuses
            && lhs.stillReadingCandidate == rhs.stillReadingCandidate
            && lhs.wipFreshness == rhs.wipFreshness
            && lhs.noLongerOnAO3Count == rhs.noLongerOnAO3Count
            && lhs.noLongerOnAO3Words == rhs.noLongerOnAO3Words
            && lhs.noLongerOnAO3LastCopies == rhs.noLongerOnAO3LastCopies
            && lhs.kudosLeftPercent == rhs.kudosLeftPercent
            && lhs.bookmarkedPercent == rhs.bookmarkedPercent
            && lhs.arrivalRows == rhs.arrivalRows
            && lhs.arrivalSince == rhs.arrivalSince
            && lhs.foundEarlyRecordedFinishedCount == rhs.foundEarlyRecordedFinishedCount
            && lhs.foundEarlyCount == rhs.foundEarlyCount
            && lhs.foundEarlyShare == rhs.foundEarlyShare
            && lhs.foundEarlyGrownCount == rhs.foundEarlyGrownCount
            && lhs.foundEarlyGrowthShare == rhs.foundEarlyGrowthShare
            && lhs.foundEarlySince == rhs.foundEarlySince
            && lhs.foundEarlyExampleItem == rhs.foundEarlyExampleItem
            && lhs.foundEarlyExample == rhs.foundEarlyExample
            && lhs.favoriteWithoutKudosCount == rhs.favoriteWithoutKudosCount
            && lhs.seriesStartedCount == rhs.seriesStartedCount
            && lhs.seriesReadToLastCount == rhs.seriesReadToLastCount
            && lhs.seriesNextWaitingCount == rhs.seriesNextWaitingCount
            && lhs.longestFinishedSeries == rhs.longestFinishedSeries
            && lhs.authors == rhs.authors
    }

    private static func locatorTitle(from locator: String) -> String? {
        guard !locator.isEmpty,
              let data = locator.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["title"] as? String
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated struct StillReadingCandidate: Equatable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var fandom: String
        var chapterProgress: String
        /// Discreet Mode variant omitting free-text Readium chapter titles.
        var discreetChapterProgress: String = ""
        /// Nil when the work has no stored position; nothing is guessed.
        var progressPercent: Int?
        var daysUntouched: Int
    }

    static func make(
        works: [SavedWork],
        readingWorks: [SavedWork]? = nil,
        facts: [ReadingSessionFacts],
        allFacts: [ReadingSessionFacts] = [],
        seriesSnapshots: [SavedSeriesSnapshot] = [],
        periodInterval: DateInterval,
        periodMonths: Double = 1,
        calendar: Calendar = .current,
        aliases: TagAliasResolver = .empty,
        askAboutUntouched: Bool = true,
        untouchedDays: Int = InsightsOptions.defaultUntouchedDays,
        now: Date = Date()
    ) -> ReadingLibraryInsights {
        let unread = works.filter { $0.insightsReadingStatus == .savedForLater }
        let unreadWords = unread.filter { $0.wordUnit == .words }.reduce(0) { $0 + max(0, $1.wordCount) }
        let readWordsInPeriod = facts.filter { $0.wordUnit == .words }.reduce(0) { $0 + $1.wordsRead }

        let addedInPeriod = works.filter { periodInterval.contains($0.dateAdded) }
        let addedWordsInPeriod = addedInPeriod.filter { $0.wordUnit == .words }
            .reduce(0) { $0 + max(0, $1.wordCount) }

        // Nil without reading in the period; the pace is per month, so a Year
        // period's words are divided by its 12 months first.
        var monthsToClear: Int? = unreadWords > 0 && readWordsInPeriod > 0
            ? max(1, Int((Double(unreadWords) / (Double(readWordsInPeriod) / max(1, periodMonths))).rounded()))
            : nil
        var monthsRange: ClosedRange<Int>?
        if !allFacts.isEmpty {
            let todayStart = calendar.startOfDay(for: now)
            let windowEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
            let windowStart = calendar.date(byAdding: .day, value: -90, to: windowEnd) ?? now
            let recentWindow = DateInterval(start: min(windowStart, windowEnd), end: max(windowStart, windowEnd))
            let recent = allFacts.filter { ReadingInsights.isInPeriod($0, period: recentWindow, calendar: calendar) }
            let readingDays = Set(recent.map { ReadingInsights.readingDay(for: $0, calendar: calendar) })
            let words = recent.filter { $0.wordUnit == .words }.reduce(0) { $0 + $1.wordsRead }
            monthsToClear = nil
            if unreadWords > 0 && words > 0 && readingDays.count >= 7 {
                // Anchor elapsed days on earliest history (not earliest in-window sitting)
                // clamped to 90 days, so a reading break inside the last 90 days cannot
                // shrink the denominator and inflate the daily average.
                let historyDays = allFacts
                    .map { ReadingInsights.readingDay(for: $0, calendar: calendar) }
                    .filter { $0 < windowEnd }
                let earliestDay = historyDays.min() ?? todayStart
                let spanDays = (calendar.dateComponents([.day], from: earliestDay, to: todayStart).day ?? 0) + 1
                let elapsed = max(1, min(90, spanDays))
                let averagePerDay = Double(words) / Double(elapsed)
                let estimate = Double(unreadWords) / (averagePerDay * 30.0)
                if readingDays.count >= 30 {
                    monthsToClear = max(1, Int(estimate.rounded()))
                } else {
                    // Owner review: sparse 7–29 day pace uses a symmetric ±25%
                    // band, rounded outward to whole months. The board gives no formula.
                    let low = max(1, Int((estimate * 0.75).rounded(.down)))
                    let high = max(low, Int((estimate * 1.25).rounded(.up)))
                    monthsRange = low...high
                }
            }
        }

        let statuses = ReadingInsights.partitionStatuses(works: works, now: now)
        // isAbandoned already checks `0.05 < readingProgress < 0.95` and `lastReadDate`,
        // and `!isCaughtUpOnWIP` excludes WIPs caught up on every posted chapter, so
        // single-chapter works, mid-final-chapter pauses, and local EPUBs without AO3
        // `chapters` remain eligible.
        let untouchedThreshold = TimeInterval(InsightsOptions.clampUntouchedDays(untouchedDays)) * 86_400
        let candidateWork: SavedWork? = askAboutUntouched
            ? works.first { (work: SavedWork) -> Bool in
                ReadingLogService.isAbandoned(work: work, now: now, threshold: untouchedThreshold)
                    && work.lastReadDate != nil
                    && !work.isCaughtUpOnWIP
                    && work.insightsReadingStatus != .stopped
                    && work.insightsReadingStatus != .onHold
                    && work.insightsReadingStatus != .stacking
            }
            : nil
        let candidate: StillReadingCandidate? = candidateWork.map { (w: SavedWork) -> StillReadingCandidate in
            let progress = w.readingProgress.map { Int(($0 * 100).rounded()) }
            var parts: [String] = []
            var discreetParts: [String] = []
            // The reader's convention: "Chapter 4 of 10" names the work's total when AO3 knows it, else just "Chapter 4".
            let currentChapter: Int = min(w.postedChapterCount, max(1, w.lastSpineIndex + 1))
            let numericChapter: String? = w.postedChapterCount > 0
                ? (SavedWork.totalChapterCount(from: w.chapters).map { (total: Int) -> String in "Chapter \(currentChapter) of \(total)" } ?? "Chapter \(currentChapter)")
                : nil
            if let title = locatorTitle(from: w.readiumLocator) {
                parts.append(title)
            } else if let numericChapter {
                parts.append(numericChapter)
            }
            if let numericChapter {
                discreetParts.append(numericChapter)
            }
            if let progress {
                parts.append("\(progress)%")
                discreetParts.append("\(progress)%")
            }
            let chapterProgress = parts.isEmpty ? "In progress" : parts.joined(separator: " · ")
            let discreetChapterProgress = discreetParts.isEmpty ? "In progress" : discreetParts.joined(separator: " · ")
            let days = w.lastReadDate.flatMap { calendar.dateComponents([.day], from: $0, to: now).day } ?? 0
            return StillReadingCandidate(
                id: w.id,
                title: w.title,
                fandom: aliases.resolve(w.workFandoms.first ?? "", kind: .fandom),
                chapterProgress: chapterProgress,
                discreetChapterProgress: discreetChapterProgress,
                progressPercent: progress,
                daysUntouched: max(1, days)
            )
        }

        let wip = ReadingInsights.wipFreshness(works: works, now: now, calendar: calendar)

        let goneWorks = works.filter { $0.preservationState == .preservedLastCopy || $0.preservationState == .goneWithNoCopy }
        let goneWords = goneWorks.filter { $0.wordUnit == .words }.reduce(0) { $0 + max(0, $1.wordCount) }
        let lastCopies = works.filter { $0.preservationState == .preservedLastCopy }.count

        let finished = works.filter(\.isFinished)
        let onAO3 = finished.filter { (work: SavedWork) -> Bool in
            work.origin == .archiveOfOurOwn && work.preservationState == .available
        }
        let kudosPct: Int? = onAO3.isEmpty ? nil
            : Int(Double(onAO3.filter(\.hasGivenKudos).count) / Double(onAO3.count) * 100)
        let bookmarkPct: Int? = finished.isEmpty ? nil
            : Int(Double(finished.filter(\.isFavorite).count) / Double(finished.count) * 100)

        var arrivals: [WorkImportSource: (saved: Int, finished: Int)] = [:]
        var arrivalSince: Date?
        for work in works {
            guard let source = work.importSource else { continue }
            var counts = arrivals[source] ?? (saved: 0, finished: 0)
            counts.saved += 1
            if work.isFinished { counts.finished += 1 }
            arrivals[source] = counts
            if let date = work.importSourceSince {
                arrivalSince = min(arrivalSince ?? date, date)
            }
        }
        var grouped: [String: (saved: Int, finished: Int)] = [:]
        for (source, counts) in arrivals {
            let label = counts.saved < 5 ? "Other" : source.label
            var total = grouped[label] ?? (saved: 0, finished: 0)
            total.saved += counts.saved
            total.finished += counts.finished
            grouped[label] = total
        }
        // Owner review: hide the card when zero recorded works are finished and omit
        // sources with zero finished works rather than showing 0% share rows.
        let totalArrivedFinished = grouped.values.reduce(0) { (sum: Int, item: (saved: Int, finished: Int)) -> Int in
            sum + item.finished
        }
        var arrivalRows: [ArrivalRow] = []
        if totalArrivedFinished > 0 {
            arrivalRows.reserveCapacity(grouped.count)
            for (label, counts) in grouped where counts.finished > 0 {
                arrivalRows.append(ArrivalRow(label: label, finished: counts.finished, saved: counts.saved))
            }
            arrivalRows.sort { (lhs: ArrivalRow, rhs: ArrivalRow) -> Bool in
                if lhs.finished != rhs.finished { return lhs.finished > rhs.finished }
                return lhs.label < rhs.label
            }
        } else {
            arrivalSince = nil
        }

        let recordedFinished = finished.filter { (work: SavedWork) -> Bool in
            work.statsSavedAt != nil && work.kudosAtSave != nil
        }
        let foundEarlySince = recordedFinished.compactMap(\.statsSavedAt).min()
        let foundEarly = recordedFinished.filter { (work: SavedWork) -> Bool in
            (work.kudosAtSave ?? Int.max) < 500
        }
        let foundEarlyShare: Double? = recordedFinished.isEmpty
            ? nil : Double(foundEarly.count) / Double(recordedFinished.count)
        let grown = foundEarly.filter { (work: SavedWork) -> Bool in
            work.kudos >= 3 * max(1, work.kudosAtSave ?? 0)
        }
        let grownShare: Double? = foundEarly.isEmpty
            ? nil : Double(grown.count) / Double(foundEarly.count)
        // Owner review: showcase the early-found work with the highest kudos growth ratio
        // (`kudosNow / max(kudosAtSave, 1)`, tie-broken by `kudosNow` then `title`) among
        // works that actually gained kudos (`kudos > kudosAtSave`), never a 0-growth work.
        let growingCandidates = foundEarly.filter { (work: SavedWork) -> Bool in
            work.kudos > (work.kudosAtSave ?? 0)
        }
        let bestExampleWork: SavedWork? = growingCandidates.max { (lhs: SavedWork, rhs: SavedWork) -> Bool in
            let lhsGrowth = Double(lhs.kudos) / Double(max(lhs.kudosAtSave ?? 0, 1))
            let rhsGrowth = Double(rhs.kudos) / Double(max(rhs.kudosAtSave ?? 0, 1))
            if lhsGrowth != rhsGrowth { return lhsGrowth < rhsGrowth }
            if lhs.kudos != rhs.kudos { return lhs.kudos < rhs.kudos }
            return lhs.title > rhs.title
        }
        let exampleItem: FoundEarlyExample? = bestExampleWork.map { (work: SavedWork) -> FoundEarlyExample in
            FoundEarlyExample(
                workID: work.id,
                title: work.title,
                kudosAtSave: work.kudosAtSave ?? 0,
                kudosNow: work.kudos
            )
        }
        let example = exampleItem.map { "\($0.title) · \($0.kudosAtSave) then, \($0.kudosNow) now" }

        let finishCounts = Dictionary(grouping: allFacts.filter(\.didFinish), by: \.workID)
            .mapValues(\.count)
        let favoriteWithoutKudos = onAO3.filter { (work: SavedWork) -> Bool in
            !work.hasGivenKudos && (work.isFavorite || (finishCounts[work.id] ?? 0) > 1)
        }.count

        let authorWorks = readingWorks ?? works
        let seriesByID = Dictionary(seriesSnapshots.map { ($0.ao3SeriesID, $0) },
            uniquingKeysWith: { first, _ in first })
        var readPartsBySeries: [Int: Set<Int>] = [:]
        var finishedPartsBySeries: [Int: Set<Int>] = [:]
        var readAO3WorkIDs: Set<Int> = []
        var finishedAO3WorkIDs: Set<Int> = []
        var seriesWordFallback: [Int: [Int: Int]] = [:]
        var seriesTitleFallback: [Int: String] = [:]

        for work in authorWorks {
            let started = work.hasStartedReading || work.isFinished
            let workFinished = work.isFinished || (finishCounts[work.id] ?? 0) > 0
            if started, let ao3ID = work.ao3WorkID { readAO3WorkIDs.insert(ao3ID) }
            if workFinished, let ao3ID = work.ao3WorkID { finishedAO3WorkIDs.insert(ao3ID) }
            guard started, let seriesID = work.ao3SeriesID else { continue }
            if readPartsBySeries[seriesID] == nil { readPartsBySeries[seriesID] = [] }
            if work.seriesPosition > 0 {
                readPartsBySeries[seriesID, default: []].insert(work.seriesPosition)
                if workFinished {
                    finishedPartsBySeries[seriesID, default: []].insert(work.seriesPosition)
                }
                if work.wordUnit == .words {
                    let prev = seriesWordFallback[seriesID]?[work.seriesPosition] ?? 0
                    seriesWordFallback[seriesID, default: [:]][work.seriesPosition] = max(prev, max(0, work.wordCount))
                }
            }
            if !work.seriesTitle.isEmpty && seriesTitleFallback[seriesID] == nil {
                seriesTitleFallback[seriesID] = work.seriesTitle
            }
        }
        for fact in allFacts {
            if let ao3ID = fact.ao3WorkID {
                readAO3WorkIDs.insert(ao3ID)
                if fact.didFinish { finishedAO3WorkIDs.insert(ao3ID) }
            }
            guard let seriesID = fact.ao3SeriesID else { continue }
            if readPartsBySeries[seriesID] == nil { readPartsBySeries[seriesID] = [] }
            if fact.seriesPosition > 0 {
                readPartsBySeries[seriesID, default: []].insert(fact.seriesPosition)
                if fact.didFinish {
                    finishedPartsBySeries[seriesID, default: []].insert(fact.seriesPosition)
                }
                if fact.wordUnit == .words {
                    let prev = seriesWordFallback[seriesID]?[fact.seriesPosition] ?? 0
                    seriesWordFallback[seriesID, default: [:]][fact.seriesPosition] = max(prev, max(0, fact.wordCount))
                }
            }
        }
        for (seriesID, snapshot) in seriesByID {
            for (index, partWorkID) in snapshot.partWorkIDs.enumerated() where partWorkID > 0 {
                let position = index + 1
                if readAO3WorkIDs.contains(partWorkID) {
                    readPartsBySeries[seriesID, default: []].insert(position)
                }
                if finishedAO3WorkIDs.contains(partWorkID) {
                    finishedPartsBySeries[seriesID, default: []].insert(position)
                }
            }
        }

        let startedSeries = Set(readPartsBySeries.keys)
        let readToLast = startedSeries.filter { (id: Int) -> Bool in
            guard let lastPart = seriesByID[id]?.effectivePartCount, lastPart > 0 else { return false }
            return finishedPartsBySeries[id]?.contains(lastPart) == true
        }
        var longestFinishedSeries: LongestFinishedSeries?
        for id in readToLast {
            let snapshot = seriesByID[id]
            let title = (snapshot?.title.isEmpty == false ? snapshot?.title : nil)
                ?? seriesTitleFallback[id]
                ?? ""
            guard !title.isEmpty else { continue }
            let partCount = snapshot?.effectivePartCount ?? (finishedPartsBySeries[id]?.count ?? 0)
            let fallbackWords = seriesWordFallback[id]?.values.reduce(0, +) ?? 0
            let wordCount = (snapshot?.wordCount ?? 0) > 0 ? (snapshot?.wordCount ?? 0) : fallbackWords
            let candidateSeries = LongestFinishedSeries(
                seriesID: id,
                title: title,
                partCount: partCount,
                wordCount: wordCount
            )
            if let current = longestFinishedSeries {
                let isBetter: Bool
                if candidateSeries.wordCount != current.wordCount {
                    isBetter = candidateSeries.wordCount > current.wordCount
                } else if candidateSeries.partCount != current.partCount {
                    isBetter = candidateSeries.partCount > current.partCount
                } else {
                    isBetter = candidateSeries.title < current.title
                }
                if isBetter { longestFinishedSeries = candidateSeries }
            } else {
                longestFinishedSeries = candidateSeries
            }
        }
        // Owner review: Next Part Waiting requires the highest read part in the series
        // to be finished, and ensures the next part is not already started/finished in
        // library, queue-only, or deleted history before counting it as waiting.
        let nextWaiting = startedSeries.filter { (id: Int) -> Bool in
            let readPositions = readPartsBySeries[id] ?? []
            guard let highest = readPositions.max(), highest > 0 else { return false }
            guard finishedPartsBySeries[id]?.contains(highest) == true else { return false }
            let nextPosition = highest + 1
            if readPositions.contains(nextPosition) { return false }
            let snapshot = seriesByID[id]
            let nextWorkID: Int?
            if let snapshot, snapshot.partWorkIDs.count >= nextPosition,
               snapshot.partWorkIDs[nextPosition - 1] > 0 {
                nextWorkID = snapshot.partWorkIDs[nextPosition - 1]
            } else {
                nextWorkID = nil
            }
            if let nextWorkID, readAO3WorkIDs.contains(nextWorkID) { return false }
            let savedNext = works.contains { (work: SavedWork) -> Bool in
                work.ao3SeriesID == id && work.seriesPosition == nextPosition
                    && !work.hasStartedReading && !work.isFinished
            }
            return savedNext || nextWorkID != nil
        }

        let wordsByWork = Dictionary(grouping: allFacts, by: \.workID)
            .mapValues { $0.reduce(0) { $0 + ($1.wordUnit == .words ? $1.wordsRead : 0) } }
        var authorTotals: [String: (works: Int, words: Int, finished: Int)] = [:]
        let liveWorkIDs = Set(authorWorks.map(\.id))
        for work in authorWorks where wordsByWork[work.id] != nil {
            let names = Set(work.verifiedAuthorIdentities.compactMap { identity -> String? in
                guard identity.kind == .registered, let username = identity.username,
                      !ReadingInsights.isExcludedAuthorByline(username) else { return nil }
                return username
            })
            for name in names {
                var total = authorTotals[name] ?? (works: 0, words: 0, finished: 0)
                total.works += 1
                total.words += wordsByWork[work.id] ?? 0
                if work.isFinished { total.finished += 1 }
                authorTotals[name] = total
            }
        }
        let deletedFacts = allFacts.filter { !liveWorkIDs.contains($0.workID) }
        let deletedByWork = Dictionary(grouping: deletedFacts, by: \.workID)
        for (_, sessions) in deletedByWork {
            // Only deleted AO3 works appear in Library -> Authors; deleted non-AO3 local
            // EPUBs have no AO3 account and must stay excluded just as they are while live.
            let isAO3Work = sessions.contains { (fact: ReadingSessionFacts) -> Bool in
                fact.ao3WorkID != nil || WorkOrigin.detect(sourceURL: fact.sourceURL) == .archiveOfOurOwn
            }
            guard isAO3Work else { continue }
            let names = Set(
                sessions.flatMap(\.authorAccounts).compactMap { (raw: String) -> String? in
                    ReadingInsights.normalizedAO3AuthorAccount(from: raw)
                }
            )
            let words = sessions.reduce(0) { total, fact in
                total + (fact.wordUnit == .words ? fact.wordsRead : 0)
            }
            let finished = sessions.contains(where: \.didFinish)
            for name in names {
                var total = authorTotals[name] ?? (works: 0, words: 0, finished: 0)
                total.works += 1
                total.words += words
                if finished { total.finished += 1 }
                authorTotals[name] = total
            }
        }
        var authors: [AuthorRow] = []
        authors.reserveCapacity(authorTotals.count)
        for (name, total) in authorTotals {
            authors.append(AuthorRow(name: name, works: total.works, words: total.words, finished: total.finished))
        }
        authors.sort { (lhs: AuthorRow, rhs: AuthorRow) -> Bool in
            if lhs.works != rhs.works { return lhs.works > rhs.works }
            return lhs.name < rhs.name
        }

        return ReadingLibraryInsights(
            unreadWords: unreadWords,
            unreadWorksCount: unread.count,
            monthsToClear: monthsToClear,
            monthsToClearRange: monthsRange,
            addedWordsInPeriod: addedWordsInPeriod,
            readWordsInPeriod: readWordsInPeriod,
            statuses: statuses,
            stillReadingCandidate: candidate,
            wipFreshness: wip,
            noLongerOnAO3Count: goneWorks.count,
            noLongerOnAO3Words: goneWords,
            noLongerOnAO3LastCopies: lastCopies,
            kudosLeftPercent: kudosPct,
            bookmarkedPercent: bookmarkPct,
            arrivalRows: arrivalRows,
            arrivalSince: arrivalSince,
            foundEarlyRecordedFinishedCount: recordedFinished.count,
            foundEarlyCount: foundEarly.count,
            foundEarlyShare: foundEarlyShare,
            foundEarlyGrownCount: grown.count,
            foundEarlyGrowthShare: grownShare,
            foundEarlySince: foundEarlySince,
            foundEarlyExampleItem: exampleItem,
            foundEarlyExample: example,
            favoriteWithoutKudosCount: favoriteWithoutKudos,
            seriesStartedCount: startedSeries.count,
            seriesReadToLastCount: readToLast.count,
            seriesNextWaitingCount: nextWaiting.count,
            longestFinishedSeries: longestFinishedSeries,
            authors: authors
        )
    }
}
