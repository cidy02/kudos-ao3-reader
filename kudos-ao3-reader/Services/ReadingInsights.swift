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

        // New redesign figures (T-497)
        insights.totalWordsRead = facts.reduce(0) { $0 + $1.wordsRead }
        insights.previousPeriodWordsRead = previousPeriodFacts.isEmpty
            ? nil
            : previousPeriodFacts.reduce(0) { $0 + $1.wordsRead }
        insights.fandomWordsShares = fandomWordsShares(from: facts)

        var wordCountsByWork: [UUID: Int] = [:]
        for f in facts { wordCountsByWork[f.workID] = f.wordCount }
        insights.lengthMix = lengthMix(words: Array(wordCountsByWork.values))

        insights.dailyWords = dailyWordsBuckets(from: facts, calendar: calendar)
        insights.hourlyDuration = hourlyDurationBuckets(from: facts, calendar: calendar)
        insights.sittingBuckets = sittingBuckets(from: facts)
        insights.readingSeconds = facts.reduce(0) { $0 + $1.durationSeconds }
        insights.finishedWorksCount = Set(facts.filter(\.didFinish).map(\.workID)).count
        insights.readingDaysCount = Set(facts.map { calendar.startOfDay(for: $0.startedAt) }).count
        insights.biggestDay = insights.dailyWords.max(by: { $0.words < $1.words })
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
    /// divide by zero or dilute the rate. Counts the words each sitting read,
    /// not the whole work's (owner Q27, 2026-10-20).
    static func wordsPerHour(of facts: [ReadingSessionFacts]) -> Double {
        let usable = facts.filter { $0.durationSeconds > 0 }
        let totalSeconds = usable.reduce(0) { $0 + $1.durationSeconds }
        guard totalSeconds > 0 else { return 0 }
        let totalWords = usable.reduce(0) { $0 + $1.wordsRead }
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

    /// Where each sitting began in its work, 0…1, in `facts` order (owner Q27,
    /// 2026-10-20): where the work's sitting before it ended, or the start for
    /// its first sitting and for one after a sitting that finished it. A sitting
    /// that went back is where the next one starts from.
    ///
    /// One rule for the words each sitting read (`ReadingLogService.wordsRead`)
    /// and the chapters History draws it reading, so the two cannot disagree.
    static func startingProgress(of facts: [ReadingSessionFacts]) -> [Double] {
        var starts = Array(repeating: 0.0, count: facts.count)
        for indices in Dictionary(grouping: facts.indices, by: { facts[$0].workID }).values {
            var start = 0.0
            for index in indices.sorted(by: { sittingOrder(facts[$0], facts[$1]) }) {
                starts[index] = start
                start = facts[index].didFinish ? 0 : min(1, max(0, facts[index].endingProgress))
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

    /// The spec's `31 min` below an hour, then its compact `3h 20m` (1ah's
    /// facts, 1ak's log line) — the reader keeps its own spelled-out sentence.
    static func durationLabel(_ seconds: Double) -> String {
        let totalMinutes = Int((max(0, seconds) / 60).rounded())
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
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

    /// Daily words breakdown within an optional date interval.
    static func dailyWordsBuckets(
        from facts: [ReadingSessionFacts],
        in interval: DateInterval? = nil,
        calendar: Calendar = .current
    ) -> [DailyWordsBucket] {
        var wordsByDay: [Date: Int] = [:]
        for fact in facts {
            let day = calendar.startOfDay(for: fact.startedAt)
            wordsByDay[day, default: 0] += fact.wordsRead
        }

        guard let interval else {
            let sortedDays = wordsByDay.keys.sorted()
            let maxWords = wordsByDay.values.max() ?? 0
            return sortedDays.map { day in
                let w = wordsByDay[day] ?? 0
                return DailyWordsBucket(
                    date: day,
                    dayNumber: calendar.component(.day, from: day),
                    words: w,
                    isMax: maxWords > 0 && w == maxWords
                )
            }
        }

        var buckets: [DailyWordsBucket] = []
        var current = calendar.startOfDay(for: interval.start)
        let end = interval.end
        let maxWords = wordsByDay.values.max() ?? 0

        while current < end {
            let w = wordsByDay[current] ?? 0
            buckets.append(
                DailyWordsBucket(
                    date: current,
                    dayNumber: calendar.component(.day, from: current),
                    words: w,
                    isMax: maxWords > 0 && w == maxWords
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return buckets
    }

    /// Hourly duration buckets (0...23) for habits time of day.
    static func hourlyDurationBuckets(
        from facts: [ReadingSessionFacts],
        calendar: Calendar = .current
    ) -> [HourlyBucket] {
        var hours: [Double] = Array(repeating: 0, count: 24)
        for fact in facts {
            let hour = calendar.component(.hour, from: fact.startedAt)
            if hour >= 0 && hour < 24 {
                hours[hour] += fact.durationSeconds
            }
        }
        return (0..<24).map { HourlyBucket(hour: $0, seconds: hours[$0]) }
    }

    /// Seconds read during late-night hours (1:00 to 5:00).
    static func lateNightDuration(
        from facts: [ReadingSessionFacts],
        calendar: Calendar = .current
    ) -> Double {
        var total: Double = 0
        for fact in facts {
            let hour = calendar.component(.hour, from: fact.startedAt)
            if hour >= 1 && hour < 5 {
                total += fact.durationSeconds
            }
        }
        return total
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
    static func fandomWordsShares(from facts: [ReadingSessionFacts]) -> [FandomWordsShare] {
        var wordsMap: [String: Int] = [:]
        var worksMap: [String: Set<UUID>] = [:]
        var unattributedWords: Int = 0
        var unattributedWorks: Set<UUID> = []

        for fact in facts {
            if fact.fandom.isEmpty {
                unattributedWords += fact.wordsRead
                unattributedWorks.insert(fact.workID)
            } else {
                wordsMap[fact.fandom, default: 0] += fact.wordsRead
                worksMap[fact.fandom, default: []].insert(fact.workID)
            }
        }

        let totalWords = max(1, facts.reduce(0) { $0 + $1.wordsRead })
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
    static func shipConcentrations(relationships: [RelationshipShare]) -> [ShipConcentration] {
        var byFandom: [String: [RelationshipShare]] = [:]
        for rel in relationships where !rel.fandom.isEmpty {
            byFandom[rel.fandom, default: []].append(rel)
        }

        var result: [ShipConcentration] = []
        for (fandom, ships) in byFandom where ships.reduce(0, { $0 + $1.worksCount }) >= 2 {
            let sorted = ships.sorted(by: { $0.words > $1.words })
            guard let top = sorted.first else { continue }
            let totalWords = max(1, ships.reduce(0) { $0 + $1.words })
            let pct = Int((Double(top.words) / Double(totalWords) * 100).rounded())
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
        return result.sorted(by: { $0.percentage > $1.percentage })
    }

    /// Tag pairs that appear together on >= minimumCount works.
    static func oftenTogetherTags(from works: [SavedWork], minimumCount: Int = 2) -> [TagPair] {
        var pairCounts: [String: (a: String, b: String, count: Int)] = [:]
        for work in works {
            let tags = Array(Set(work.workTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
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
            .filter { $0.count >= minimumCount }
            .sorted { $0.count > $1.count }
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
            if work.isFinished {
                p.finishedCount += 1
            } else if work.isQueuedForLater && !work.hasStartedReading {
                p.savedForLaterCount += 1
            } else if ReadingLogService.isAbandoned(work: work, now: now) {
                p.stoppedCount += 1
            } else if work.keepInProgressOverride {
                p.onHoldCount += 1
            } else if work.hasStartedReading {
                let progress = work.readingProgress ?? 0
                if !work.isComplete && progress >= 0.98 {
                    p.caughtUpCount += 1
                } else {
                    p.readingCount += 1
                }
            } else {
                p.savedForLaterCount += 1
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
    var usualFicSummary: String = ""
    var usualFicTags: [String] = []
    var fandoms: [ReadingInsights.FandomWordsShare] = []
    var relationships: [RelationshipShare] = []
    var shipConcentrations: [ShipConcentration] = []
    var characters: [CharacterShare] = []
    var tags: [TagShare] = []
    var oftenTogether: [TagPair] = []
    var ratings: [CountBreakdown] = []
    var categories: [CountBreakdown] = []
    var warnings: [CountBreakdown] = []
    var yearCounts: [YearCount] = []
    var medianYear: Int? = nil
    var crossoverCount: Int = 0
    var totalWorksCount: Int = 0
    var languages: [CountBreakdown] = []

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
    }

    nonisolated struct CountBreakdown: Equatable, Sendable, Identifiable {
        var id: String { label }
        var label: String
        var count: Int
    }

    nonisolated struct YearCount: Equatable, Sendable, Identifiable {
        var id: Int { year }
        var year: Int
        var count: Int
    }

    static func make(works: [SavedWork], facts: [ReadingSessionFacts]) -> ReadingTasteInsights {
        let readWorkIDs = Set(facts.map(\.workID))
        let targetWorks = works.filter { readWorkIDs.contains($0.id) }
        let effectiveWorks = targetWorks.isEmpty ? works : targetWorks

        let fandomShares = ReadingInsights.fandomWordsShares(from: facts)

        var relWords: [String: (fandom: String, works: Set<UUID>, words: Int)] = [:]
        for fact in facts {
            let work = works.first { $0.id == fact.workID }
            for rel in work?.workRelationships ?? [] {
                let trimmed = rel.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let current = relWords[trimmed] ?? (fandom: fact.fandom, works: [], words: 0)
                var updatedWorks = current.works
                updatedWorks.insert(fact.workID)
                relWords[trimmed] = (
                    fandom: current.fandom.isEmpty ? fact.fandom : current.fandom,
                    works: updatedWorks,
                    words: current.words + fact.wordsRead
                )
            }
        }
        let relationships = relWords.map { key, val in
            RelationshipShare(
                name: key,
                isRomantic: ReadingInsights.isRomanticRelationship(key),
                fandom: val.fandom,
                worksCount: val.works.count,
                words: val.words
            )
        }.sorted { $0.words > $1.words }

        let shipConcentrations = ReadingInsights.shipConcentrations(relationships: relationships)

        var charCounts: [String: (fandom: String, count: Int)] = [:]
        for work in effectiveWorks {
            let fandom = work.workFandoms.first ?? ""
            for char in work.workCharacters {
                let trimmed = char.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                charCounts[trimmed, default: (fandom: fandom, count: 0)].count += 1
                if charCounts[trimmed]?.fandom.isEmpty == true {
                    charCounts[trimmed]?.fandom = fandom
                }
            }
        }
        let characters = charCounts.map { key, val in
            CharacterShare(name: key, count: val.count, fandom: val.fandom)
        }.sorted { $0.count > $1.count }

        var tagWords: [String: (words: Int, count: Int)] = [:]
        for fact in facts {
            let work = works.first { $0.id == fact.workID }
            for tag in work?.workTags ?? [] {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                tagWords[trimmed, default: (words: 0, count: 0)].words += fact.wordsRead
                tagWords[trimmed]?.count += 1
            }
        }
        let tags = tagWords.map { key, val in
            TagShare(name: key, words: val.words, count: val.count)
        }.sorted { $0.words > $1.words }

        let oftenTogether = ReadingInsights.oftenTogetherTags(from: effectiveWorks)

        var ratingCounts: [String: Int] = [:]
        for work in effectiveWorks {
            let r = work.rating.trimmingCharacters(in: .whitespacesAndNewlines)
            if !r.isEmpty { ratingCounts[r, default: 0] += 1 }
        }
        let ratingsOrder = ["General Audiences", "Teen And Up Audiences", "Mature", "Explicit", "Not Rated"]
        let ratings = ratingsOrder.compactMap { label -> CountBreakdown? in
            let count = ratingCounts[label] ?? ratingCounts.first(where: { $0.key.localizedCaseInsensitiveContains(label.prefix(4)) })?.value ?? 0
            guard count > 0 else { return nil }
            let shortLabel: String
            switch label {
            case "General Audiences": shortLabel = "General"
            case "Teen And Up Audiences": shortLabel = "Teen"
            default: shortLabel = label
            }
            return CountBreakdown(label: shortLabel, count: count)
        }

        var catCounts: [String: Int] = [:]
        for work in effectiveWorks {
            for cat in work.workCategories {
                let trimmed = cat.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { catCounts[trimmed, default: 0] += 1 }
            }
        }
        let categories = catCounts.map { CountBreakdown(label: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        var warnCounts: [String: Int] = [:]
        for work in effectiveWorks {
            for w in work.workWarnings {
                let trimmed = w.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { warnCounts[trimmed, default: 0] += 1 }
            }
        }
        let warnings = warnCounts.map { CountBreakdown(label: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        var yearMap: [Int: Int] = [:]
        let calendar = Calendar.current
        for work in effectiveWorks {
            if let date = WorkStat.date(from: work.datePublished) ?? work.downloadedAt {
                let y = calendar.component(.year, from: date)
                if y > 1990 && y <= calendar.component(.year, from: Date()) {
                    yearMap[y, default: 0] += 1
                }
            }
        }
        let yearCounts = yearMap.keys.sorted().map { YearCount(year: $0, count: yearMap[$0] ?? 0) }
        let allYears = yearMap.flatMap { Array(repeating: $0.key, count: $0.value) }.sorted()
        let medianYear = allYears.isEmpty ? nil : allYears[allYears.count / 2]

        let crossoverCount = effectiveWorks.filter { $0.workFandoms.count > 1 }.count
        var langCounts: [String: Int] = [:]
        for work in effectiveWorks {
            let l = work.language.trimmingCharacters(in: .whitespacesAndNewlines)
            if !l.isEmpty { langCounts[l, default: 0] += 1 }
        }
        let languages = langCounts.map { CountBreakdown(label: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        let statusStr = (effectiveWorks.filter(\.isFinished).count >= max(1, effectiveWorks.count / 2)) ? "complete" : "in-progress"
        let ratingStr = ratings.first?.label ?? "Teen"
        let catStr = categories.first?.label ?? "F/M"
        let topTagStr = tags.first?.name.lowercased() ?? "slow burn"
        let topFandomStr = fandomShares.first(where: { !$0.isRemainder })?.name ?? "AO3"
        let topRel = relationships.first?.name ?? ""
        let extraTags = tags.dropFirst().prefix(2).map { $0.name.lowercased() }.joined(separator: " and ")

        let summary: String
        if !topRel.isEmpty && !extraTags.isEmpty {
            summary = "A \(statusStr), \(ratingStr)-rated \(catStr) \(topTagStr) in \(topFandomStr), 50–150k words long, with \(topRel), \(extraTags)."
        } else {
            summary = "A \(statusStr), \(ratingStr)-rated \(catStr) \(topTagStr) in \(topFandomStr)."
        }

        var usualChips: [String] = [statusStr.capitalized, ratingStr, catStr, topTagStr.capitalized]
        if !topRel.isEmpty { usualChips.append(topRel) }
        for t in tags.dropFirst().prefix(2) { usualChips.append(t.name) }

        return ReadingTasteInsights(
            usualFicSummary: summary,
            usualFicTags: usualChips,
            fandoms: fandomShares,
            relationships: relationships,
            shipConcentrations: shipConcentrations,
            characters: characters,
            tags: tags,
            oftenTogether: oftenTogether,
            ratings: ratings,
            categories: categories,
            warnings: warnings,
            yearCounts: yearCounts,
            medianYear: medianYear,
            crossoverCount: crossoverCount,
            totalWorksCount: effectiveWorks.count,
            languages: languages
        )
    }
}

// MARK: - Habits Insights

nonisolated struct ReadingHabitsInsights: Equatable, Sendable {
    var hourlyDuration: [ReadingInsights.HourlyBucket] = []
    var lateNightDuration: Double = 0
    var lateNightSharePercent: Int = 0
    var calendarDays: [ReadingInsights.DailyWordsBucket] = []
    var longestStreak: Int = 0
    var sittingBuckets: [ReadingInsights.SittingBucket] = []
    var typicalSittingSeconds: Double = 0
    /// Medians come from the stored dates and log; nil when the data cannot say.
    var savedToOpenedMedianDays: Int?
    var openedToFinishedMedianDays: Int?
    var rereads: [RereadWork] = []
    var fandomTimeline: [FandomTimelineLane] = []
    var stoppedCount: Int = 0
    var stoppedMedianProgress: Double?
    var commonStopTags: [(name: String, count: Int)] = []

    static func == (lhs: ReadingHabitsInsights, rhs: ReadingHabitsInsights) -> Bool {
        lhs.hourlyDuration == rhs.hourlyDuration
            && lhs.lateNightDuration == rhs.lateNightDuration
            && lhs.lateNightSharePercent == rhs.lateNightSharePercent
            && lhs.calendarDays == rhs.calendarDays
            && lhs.longestStreak == rhs.longestStreak
            && lhs.sittingBuckets == rhs.sittingBuckets
            && lhs.typicalSittingSeconds == rhs.typicalSittingSeconds
            && lhs.savedToOpenedMedianDays == rhs.savedToOpenedMedianDays
            && lhs.openedToFinishedMedianDays == rhs.openedToFinishedMedianDays
            && lhs.rereads == rhs.rereads
            && lhs.fandomTimeline == rhs.fandomTimeline
            && lhs.stoppedCount == rhs.stoppedCount
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

    nonisolated struct FandomTimelineLane: Equatable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        var monthlyActivity: [Int]
    }

    /// Median of the values; nil when there are none.
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func make(
        works: [SavedWork],
        facts: [ReadingSessionFacts],
        allFacts: [ReadingSessionFacts],
        calendar: Calendar = .current
    ) -> ReadingHabitsInsights {
        let hourly = ReadingInsights.hourlyDurationBuckets(from: facts, calendar: calendar)
        let lateNightSec = ReadingInsights.lateNightDuration(from: facts, calendar: calendar)
        let totalSec = max(1, facts.reduce(0) { $0 + $1.durationSeconds })
        let lateNightPct = Int((lateNightSec / totalSec * 100).rounded())

        let calDays = ReadingInsights.dailyWordsBuckets(from: facts, calendar: calendar)
        let streak = ReadingInsights.longestStreak(of: facts, calendar: calendar)
        let sittings = ReadingInsights.sittingBuckets(from: facts)
        let typicalSec = ReadingInsights.medianSeconds(of: facts)

        var finishCountsByWork: [UUID: (title: String, fandom: String, words: Int, count: Int)] = [:]
        for fact in allFacts where fact.didFinish {
            guard let work = works.first(where: { $0.id == fact.workID }) else { continue }
            let cur = finishCountsByWork[fact.workID] ?? (
                title: work.title,
                fandom: work.workFandoms.first ?? "",
                words: 0,
                count: 0
            )
            finishCountsByWork[fact.workID] = (
                title: cur.title,
                fandom: cur.fandom,
                words: cur.words + fact.wordsRead,
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
        }.sorted { $0.finishCount > $1.finishCount }

        let topFandomNames = ReadingInsights.fandomShares(from: facts).filter { !$0.isRemainder }.map(\.name)
        let timelineLanes = topFandomNames.map { name -> FandomTimelineLane in
            var months = Array(repeating: 0, count: 12)
            for fact in allFacts where fact.fandom == name {
                let m = calendar.component(.month, from: fact.startedAt) - 1
                if m >= 0 && m < 12 {
                    months[m] += fact.wordsRead
                }
            }
            let maxM = months.max() ?? 0
            let tiers = months.map { w -> Int in
                guard maxM > 0 && w > 0 else { return 0 }
                let ratio = Double(w) / Double(maxM)
                if ratio < 0.25 { return 1 }
                if ratio < 0.6 { return 2 }
                return 3
            }
            return FandomTimelineLane(name: name, monthlyActivity: tiers)
        }

        let stoppedWorks = works.filter { ReadingLogService.isAbandoned(work: $0) }
        let stoppedCount = stoppedWorks.count

        let stoppedMedianProgress = median(stoppedWorks.compactMap(\.readingProgress))

        var stopTags: [String: Int] = [:]
        for work in stoppedWorks {
            for tag in work.workWarnings + work.workTags {
                let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { stopTags[t, default: 0] += 1 }
            }
        }
        let commonStopTags = stopTags.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { $0 }

        // First sitting per work from the whole log, then the gaps the dates can prove.
        let firstSitting = Dictionary(grouping: allFacts, by: \.workID).mapValues { $0.map(\.startedAt).min() }
        let secondsPerDay = 86_400.0
        let savedToOpened = works.compactMap { work -> Double? in
            guard facts.contains(where: { $0.workID == work.id }),
                  let first = firstSitting[work.id] ?? nil else { return nil }
            return max(0, first.timeIntervalSince(work.dateAdded)) / secondsPerDay
        }
        let openedToFinished = works.compactMap { work -> Double? in
            guard let first = firstSitting[work.id] ?? nil,
                  let done = facts.filter({ $0.workID == work.id && $0.didFinish }).map(\.startedAt).min()
            else { return nil }
            return max(0, done.timeIntervalSince(first)) / secondsPerDay
        }

        return ReadingHabitsInsights(
            hourlyDuration: hourly,
            lateNightDuration: lateNightSec,
            lateNightSharePercent: lateNightPct,
            calendarDays: calDays,
            longestStreak: streak,
            sittingBuckets: sittings,
            typicalSittingSeconds: typicalSec,
            savedToOpenedMedianDays: median(savedToOpened).map { Int($0.rounded()) },
            openedToFinishedMedianDays: median(openedToFinished).map { Int($0.rounded()) },
            rereads: rereads,
            fandomTimeline: timelineLanes,
            stoppedCount: stoppedCount,
            stoppedMedianProgress: stoppedMedianProgress,
            commonStopTags: Array(commonStopTags)
        )
    }
}

// MARK: - Library Insights

nonisolated struct ReadingLibraryInsights: Equatable, Sendable {
    var unreadWords: Int = 0
    var unreadWorksCount: Int = 0
    var monthsToClear: Int? = nil
    var addedWordsInPeriod: Int = 0
    var readWordsInPeriod: Int = 0
    var statuses: ReadingStatusPartition = ReadingStatusPartition()
    var stillReadingCandidate: StillReadingCandidate? = nil
    var wipFreshness: WIPFreshness = WIPFreshness()
    var noLongerOnAO3Count: Int = 0
    var noLongerOnAO3Words: Int = 0
    var noLongerOnAO3LastCopies: Int = 0
    /// Share of finished works you left kudos on / favourited; nil with nothing finished.
    var kudosLeftPercent: Int?
    var bookmarkedPercent: Int?

    static func == (lhs: ReadingLibraryInsights, rhs: ReadingLibraryInsights) -> Bool {
        lhs.unreadWords == rhs.unreadWords
            && lhs.unreadWorksCount == rhs.unreadWorksCount
            && lhs.monthsToClear == rhs.monthsToClear
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
    }

    nonisolated struct StillReadingCandidate: Equatable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var fandom: String
        var chapterProgress: String
        /// Nil when the work has no stored position; nothing is guessed.
        var progressPercent: Int?
        var daysUntouched: Int
        var work: SavedWork
    }

    static func make(
        works: [SavedWork],
        facts: [ReadingSessionFacts],
        periodInterval: DateInterval,
        periodMonths: Double = 1,
        calendar: Calendar = .current
    ) -> ReadingLibraryInsights {
        let unread = works.filter { !$0.hasStartedReading && !$0.isFinished }
        let unreadWords = unread.reduce(0) { $0 + max(0, $1.wordCount) }
        let readWordsInPeriod = facts.reduce(0) { $0 + $1.wordsRead }

        let addedInPeriod = works.filter { periodInterval.contains($0.dateAdded) }
        let addedWordsInPeriod = addedInPeriod.reduce(0) { $0 + max(0, $1.wordCount) }

        // Nil without reading in the period; the pace is per month, so a Year
        // period's words are divided by its 12 months first.
        let monthsToClear: Int? = unreadWords > 0 && readWordsInPeriod > 0
            ? max(1, Int((Double(unreadWords) / (Double(readWordsInPeriod) / max(1, periodMonths))).rounded()))
            : nil

        let statuses = ReadingInsights.partitionStatuses(works: works)
        // isAbandoned needs lastReadDate, so the untouched time is always real.
        let candidateWork = works.first { ReadingLogService.isAbandoned(work: $0) && $0.lastReadDate != nil }
        let candidate: StillReadingCandidate? = candidateWork.map { w in
            let progress = w.readingProgress.map { Int(($0 * 100).rounded()) }
            let chapters = "Chapter \(w.lastSpineIndex + 1) of \(w.postedChapterCount > 0 ? w.postedChapterCount : 1)"
            let days = w.lastReadDate.flatMap { calendar.dateComponents([.day], from: $0, to: Date()).day } ?? 0
            return StillReadingCandidate(
                id: w.id,
                title: w.title,
                fandom: w.workFandoms.first ?? "",
                chapterProgress: progress.map { "\(chapters) · \($0)%" } ?? chapters,
                progressPercent: progress,
                daysUntouched: max(1, days),
                work: w
            )
        }

        let wip = ReadingInsights.wipFreshness(works: works, calendar: calendar)

        let goneWorks = works.filter { $0.preservationState == .preservedLastCopy || $0.preservationState == .goneWithNoCopy }
        let goneWords = goneWorks.reduce(0) { $0 + max(0, $1.wordCount) }
        let lastCopies = works.filter { $0.preservationState == .preservedLastCopy }.count

        let finished = works.filter(\.isFinished)
        let kudosPct: Int? = finished.isEmpty ? nil
            : Int(Double(finished.filter(\.hasGivenKudos).count) / Double(finished.count) * 100)
        let bookmarkPct: Int? = finished.isEmpty ? nil
            : Int(Double(finished.filter(\.isFavorite).count) / Double(finished.count) * 100)

        return ReadingLibraryInsights(
            unreadWords: unreadWords,
            unreadWorksCount: unread.count,
            monthsToClear: monthsToClear,
            addedWordsInPeriod: addedWordsInPeriod,
            readWordsInPeriod: readWordsInPeriod,
            statuses: statuses,
            stillReadingCandidate: candidate,
            wipFreshness: wip,
            noLongerOnAO3Count: goneWorks.count,
            noLongerOnAO3Words: goneWords,
            noLongerOnAO3LastCopies: lastCopies,
            kudosLeftPercent: kudosPct,
            bookmarkedPercent: bookmarkPct
        )
    }
}
