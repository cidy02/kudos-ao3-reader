import Foundation

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
    var durationSeconds: Double
    var wordCount: Int
    var didFinish: Bool
    var fandom: String = ""
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

    /// How many named fandoms 1bi lists before folding the rest together.
    static let namedFandomLimit = 3
    /// What the folded row is called. Named once so the screen can recognise it
    /// without matching a literal.
    static let remainderName = "Everything else"

    /// Builds every figure in one pass.
    static func make(
        facts: [ReadingSessionFacts],
        previousPeriodFacts: [ReadingSessionFacts] = [],
        calendar: Calendar = .current
    ) -> ReadingInsights {
        var insights = ReadingInsights()
        insights.totalSeconds = facts.reduce(0) { $0 + $1.durationSeconds }
        insights.previousPeriodSeconds = previousPeriodFacts.isEmpty
            ? nil
            : previousPeriodFacts.reduce(0) { $0 + $1.durationSeconds }
        insights.weeklySeconds = weeklyBuckets(from: facts, calendar: calendar)
        insights.byFandom = fandomShares(from: facts)
        insights.medianSessionSeconds = medianSeconds(of: facts)
        insights.wordsPerHour = wordsPerHour(of: facts)
        insights.finishRate = finishRate(of: facts)
        insights.longestStreakDays = longestStreak(of: facts, calendar: calendar)
        return insights
    }

    // MARK: The rules

    static func weeklyBuckets(
        from facts: [ReadingSessionFacts],
        calendar: Calendar
    ) -> [WeeklyBucket] {
        var buckets: [Date: Double] = [:]
        for fact in facts {
            guard let weekStart = calendar
                .dateInterval(of: .weekOfYear, for: fact.startedAt)?.start
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
    static func fandomShares(from facts: [ReadingSessionFacts]) -> [FandomShare] {
        var seconds: [String: Double] = [:]
        var unattributed: Double = 0
        for fact in facts {
            if fact.fandom.isEmpty {
                unattributed += fact.durationSeconds
            } else {
                seconds[fact.fandom, default: 0] += fact.durationSeconds
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

    /// Median of the session durations. An even count takes the mean of the
    /// middle two — the ordinary definition, and the one a reader checking the
    /// figure by hand would use.
    static func medianSeconds(of facts: [ReadingSessionFacts]) -> Double {
        let durations = facts.map(\.durationSeconds).filter { $0 > 0 }.sorted()
        guard !durations.isEmpty else { return 0 }
        let middle = durations.count / 2
        if durations.count.isMultiple(of: 2) {
            return (durations[middle - 1] + durations[middle]) / 2
        }
        return durations[middle]
    }

    /// Words per hour over the whole period, weighted by time rather than
    /// averaged across sessions. Zero-length rows are dropped so one cannot
    /// divide by zero or dilute the rate.
    static func wordsPerHour(of facts: [ReadingSessionFacts]) -> Double {
        let usable = facts.filter { $0.durationSeconds > 0 }
        let totalSeconds = usable.reduce(0) { $0 + $1.durationSeconds }
        guard totalSeconds > 0 else { return 0 }
        let totalWords = usable.reduce(0) { $0 + $1.wordCount }
        return Double(totalWords) / (totalSeconds / 3600)
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

    /// Longest run of consecutive calendar days carrying at least one session.
    ///
    /// Days, not sessions: two sessions on one evening are one day of reading.
    /// `calendar` is a parameter because "which day is this" is a timezone
    /// question, and a streak computed in UTC would break for anyone who reads
    /// late at night.
    static func longestStreak(of facts: [ReadingSessionFacts], calendar: Calendar) -> Int {
        let days = Set(facts.map { calendar.startOfDay(for: $0.startedAt) }).sorted()
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

    /// The spec's `31 min`. Minutes below an hour, then `1 h 12 min`.
    static func durationLabel(_ seconds: Double) -> String {
        let totalMinutes = Int((max(0, seconds) / 60).rounded())
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }
}
