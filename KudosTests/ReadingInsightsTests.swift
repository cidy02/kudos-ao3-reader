import Foundation
import Testing
@testable import Kudos

/// Artboard 1bi's figures. Every rule here is arguable, so every test states
/// which answer was chosen and would fail if the other one were substituted —
/// a test that only checked "a number came out" would pass on either.
///
/// No `ModelContainer`: the rules take `ReadingSessionFacts`, which is the point
/// of that type.
struct ReadingInsightsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func day(_ dayOfMonth: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = dayOfMonth
        components.hour = hour
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func fact(
        work: UUID = UUID(),
        on dayOfMonth: Int,
        hour: Int = 12,
        minutes: Double,
        words: Int = 0,
        didFinish: Bool = false,
        fandom: String = ""
    ) -> ReadingSessionFacts {
        ReadingSessionFacts(
            workID: work,
            startedAt: day(dayOfMonth, hour: hour),
            durationSeconds: minutes * 60,
            wordCount: words,
            didFinish: didFinish,
            fandom: fandom,
            wordsRead: words
        )
    }

    // MARK: Median

    @Test func theTypicalSessionIsTheMedianSoOneBingeCannotMoveIt() {
        let facts = [
            fact(on: 1, minutes: 20),
            fact(on: 2, minutes: 30),
            fact(on: 3, minutes: 40),
            fact(on: 4, minutes: 240)
        ]
        // Mean would be 82.5 minutes — a figure none of these four sessions
        // resembles. The median of the middle two is 35.
        #expect(ReadingInsights.medianSeconds(of: facts) == 35 * 60)
    }

    @Test func medianOfNothingIsZeroRatherThanACrash() {
        #expect(ReadingInsights.medianSeconds(of: []) == 0)
    }

    // MARK: Finish rate

    @Test func finishRateCountsWorksNotSessionsSoARereadCannotInflateIt() {
        let reread = UUID()
        let abandoned = UUID()
        let facts = [
            fact(work: reread, on: 1, minutes: 30, didFinish: true),
            fact(work: reread, on: 2, minutes: 30, didFinish: true),
            fact(work: reread, on: 3, minutes: 30, didFinish: true),
            fact(work: abandoned, on: 4, minutes: 30)
        ]
        // Per session this would be 75%. Two works, one finished: 50%.
        #expect(ReadingInsights.finishRate(of: facts) == 0.5)
    }

    @Test func noStartedWorksIsNoDataRatherThanZeroPercent() {
        #expect(ReadingInsights.finishRate(of: []) == nil)
    }

    // MARK: Streak

    @Test func aStreakCountsDaysSoTwoSessionsInOneEveningAreOneDay() {
        let facts = [
            fact(on: 1, hour: 19, minutes: 30),
            fact(on: 1, hour: 22, minutes: 30),
            fact(on: 2, minutes: 30),
            fact(on: 3, minutes: 30),
            // Gap.
            fact(on: 9, minutes: 30)
        ]
        #expect(ReadingInsights.longestStreak(of: facts, calendar: calendar) == 3)
    }

    @Test func aStreakOfOneDayIsOneNotZero() {
        #expect(ReadingInsights.longestStreak(of: [fact(on: 4, minutes: 30)],
                                              calendar: calendar) == 1)
    }

    // MARK: Fandom shares

    @Test func fandomSharesPartitionTheHoursRatherThanOverCounting() {
        let facts = [
            fact(on: 1, minutes: 60, fandom: "Naruto"),
            fact(on: 2, minutes: 30, fandom: "Cyberpunk 2077"),
            fact(on: 3, minutes: 20, fandom: "Blade Runner"),
            fact(on: 4, minutes: 10, fandom: "Dracula"),
            // A session whose work is gone: still real hours, no fandom.
            fact(on: 5, minutes: 5)
        ]
        let shares = ReadingInsights.fandomShares(from: facts)

        #expect(shares.map(\.name) == [
            "Naruto", "Cyberpunk 2077", "Blade Runner", "Everything else"
        ])
        // The fourth fandom and the unattributable session fold together, and
        // the shares still sum to the total — the whole reason attribution is a
        // partition rather than one row per fandom of a crossover.
        #expect(shares.last?.seconds == Double(15 * 60))
        #expect(shares.last?.isRemainder == true)
        #expect(shares.reduce(0) { $0 + $1.seconds } == 125 * 60)
    }

    @Test func noRemainderRowAppearsWhenNothingIsLeftOver() {
        let shares = ReadingInsights.fandomShares(from: [
            fact(on: 1, minutes: 60, fandom: "Naruto"),
            fact(on: 2, minutes: 30, fandom: "Dracula")
        ])
        #expect(shares.map(\.name) == ["Naruto", "Dracula"])
        #expect(shares.contains { $0.isRemainder } == false)
    }

    // MARK: Words per hour

    @Test func wordsPerHourIsWeightedByTimeNotAveragedAcrossSessions() {
        let facts = [
            fact(on: 1, minutes: 60, words: 10_000),
            fact(on: 2, minutes: 180, words: 60_000),
            // Ignored: a zero-length row would otherwise divide by zero.
            fact(on: 3, minutes: 0, words: 900_000)
        ]
        // Averaging the two rates would give 15,000. Weighted by time: 70,000
        // words over 4 hours.
        #expect(ReadingInsights.wordsPerHour(of: facts) == 17_500)
    }

    // MARK: The delta

    @Test func aFirstPeriodHasNoDeltaRatherThanADeltaAgainstZero() {
        let insights = ReadingInsights.make(
            facts: [fact(on: 1, minutes: 60)], calendar: calendar
        )
        #expect(insights.previousPeriodSeconds == nil)
        #expect(insights.totalSeconds == 3_600)
    }

    @Test func theDeltaComesFromThePriorPeriodsOwnRows() {
        let insights = ReadingInsights.make(
            facts: [fact(on: 1, minutes: 90)],
            previousPeriodFacts: [fact(on: 1, minutes: 30)],
            calendar: calendar
        )
        #expect(insights.previousPeriodSeconds == 1_800)
        #expect(ReadingInsights.signedHoursLabel(
            insights.totalSeconds - (insights.previousPeriodSeconds ?? 0)
        ) == "+1.0")
    }

    // MARK: Labels

    @Test func labelsMatchTheSpecsOwnFormats() {
        #expect(ReadingInsights.hoursLabel(18.4 * 3600) == "18.4")
        #expect(ReadingInsights.signedHoursLabel(-0.6 * 3600) == "−0.6")
        #expect(ReadingInsights.durationLabel(31 * 60) == "31 min")
        #expect(ReadingInsights.durationLabel(72 * 60) == "1h 12m")
        #expect(ReadingInsights.durationLabel(120 * 60) == "2h")
    }

    // MARK: Redesign Figures (T-497)

    @Test func novelsWorthCalculationRoundsToHalfAndHidesUnder35k() {
        // Spec rule: Words read ÷ 70,000 to nearest half; hidden under 35,000 words.
        #expect(ReadingInsights.novelsWorth(words: 30_000) == nil)
        #expect(ReadingInsights.novelsWorth(words: 35_000) == 0.5)
        #expect(ReadingInsights.novelsWorth(words: 70_000) == 1.0)
        #expect(ReadingInsights.novelsWorth(words: 100_000) == 1.5)
        #expect(ReadingInsights.novelsWorth(words: 212_600) == 3.0)

        #expect(
            ReadingInsights.novelsWorthLabel(words: 212_600) ==
                "About 3 novels’ worth, at 70,000 words a novel"
        )
        #expect(ReadingInsights.novelsWorthLabel(words: 25_000) == nil)
    }

    @Test func lengthMixCategorizesWordCountsCorrectly() {
        let words = [2_500, 15_000, 45_000, 60_000, 250_000]
        let mix = ReadingInsights.lengthMix(words: words)

        #expect(mix.under5k == 1)
        #expect(mix.from5kTo50k == 2)
        #expect(mix.from50kTo150k == 1)
        #expect(mix.over150k == 1)
        #expect(mix.totalWorks == 5)
    }

    @Test func romanticVsPlatonicRelationshipDetection() {
        #expect(ReadingInsights.isRomanticRelationship("Anne Elliot/Frederick Wentworth") == true)
        #expect(ReadingInsights.relationshipGlyph(for: "Anne Elliot/Frederick Wentworth") == "/")

        #expect(ReadingInsights.isRomanticRelationship("Sherlock Holmes & John Watson") == false)
        #expect(ReadingInsights.relationshipGlyph(for: "Sherlock Holmes & John Watson") == "&")
    }

    @Test func shipConcentrationCalculatesPercentageOnTopRelationship() {
        let ships = [
            RelationshipShare(
                name: "A/B",
                isRomantic: true,
                fandom: "Persuasion",
                worksCount: 4,
                words: 80_000
            ),
            RelationshipShare(
                name: "A&C",
                isRomantic: false,
                fandom: "Persuasion",
                worksCount: 1,
                words: 20_000
            )
        ]
        let conc = ReadingInsights.shipConcentrations(relationships: ships)
        #expect(conc.count == 1)
        #expect(conc.first?.percentage == 80)
        #expect(conc.first?.fandom == "Persuasion")
    }

    @Test func sittingBucketsDistributeCorrectlyByDuration() {
        let facts = [
            fact(on: 1, minutes: 5),    // < 10 m
            fact(on: 2, minutes: 20),   // 10–30 m
            fact(on: 3, minutes: 45),   // 30–60 m
            fact(on: 4, minutes: 90),   // 1–2 h
            fact(on: 5, minutes: 150)   // 2 h +
        ]
        let buckets = ReadingInsights.sittingBuckets(from: facts)
        #expect(buckets.map(\.count) == [1, 1, 1, 1, 1])
    }

    @Test func lateNightDurationOnlyCountsSessionsBetween1And5AM() {
        let facts = [
            fact(on: 1, hour: 3, minutes: 30),  // late night
            fact(on: 2, hour: 14, minutes: 60)  // afternoon
        ]
        #expect(ReadingInsights.lateNightDuration(from: facts, calendar: calendar) == 30 * 60)
    }

    // MARK: Library insights are honest

    private func libraryInsights(
        words: Int, works: [SavedWork], months: Double
    ) -> ReadingLibraryInsights {
        let interval = DateInterval(start: day(1), end: day(28))
        let facts = words == 0 ? [] : [
            ReadingSessionFacts(
                workID: UUID(), startedAt: day(2), durationSeconds: 3600,
                wordCount: words, didFinish: false, wordsRead: words
            )
        ]
        return ReadingLibraryInsights.make(
            works: works, facts: facts, periodInterval: interval,
            periodMonths: months, calendar: calendar
        )
    }

    @Test func monthsToClearIsNilWhenThePeriodHasNoReading() {
        let unread = SavedWork(title: "Unread", author: "A")
        unread.wordCount = 100_000
        #expect(libraryInsights(words: 0, works: [unread], months: 1).monthsToClear == nil)
    }

    @Test func monthsToClearUsesAPerMonthPaceInYearMode() {
        let unread = SavedWork(title: "Unread", author: "A")
        unread.wordCount = 120_000
        // 60k words read in a month is 60k/month; across a year it is 5k/month.
        #expect(libraryInsights(words: 60_000, works: [unread], months: 1).monthsToClear == 2)
        #expect(libraryInsights(words: 60_000, works: [unread], months: 12).monthsToClear == 24)
    }

    @Test func libraryInsightsInventNothingWithNoFinishedWorks() {
        let insights = libraryInsights(words: 0, works: [SavedWork(title: "T", author: "A")], months: 1)
        #expect(insights.kudosLeftPercent == nil)
        #expect(insights.bookmarkedPercent == nil)
    }

    @Test func rereadsExcludesWorksNotPresentInVisibleWorks() {
        let visibleWork = SavedWork(title: "Allowed Fic", author: "Author")
        let facts = [
            ReadingSessionFacts(
                workID: visibleWork.id,
                startedAt: day(1),
                durationSeconds: 1800,
                wordCount: 10000,
                didFinish: true,
                fandom: "Persuasion",
                wordsRead: 10000,
                title: "Allowed Fic"
            ),
            ReadingSessionFacts(
                workID: visibleWork.id,
                startedAt: day(2),
                durationSeconds: 1800,
                wordCount: 10000,
                didFinish: true,
                fandom: "Persuasion",
                wordsRead: 10000,
                title: "Allowed Fic"
            ),
            ReadingSessionFacts(
                workID: UUID(), // Concealed or unknown work
                startedAt: day(3),
                durationSeconds: 1800,
                wordCount: 20000,
                didFinish: true,
                fandom: "Secret Fandom",
                wordsRead: 20000,
                title: "Secret Fic"
            ),
            ReadingSessionFacts(
                workID: UUID(), // Same concealed or unknown work finished again
                startedAt: day(4),
                durationSeconds: 1800,
                wordCount: 20000,
                didFinish: true,
                fandom: "Secret Fandom",
                wordsRead: 20000,
                title: "Secret Fic"
            )
        ]

        let habits = ReadingHabitsInsights.make(
            works: [visibleWork],
            facts: facts,
            allFacts: facts,
            calendar: calendar
        )

        // Only the visible work is listed in rereads; concealed/unlisted work is excluded
        #expect(habits.rereads.count == 1)
        #expect(habits.rereads.first?.title == "Allowed Fic")
        #expect(habits.rereads.first?.finishCount == 2)
    }

    @Test func habitsMediansComeFromTheDataNotConstants() {
        // Nothing read, nothing stopped: every median is nil. A hard-coded 6, 3 or 0.31 fails here.
        let empty = ReadingHabitsInsights.make(works: [], facts: [], allFacts: [], calendar: calendar)
        #expect(empty.savedToOpenedMedianDays == nil)
        #expect(empty.openedToFinishedMedianDays == nil)
        #expect(empty.stoppedMedianProgress == nil)

        // Saved 10 days before the first sitting, finished 4 days after it.
        let work = SavedWork(title: "W", author: "A")
        work.dateAdded = day(1)
        let facts = [
            ReadingSessionFacts(workID: work.id, startedAt: day(11), durationSeconds: 600, wordCount: 1000, didFinish: false),
            ReadingSessionFacts(workID: work.id, startedAt: day(15), durationSeconds: 600, wordCount: 1000, didFinish: true)
        ]
        let habits = ReadingHabitsInsights.make(works: [work], facts: facts, allFacts: facts, calendar: calendar)
        #expect(habits.savedToOpenedMedianDays == 10)
        #expect(habits.openedToFinishedMedianDays == 4)
    }

    // MARK: T-517 — the day runs 4:00 to 4:00, in the zone the sitting was read in

    private func instant(
        month: Int = 8, _ dayOfMonth: Int, _ hour: Int, _ minute: Int = 0, offsetHours: Int = 0
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: offsetHours * 3600) ?? .gmt
        let parts = DateComponents(year: 2026, month: month, day: dayOfMonth, hour: hour, minute: minute)
        return cal.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    private func sitting(
        at startedAt: Date, minutes: Double = 30, words: Int = 0, tzHours: Int? = nil
    ) -> ReadingSessionFacts {
        var fact = ReadingSessionFacts(
            workID: UUID(), startedAt: startedAt, durationSeconds: minutes * 60,
            wordCount: words, didFinish: false, wordsRead: words
        )
        fact.tzOffsetSeconds = tzHours.map { $0 * 3600 }
        return fact
    }

    @Test func aSittingAtHalfPastTwoCountsForThePreviousDay() {
        let night = sitting(at: instant(10, 2, 30))
        #expect(ReadingInsights.readingDay(for: night, calendar: calendar) == day(9, hour: 0))
        // 4:00 sharp is the new day; 3:59 is still the old one.
        #expect(ReadingInsights.readingDay(for: sitting(at: instant(10, 4, 0)), calendar: calendar) == day(10, hour: 0))
        #expect(ReadingInsights.readingDay(for: sitting(at: instant(10, 3, 59)), calendar: calendar) == day(9, hour: 0))
        // Read at 23:30 and 02:30 the same night: one day, one streak.
        let facts = [sitting(at: instant(9, 23, 30)), night]
        #expect(ReadingInsights.make(facts: facts, calendar: calendar).readingDaysCount == 1)
        #expect(ReadingInsights.longestStreak(of: facts, calendar: calendar) == 1)
    }

    @Test func aSittingReadAtPlusNineAndViewedAtMinusFiveLandsOnTheDayItWasRead() {
        var viewer = Calendar(identifier: .gregorian)
        viewer.timeZone = TimeZone(secondsFromGMT: -5 * 3600) ?? .gmt
        // 12:00 on 10 Aug in Tokyo is 22:00 on 9 Aug in the viewer's zone.
        let read = sitting(at: instant(10, 12, offsetHours: 9), tzHours: 9)
        var expected = DateComponents(year: 2026, month: 8, day: 10)
        expected.hour = 0
        #expect(ReadingInsights.readingDay(for: read, calendar: viewer) == viewer.date(from: expected))
        // Without the recorded zone it falls back to the viewer's, as before.
        var unzoned = read
        unzoned.tzOffsetSeconds = nil
        expected.day = 9
        #expect(ReadingInsights.readingDay(for: unzoned, calendar: viewer) == viewer.date(from: expected))
        // Time of Day uses the hour on the clock where it was read.
        let hours = ReadingInsights.hourlyDurationBuckets(from: [read], calendar: viewer)
        #expect(hours[12].seconds == 30 * 60)
    }

    @Test func aStreakAcrossATimeZoneChangeIsNotBroken() {
        // 20:00 on 10 Aug in Tokyo, then 20:00 on 11 Aug in UTC-8 (04:00 UTC on the 12th).
        // Viewed in one fixed zone these are two days apart; read where they were, they are
        // consecutive evenings.
        let facts = [
            sitting(at: instant(10, 20, offsetHours: 9), tzHours: 9),
            sitting(at: instant(11, 20, offsetHours: -8), tzHours: -8)
        ]
        #expect(ReadingInsights.longestStreak(of: facts, calendar: calendar) == 2)
        #expect(ReadingInsights.make(facts: facts, calendar: calendar).readingDaysCount == 2)
    }

    // MARK: T-517 — like for like

    private func julyFact(_ dayOfMonth: Int) -> ReadingSessionFacts {
        sitting(at: instant(month: 7, dayOfMonth, 12), minutes: 60, words: 1_000)
    }

    @Test func aTenDayPartialMonthIsComparedWithTenDaysNotTheWholeMonth() {
        let july = (1...31).map(julyFact)
        let tenDays = DateInterval(start: day(1, hour: 0), end: day(11, hour: 0))
        let insights = ReadingInsights.make(
            facts: [fact(on: 2, minutes: 60, words: 1_000)],
            previousPeriodFacts: july, dayRange: tenDays, calendar: calendar
        )
        #expect(insights.previousPeriodSeconds == Double(10 * 3_600))
        #expect(insights.previousPeriodWordsRead == 10_000)
        // No day range (a year): the earlier period stays whole.
        let whole = ReadingInsights.make(
            facts: [fact(on: 2, minutes: 60)], previousPeriodFacts: july, calendar: calendar
        )
        #expect(whole.previousPeriodSeconds == Double(31 * 3_600))
        // Nothing read in those ten days last month: no delta, not a delta against zero.
        let none = ReadingInsights.make(
            facts: [fact(on: 2, minutes: 60)], previousPeriodFacts: [julyFact(20)],
            dayRange: tenDays, calendar: calendar
        )
        #expect(none.previousPeriodSeconds == nil)
        #expect(none.previousPeriodWordsRead == nil)
    }

    // MARK: T-517 — visits under 5 minutes apart are one sitting for the median

    private func visits(secondStartsAtMinute second: Int) -> [ReadingSessionFacts] {
        [
            sitting(at: instant(1, 12, 0), minutes: 10),
            sitting(at: instant(1, 12, second), minutes: 10),
            sitting(at: instant(3, 12), minutes: 30),
            sitting(at: instant(5, 12), minutes: 60)
        ]
    }

    @Test func twoVisitsFourMinutesApartAreOneSittingForTheMedian() {
        // The first visit ends 12:10; the second starts 12:14.
        let facts = visits(secondStartsAtMinute: 14)
        #expect(ReadingInsights.medianSeconds(of: facts) == 30 * 60)   // 20, 30, 60
        // Stored sittings are untouched: the bars still count four visits.
        #expect(ReadingInsights.sittingBuckets(from: facts).reduce(0) { $0 + $1.count } == 4)
    }

    @Test func twoVisitsSixMinutesApartAreTwoSittingsForTheMedian() {
        let facts = visits(secondStartsAtMinute: 16)
        #expect(ReadingInsights.medianSeconds(of: facts) == 20 * 60)   // 10, 10, 30, 60
    }

    // MARK: T-517 — Checks: numbers that must agree

    /// A month of reading with no two visits within 5 minutes of each other and none before 04:00.
    private func checkFixture() -> (facts: [ReadingSessionFacts], period: DateInterval, dayRange: DateInterval?) {
        let a = UUID(), b = UUID(), c = UUID()
        let rows: [(UUID, Int, Int, Double, Int, String)] = [
            (a, 1, 9, 20, 4_000, "Naruto"), (a, 2, 21, 45, 9_000, "Naruto"),
            (b, 4, 13, 90, 12_000, "Dracula"), (b, 4, 22, 30, 6_000, "Dracula"),
            (c, 9, 6, 5, 1_000, ""), (c, 12, 15, 150, 30_000, "Blade Runner"),
            (a, 20, 23, 35, 7_000, "Naruto")
        ]
        let facts = rows.map { work, d, h, minutes, words, fandom in
            ReadingSessionFacts(
                workID: work, startedAt: day(d, hour: h), durationSeconds: minutes * 60,
                wordCount: words * 3, didFinish: false, fandom: fandom, wordsRead: words
            )
        }
        let period = DateInterval(start: day(1, hour: 0), end: day(1, hour: 0).addingTimeInterval(31 * 86_400))
        return (facts, period, period)
    }

    @Test func checkWordsAddUp() {
        let (facts, _, range) = checkFixture()
        let insights = ReadingInsights.make(facts: facts, dayRange: range, calendar: calendar)
        let total = insights.totalWordsRead
        #expect(total == facts.reduce(0) { $0 + $1.wordsRead })
        #expect(insights.dailyWords.reduce(0) { $0 + $1.words } == total)
        #expect(insights.fandomWordsShares.reduce(0) { $0 + $1.words } == total)
        let habits = ReadingHabitsInsights.make(works: [], facts: facts, allFacts: facts, calendar: calendar)
        #expect(habits.calendarDays.reduce(0) { $0 + $1.words } == total)
    }

    @Test func checkTimeAddsUp() {
        let (facts, _, range) = checkFixture()
        let insights = ReadingInsights.make(facts: facts, dayRange: range, calendar: calendar)
        #expect(insights.hourlyDuration.reduce(0) { $0 + $1.seconds } == insights.readingSeconds)
        #expect(insights.readingSeconds == insights.totalSeconds)
        // The least time the Sittings bars can hold, bar by bar, cannot exceed the total.
        let floors: [Double] = [0, 10, 30, 60, 120].map { $0 * 60 }
        let implied = zip(insights.sittingBuckets, floors).reduce(0) { $0 + Double($1.0.count) * $1.1 }
        #expect(implied <= insights.totalSeconds)
    }

    @Test func checkSittingsAddUp() {
        let (facts, _, _) = checkFixture()
        let insights = ReadingInsights.make(facts: facts, calendar: calendar)
        let counted = facts.filter { $0.durationSeconds > 0 }.count
        #expect(insights.sittingBuckets.reduce(0) { $0 + $1.count } == counted)
        // Seven sittings: the middle one is the 4th shortest (35 min), in the 30–60 m bar.
        let sorted = facts.map(\.durationSeconds).sorted()
        let middle = sorted[sorted.count / 2]
        func bar(_ seconds: Double) -> Int {
            [10, 30, 60, 120].firstIndex { seconds / 60 < Double($0) } ?? 4
        }
        #expect(bar(insights.medianSessionSeconds) == bar(middle))
        #expect(insights.medianSessionSeconds == middle)
    }

    @Test func checkWorksAddUp() {
        let (facts, _, _) = checkFixture()
        let insights = ReadingInsights.make(facts: facts, calendar: calendar)
        #expect(insights.lengthMix.totalWorks == Set(facts.map(\.workID)).count)

        let finished = SavedWork(title: "F", author: "A")
        finished.isFinished = true
        let reading = SavedWork(title: "R", author: "A")
        reading.lastSpineIndex = 2
        let later = SavedWork(title: "L", author: "A")
        later.isQueuedForLater = true
        let wip = SavedWork(title: "W", author: "A")
        wip.isComplete = false
        let done = SavedWork(title: "D", author: "A")
        done.isComplete = true
        let works = [finished, reading, later, wip, done]
        #expect(ReadingInsights.partitionStatuses(works: works).total == works.count)
        #expect(ReadingInsights.wipFreshness(works: works).total == works.filter { !$0.isComplete }.count)
    }

    @Test func hourBarsSpreadAcrossClockHoursAndAgreeWithTotalTime() {
        var crossing = fact(on: 1, hour: 23, minutes: 90, words: 1_000)
        crossing.tzOffsetSeconds = 0
        var listening = fact(on: 2, hour: 12, minutes: 30)
        listening.mode = .listen
        let figures = ReadingInsights.make(facts: [crossing, listening], calendar: calendar)
        #expect(figures.hourlyDuration[23].seconds == 3_600)
        #expect(figures.hourlyDuration[0].seconds == 1_800)
        #expect(figures.hourlyDuration.reduce(0) { $0 + $1.seconds } == figures.readingSeconds)
        #expect(figures.silentReadingSeconds + figures.listeningSeconds == figures.readingSeconds)
        #expect(figures.silentReadingSeconds == 5_400)
        #expect(figures.listeningSeconds == 1_800)
    }

    @Test func explicitStatusesWinAndUntouchedIsNotStopped() {
        let stopped = SavedWork(title: "Stopped", author: "A")
        stopped.readingStatusRaw = "stopped"
        stopped.isFinished = true
        let stacking = SavedWork(title: "Stacking", author: "A")
        stacking.readingStatusRaw = "stacking"
        let later = SavedWork(title: "Later", author: "A")
        let partition = ReadingInsights.partitionStatuses(works: [stopped, stacking, later])
        #expect(partition.stoppedCount == 1)
        #expect(partition.stackingCount == 1)
        #expect(partition.savedForLaterCount == 1)
        #expect(partition.finishedCount == 0)
        #expect(partition.total == 3)

        let library = ReadingLibraryInsights.make(
            works: [stopped, stacking, later], facts: [],
            periodInterval: DateInterval(start: day(1), end: day(2)), calendar: calendar
        )
        #expect(library.unreadWorksCount == 1)
    }

    @Test func arrivalAndFoundEarlyUseOnlyRecordedSaveFacts() {
        let early = SavedWork(title: "Early", author: "A")
        early.isFinished = true
        early.importSourceRaw = WorkImportSource.search.rawValue
        early.statsSavedAt = day(1)
        early.kudosAtSave = 100
        early.kudos = 350
        let old = SavedWork(title: "Old", author: "A")
        old.isFinished = true
        old.kudos = 2_000
        let figures = ReadingLibraryInsights.make(
            works: [early, old], facts: [],
            periodInterval: DateInterval(start: day(1), end: day(2)), calendar: calendar
        )
        #expect(figures.arrivalRows.first?.finished == 1)
        #expect(figures.arrivalRows.first?.saved == 1)
        #expect(figures.arrivalRows.first?.label == "Other")
        #expect(figures.foundEarlyCount == 1)
        #expect(figures.foundEarlyGrownCount == 1)
        #expect(figures.foundEarlyExample?.contains("100 then, 350 now") == true)

        let beforeRecording = ReadingLibraryInsights.make(
            works: [old], facts: [],
            periodInterval: DateInterval(start: day(1), end: day(2)), calendar: calendar
        )
        #expect(beforeRecording.arrivalRows.isEmpty)
        #expect(beforeRecording.foundEarlyCount == 0)
    }

    @Test func seriesAuthorsAndFavoritesUseRecordedIdentityAndLastPart() {
        let first = SavedWork(title: "First", author: "A")
        first.ao3SeriesID = 7
        first.seriesPosition = 1
        first.lastSpineIndex = 1
        first.lastReadDate = day(1)
        first.isFinished = true
        first.isFavorite = true
        first.verifiedAuthorIdentities = [AO3AuthorIdentity(route: AO3AuthorRoute(username: "writer")!)]
        let last = SavedWork(title: "Last", author: "A")
        last.ao3SeriesID = 7
        last.seriesPosition = 3
        last.lastSpineIndex = 1
        last.lastReadDate = day(2)
        last.isFinished = true
        last.verifiedAuthorIdentities = first.verifiedAuthorIdentities
        let series = SavedSeriesSnapshot(ao3SeriesID: 7, title: "Series", partCount: 3,
            isComplete: true, wordCount: 30_000)
        let allFacts = [fact(work: first.id, on: 1, minutes: 30, words: 1_000),
                        fact(work: last.id, on: 2, minutes: 30, words: 2_000)]
        let figures = ReadingLibraryInsights.make(
            works: [first, last], facts: allFacts, allFacts: allFacts,
            seriesSnapshots: [series], periodInterval: DateInterval(start: day(1), end: day(3)),
            calendar: calendar
        )
        #expect(figures.favoriteWithoutKudosCount == 1)
        #expect(figures.seriesStartedCount == 1)
        #expect(figures.seriesReadToLastCount == 1)
        #expect(figures.seriesNextWaitingCount == 0)
        #expect(figures.authors.first?.name == "writer")
        #expect(figures.authors.first?.works == 2)
        #expect(figures.authors.first?.words == 3_000)
    }

    @Test func tasteTagsCountWorksAndUnknownLabelsFillBreakdowns() {
        let work = SavedWork(title: "T", author: "A")
        work.workTags = ["Shared"]
        let facts = [fact(work: work.id, on: 1, minutes: 30, words: 100),
                     fact(work: work.id, on: 2, minutes: 30, words: 200)]
        let taste = ReadingTasteInsights.make(works: [work], facts: facts)
        #expect(taste.tags.first?.count == 1)
        #expect(taste.tags.first?.words == 300)
        #expect(taste.ratings.reduce(0) { $0 + $1.count } == 1)
        #expect(taste.languages.reduce(0) { $0 + $1.count } == 1)
        #expect(taste.yearCounts.isEmpty)
        #expect(taste.usualFicTags.isEmpty)
        #expect(taste.usualFicSummary.contains("five works"))
    }

    @Test func usualFicCallsUnsharedFieldsVariedAfterFiveWorks() {
        let works = (0..<5).map { SavedWork(title: "\($0)", author: "A") }
        for (index, work) in works.enumerated() { work.rating = "Rating \(index)" }
        let facts = works.enumerated().map { index, work in
            fact(work: work.id, on: index + 1, minutes: 20, words: 100)
        }
        let taste = ReadingTasteInsights.make(works: works, facts: facts)
        #expect(taste.usualRating == "varied")
        #expect(taste.usualFicSummary.contains("varied"))
    }

    @Test func oftenTogetherRequiresThreeWorksAndLiftAboveChance() {
        let works = (0..<6).map { SavedWork(title: "\($0)", author: "A") }
        for work in works.prefix(3) { work.workTags = ["A", "B"] }
        for work in works.dropFirst(3) { work.workTags = ["C"] }
        let pairs = ReadingInsights.oftenTogetherTags(from: works)
        #expect(pairs.count == 1)
        #expect(pairs.first?.tagA == "A")
        #expect(pairs.first?.tagB == "B")
        #expect(ReadingInsights.oftenTogetherTags(from: Array(works.prefix(2))).isEmpty)
    }

    @Test func checkShownFiguresReproduce() {
        let (facts, _, _) = checkFixture()
        let insights = ReadingInsights.make(facts: facts, calendar: calendar)
        let hours = insights.readingSeconds / 3_600
        #expect(abs(insights.wordsPerHour - Double(insights.totalWordsRead) / hours) < 1e-9)
        let words = 212_600
        #expect(ReadingInsights.novelsWorth(words: words) == (Double(words) / 70_000 * 2).rounded() / 2)

        let unread = SavedWork(title: "U", author: "A")
        unread.wordCount = 120_000
        let library = ReadingLibraryInsights.make(
            works: [unread], facts: facts,
            periodInterval: DateInterval(start: day(1, hour: 0), end: day(28, hour: 0)),
            periodMonths: 1, calendar: calendar
        )
        let monthly = Double(insights.totalWordsRead)
        #expect(library.monthsToClear == max(1, Int((120_000 / monthly).rounded())))
    }

    @Test func checkHistoryHoldsStill() {
        let (august, period, _) = checkFixture()
        // July, which August is compared with, and September, which arrives later.
        let july = (1...31).map(julyFact)
        let september = [sitting(at: instant(month: 9, 3, 12), minutes: 60, words: 5_000)]
        func augustAsSeen(on now: Date, log: [ReadingSessionFacts]) -> ReadingInsights {
            let current = log.filter { period.contains($0.startedAt) }
            let previous = log.filter {
                $0.startedAt < period.start && $0.startedAt >= instant(month: 7, 1, 0)
            }
            let range = ReadingInsights.chartDays(for: period, now: now, calendar: calendar)
            return ReadingInsights.make(
                facts: current, previousPeriodFacts: previous, dayRange: range, calendar: calendar
            )
        }
        let atTheEnd = augustAsSeen(on: instant(31, 18), log: august + july)
        let nextMonth = augustAsSeen(on: instant(month: 9, 15, 9), log: august + july + september)
        #expect(atTheEnd == nextMonth)
    }

    @Test func checkSaneSittingsClampProgress() {
        // Progress outside 0…1 and an end before the start cannot make a start or a word count
        // that runs backwards.
        let work = UUID()
        var odd = ReadingSessionFacts(
            workID: work, startedAt: day(1), durationSeconds: 600, wordCount: 1_000,
            didFinish: false, wordsRead: 0, endingProgress: 1.7
        )
        odd.startProgress = -0.4
        let starts = ReadingInsights.startingProgress(of: [odd])
        #expect(starts == [0])
        #expect(ReadingInsights.make(facts: [odd], calendar: calendar).totalSeconds >= 0)
    }
}
