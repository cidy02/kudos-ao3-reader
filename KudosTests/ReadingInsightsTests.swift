import Foundation
import SwiftData
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

    @Test func shipConcentrationUsesFandomWordsAndFourUniqueWorks() {
        let ship = RelationshipShare(name: "A/B", isRomantic: true, fandom: "F",
            worksCount: 2, words: 3_000)
        let tooFew = ReadingInsights.shipConcentrations(
            relationships: [ship], fandomWords: ["F": 10_000], fandomWorkCounts: ["F": 3]
        )
        #expect(tooFew.isEmpty)
        let enough = ReadingInsights.shipConcentrations(
            relationships: [ship], fandomWords: ["F": 10_000], fandomWorkCounts: ["F": 4]
        )
        #expect(enough.first?.percentage == 30)
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
        // Insights-Metrics: openedToFinished covers complete works finished in the period.
        let work = SavedWork(title: "W", author: "A")
        work.isComplete = true
        work.dateAdded = day(1)
        let wip = SavedWork(title: "WIP", author: "A")
        wip.isComplete = false
        wip.dateAdded = day(1)
        let reread = SavedWork(title: "Reread", author: "A")
        reread.isComplete = true
        reread.dateAdded = day(1)
        let period = DateInterval(start: day(10, hour: 0), end: day(20, hour: 0))
        let priorFinish = ReadingSessionFacts(
            workID: reread.id, startedAt: day(2), durationSeconds: 600, wordCount: 1000, didFinish: true
        )
        let periodFacts = [
            ReadingSessionFacts(workID: work.id, startedAt: day(11), durationSeconds: 600, wordCount: 1000, didFinish: false),
            ReadingSessionFacts(workID: work.id, startedAt: day(15), durationSeconds: 600, wordCount: 1000, didFinish: true),
            ReadingSessionFacts(workID: wip.id, startedAt: day(11), durationSeconds: 600, wordCount: 1000, didFinish: false),
            ReadingSessionFacts(workID: wip.id, startedAt: day(19), durationSeconds: 600, wordCount: 1000, didFinish: true),
            ReadingSessionFacts(workID: reread.id, startedAt: day(18), durationSeconds: 600, wordCount: 1000, didFinish: true)
        ]
        let habits = ReadingHabitsInsights.make(
            works: [work, wip, reread],
            facts: periodFacts,
            allFacts: [priorFinish] + periodFacts,
            periodInterval: period,
            calendar: calendar
        )
        #expect(habits.savedToOpenedMedianDays == 10)
        #expect(habits.openedToFinishedMedianDays == 4)
        #expect(habits.openedToFinishedCount == 1)
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

    @MainActor
    @Test func allTabsReconcileFromOneFilteredPeriod() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
            ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
            QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self,
            FollowedTag.self, TagAlias.self, SavedSeries.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let sepPeriod = DateInterval(start: instant(month: 9, 1, 0), end: instant(month: 10, 1, 0))
        let octPeriod = DateInterval(start: instant(month: 10, 1, 0), end: instant(month: 11, 1, 0))
        let now = instant(month: 10, 31, 20)

        let workA = SavedWork(title: "Work A", author: "Author A")
        workA.ao3WorkID = 1001
        workA.wordCount = 20_000
        workA.rating = "Teen"
        workA.isComplete = true
        workA.isFinished = true
        workA.language = "English"
        workA.workFandoms = ["Persuasion"]
        workA.workFreeforms = ["Slow Burn"]

        let workB = SavedWork(title: "Work B", author: "Author B")
        workB.ao3WorkID = 1002
        workB.wordCount = 30_000
        workB.rating = "General Audiences"
        workB.isComplete = true
        workB.language = "English"
        workB.workFandoms = ["Sherlock Holmes"]

        let workC = SavedWork(title: "Work C", author: "Author C")
        workC.ao3WorkID = 1003
        workC.wordCount = 12_000
        workC.rating = "Mature"
        workC.isComplete = true
        workC.language = "Japanese"
        workC.wordUnitRaw = SavedWork.WordUnit.characters.rawValue
        workC.workFandoms = ["BNHA"]

        let workExcluded = SavedWork(title: "Excluded Work", author: "Author E")
        workExcluded.ao3WorkID = 1004
        workExcluded.wordCount = 50_000
        workExcluded.isComplete = true
        workExcluded.isFinished = true
        workExcluded.workFandoms = ["Excluded Fandom"]

        let workUnread = SavedWork(title: "Unread Work", author: "Author U")
        workUnread.ao3WorkID = 1005
        workUnread.wordCount = 120_000
        workUnread.isComplete = false
        workUnread.workFandoms = ["Persuasion"]

        let liveWorks = [workA, workB, workC, workExcluded, workUnread]
        liveWorks.forEach { context.insert($0) }

        // 01:30 UTC on Oct 1 -> readingDay Sep 30 (previous month, NOT October).
        let sSep = ReadingSession(
            workID: workA.id, startedAt: instant(month: 10, 1, 1, 30),
            endedAt: instant(month: 10, 1, 2, 0), durationSeconds: 1_800,
            tzOffsetSeconds: 0, startProgress: 0, endingProgress: 0.25,
            wordCount: 20_000, didFinish: false
        )
        sSep.snapshot(from: workA)

        // Oct 2 noon UTC: 10,000 words read.
        let sOct2 = ReadingSession(
            workID: workA.id, startedAt: instant(month: 10, 2, 12, 0),
            endedAt: instant(month: 10, 2, 13, 0), durationSeconds: 3_600,
            tzOffsetSeconds: 0, startProgress: 0.25, endingProgress: 0.75,
            wordCount: 20_000, didFinish: false
        )
        sOct2.snapshot(from: workA)

        // 01:30 UTC on Nov 1 -> readingDay Oct 31 (still October, 5,000 words read).
        let sOct31 = ReadingSession(
            workID: workA.id, startedAt: instant(month: 11, 1, 1, 30),
            endedAt: instant(month: 11, 1, 2, 0), durationSeconds: 1_800,
            tzOffsetSeconds: 0, startProgress: 0.75, endingProgress: 1.0,
            wordCount: 20_000, didFinish: true
        )
        sOct31.snapshot(from: workA)

        // Time-zone change: Oct 1 08:00 +09:00 (= Sep 30 23:00 UTC), Read Aloud 1.25x, 15,000 words.
        let sTokyoListen = ReadingSession(
            workID: workB.id, startedAt: instant(month: 10, 1, 8, 0, offsetHours: 9),
            endedAt: instant(month: 10, 1, 9, 0, offsetHours: 9), durationSeconds: 3_600,
            tzOffsetSeconds: 9 * 3_600, startProgress: 0, modeRaw: ReadingSession.Mode.listen.rawValue,
            playbackRate: 1.25, endingProgress: 0.5, wordCount: 30_000, didFinish: false
        )
        sTokyoListen.snapshot(from: workB)

        // Oct 10: .characters work (6,000 characters, 0 words).
        let sJapanese = ReadingSession(
            workID: workC.id, startedAt: instant(month: 10, 10, 15, 0),
            endedAt: instant(month: 10, 10, 15, 30), durationSeconds: 1_800,
            tzOffsetSeconds: 0, startProgress: 0, endingProgress: 0.5,
            wordCount: 12_000, didFinish: false
        )
        sJapanese.snapshot(from: workC)

        // Oct 15: deleted work (not inserted into liveWorks) with D1 snapshot, 10,000 words.
        let deletedID = UUID()
        let sDeleted = ReadingSession(
            workID: deletedID, workTitle: "Deleted Fic",
            startedAt: instant(month: 10, 15, 20, 0),
            endedAt: instant(month: 10, 15, 20, 30), durationSeconds: 1_800,
            tzOffsetSeconds: 0, startProgress: 0, endingProgress: 1.0,
            wordCount: 10_000, didFinish: true
        )
        sDeleted.metadataSnapshotRecorded = true
        sDeleted.fandoms = ["Jane Eyre"]
        sDeleted.rating = "Explicit"
        sDeleted.language = "English"
        sDeleted.isCompleteAtVisit = true

        // Oct 20: excluded fandom work — must be dropped from every tab by InsightsOptions.filter.
        let sExcluded = ReadingSession(
            workID: workExcluded.id, startedAt: instant(month: 10, 20, 12, 0),
            endedAt: instant(month: 10, 20, 13, 0), durationSeconds: 3_600,
            tzOffsetSeconds: 0, startProgress: 0, endingProgress: 1.0,
            wordCount: 50_000, didFinish: true
        )
        sExcluded.snapshot(from: workExcluded)

        [sSep, sOct2, sOct31, sTokyoListen, sJapanese, sDeleted, sExcluded].forEach { context.insert($0) }
        try context.save()

        let options = InsightsOptions(excludedFandoms: ["Excluded Fandom"])
        let gathered = ReadingLogService.gatherInsights(
            for: octPeriod,
            previousPeriod: sepPeriod,
            works: liveWorks,
            readingWorks: liveWorks,
            periodMonths: 1,
            calendar: calendar,
            context: context,
            options: options,
            now: now
        )
        let overview = gathered.insights
        let taste = try #require(gathered.taste)
        let habits = gathered.habits
        let library = gathered.library

        let expectedWords = 40_000
        #expect(overview.totalWordsRead == expectedWords)
        #expect(overview.previousPeriodWordsRead == 5_000)
        #expect(overview.charactersRead == 6_000)
        #expect(overview.dailyWords.count == 31)
        #expect(habits.calendarDays.count == overview.dailyWords.count)
        #expect(overview.dailyWords.reduce(0) { $0 + $1.words } == expectedWords)
        #expect(overview.fandomWordsShares.reduce(0) { $0 + $1.words } == expectedWords)
        #expect(taste.fandoms.reduce(0) { $0 + $1.words } == expectedWords)
        #expect(habits.calendarDays.reduce(0) { $0 + $1.words } == expectedWords)
        #expect(library.readWordsInPeriod == expectedWords)
        #expect(habits.fandomTimeline.reduce(0) { (total: Int, lane: ReadingHabitsInsights.FandomTimelineLane) -> Int in
            total + lane.monthlyWords[9]
        } == expectedWords)

        #expect(overview.readingDaysCount == 5)
        #expect(habits.calendarDays.filter { $0.hasReading || $0.words > 0 }.count == overview.readingDaysCount)

        #expect(overview.silentReadingSeconds == 9_000)
        #expect(overview.listeningSeconds == 3_600)
        #expect(overview.silentReadingSeconds + overview.listeningSeconds == overview.readingSeconds)
        #expect(overview.listeningPlaybackRate == 1.25)
        #expect(overview.listeningWorksCount == 1)
        #expect(habits.hourlyDuration.reduce(0) { $0 + $1.seconds } == overview.readingSeconds)
        #expect(habits.sittingBuckets.reduce(0) { $0 + $1.count } == 5)
        #expect(habits.typicalSittingSeconds == overview.medianSessionSeconds)

        // Works read = workA, workB, workC (.characters), deletedID (D1 snapshot).
        #expect(overview.lengthMix.totalWorks == 4)
        #expect(taste.totalWorksCount == 4)
        #expect(taste.ratings.reduce(0) { $0 + $1.count } == 4)
        #expect(taste.ratings.first { $0.label == "Teen" }?.words == 15_000)
        #expect(taste.statuses.reduce(0) { $0 + $1.count } == 4)
        #expect(taste.lengthBands.reduce(0) { $0 + $1.count } == 4)
        #expect(taste.languages.reduce(0) { $0 + $1.count } == 4)
        #expect(library.statuses.total == 4)
        #expect(library.wipFreshness.total == 1)

        // Visual reading pace excludes listening (sTokyoListen) and characters (sJapanese): 25k / 2h.
        #expect(overview.wordsPerHour == 12_500)
        #expect(overview.charactersPerHour == 12_000)
        #expect(!overview.fandomWordsShares.contains { $0.name == "Excluded Fandom" })
        #expect(!taste.fandoms.contains { $0.name == "Excluded Fandom" })
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

    @Test func pausedSittingSpreadsActiveTimeAcrossItsWallClockSpan() {
        var paused = fact(on: 1, hour: 23, minutes: 60)
        paused.startedAt = day(1, hour: 23).addingTimeInterval(30 * 60)
        paused.endedAt = paused.startedAt.addingTimeInterval(2 * 3_600)
        paused.tzOffsetSeconds = 0
        let hours = ReadingInsights.hourlyDurationBuckets(from: [paused], calendar: calendar)
        #expect(hours[23].seconds == 900)
        #expect(hours[0].seconds == 1_800)
        #expect(hours[1].seconds == 900)
        #expect(hours.reduce(0) { $0 + $1.seconds } == paused.durationSeconds)
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
        early.importSourceSince = day(1)
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
        #expect(figures.arrivalSince == day(1))
        #expect(figures.foundEarlyCount == 1)
        #expect(figures.foundEarlyGrownCount == 1)
        #expect(figures.foundEarlyGrowthShare == 1)
        #expect(figures.foundEarlyExample?.contains("100 then, 350 now") == true)

        let beforeRecording = ReadingLibraryInsights.make(
            works: [old], facts: [],
            periodInterval: DateInterval(start: day(1), end: day(2)), calendar: calendar
        )
        #expect(beforeRecording.arrivalRows.isEmpty)
        #expect(beforeRecording.arrivalSince == nil)
        #expect(beforeRecording.foundEarlyCount == 0)
        #expect(beforeRecording.foundEarlyGrowthShare == nil)
    }

    @Test func seriesAuthorsAndFavoritesUseRecordedIdentityAndLastPart() {
        let first = SavedWork(title: "First", author: "A")
        first.ao3WorkID = 101
        first.ao3SeriesID = 7
        first.seriesPosition = 1
        first.lastSpineIndex = 1
        first.lastReadDate = day(1)
        first.isFinished = true
        first.isFavorite = true
        first.verifiedAuthorIdentities = [AO3AuthorIdentity(route: AO3AuthorRoute(username: "writer")!)]
        let last = SavedWork(title: "Last", author: "A")
        last.ao3WorkID = 102
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
        #expect(figures.longestFinishedSeries?.title == "Series")
        #expect(figures.longestFinishedSeries?.partCount == 3)
        #expect(figures.longestFinishedSeries?.wordCount == 30_000)
        #expect(figures.seriesNextWaitingCount == 0)
        #expect(figures.authors.first?.name == "writer")
        #expect(figures.authors.first?.works == 2)
        #expect(figures.authors.first?.words == 3_000)
    }

    @Test func nextSeriesPartRequiresAStoredPartOrAO3WorkIdentity() {
        let first = SavedWork(title: "First", author: "A")
        first.ao3WorkID = 701
        first.ao3SeriesID = 77
        first.seriesPosition = 1
        first.lastReadDate = day(1)
        first.isFinished = true
        let inProgressFirst = SavedWork(title: "In Progress", author: "A")
        inProgressFirst.ao3WorkID = 701
        inProgressFirst.ao3SeriesID = 77
        inProgressFirst.seriesPosition = 1
        inProgressFirst.lastReadDate = day(1)
        inProgressFirst.isFinished = false
        let unread = SavedWork(title: "Next", author: "A")
        unread.ao3WorkID = 702
        unread.ao3SeriesID = 77
        unread.seriesPosition = 2
        let partial = SavedSeriesSnapshot(ao3SeriesID: 77, title: "Series", partCount: 2,
                                          isComplete: false, wordCount: 2_000)
        let known = SavedSeriesSnapshot(ao3SeriesID: 77, title: "Series", partCount: 2,
                                        isComplete: false, wordCount: 2_000,
                                        partWorkIDs: [701, 702])
        let interval = DateInterval(start: day(1), end: day(3))
        func count(_ works: [SavedWork], _ snapshot: SavedSeriesSnapshot) -> Int {
            ReadingLibraryInsights.make(works: works, facts: [], seriesSnapshots: [snapshot],
                                        periodInterval: interval, calendar: calendar).seriesNextWaitingCount
        }
        #expect(count([first], partial) == 0)
        #expect(count([first, unread], partial) == 1)
        #expect(count([first], known) == 1)
        // Still reading Part 1: Part 2 is not waiting until Part 1 is finished.
        #expect(count([inProgressFirst, unread], partial) == 0)
        #expect(count([inProgressFirst], known) == 0)
    }

    @Test func deletedWorkKeepsVerifiedCoauthorTotalsFromSessionSnapshot() {
        let deletedID = UUID()
        var first = fact(work: deletedID, on: 1, minutes: 20, words: 400)
        first.authorAccounts = ["writer", "partner"]
        var finish = fact(work: deletedID, on: 2, minutes: 20, words: 600, didFinish: true)
        finish.authorAccounts = ["writer", "partner"]
        let interval = DateInterval(start: day(1), end: day(3))
        let result = ReadingLibraryInsights.make(
            works: [], facts: [first, finish], allFacts: [first, finish],
            periodInterval: interval, calendar: calendar
        )
        #expect(result.authors.count == 2)
        #expect(result.authors.allSatisfy { $0.works == 1 && $0.words == 1_000 && $0.finished == 1 })
    }

    @Test func arrivalShareRateAndFoundEarlyUseRecordedDenominators() {
        let rows = [
            ReadingLibraryInsights.ArrivalRow(label: "Search", finished: 3, saved: 6),
            ReadingLibraryInsights.ArrivalRow(label: "Other", finished: 1, saved: 4)
        ]
        #expect(rows[0].finishedSharePercent(totalFinished: 4) == 75)
        #expect(rows[0].finishRatePercent == 50)
        #expect(rows[1].finishedSharePercent(totalFinished: 4) == 25)
        #expect(rows[1].finishRatePercent == 25)
        #expect(rows.reduce(0) { $0 + $1.finishedSharePercent(totalFinished: 4) } == 100)
    }

    @Test func smallArrivalSourcesFoldIntoOtherWhileKeepingFinishedTotals() {
        let search = (0..<5).map { index -> SavedWork in
            let work = SavedWork(title: "Search \(index)", author: "A")
            work.importSourceRaw = WorkImportSource.search.rawValue
            work.isFinished = index < 3
            return work
        }
        let other = (0..<2).map { index -> SavedWork in
            let work = SavedWork(title: "Series \(index)", author: "A")
            work.importSourceRaw = WorkImportSource.series.rawValue
            work.isFinished = index == 0
            return work
        }
        let result = ReadingLibraryInsights.make(
            works: search + other, facts: [],
            periodInterval: DateInterval(start: day(1), end: day(3)), calendar: calendar
        )
        #expect(result.arrivalRows.count == 2)
        #expect(result.arrivalRows.first { $0.label == "Search" }?.finished == 3)
        #expect(result.arrivalRows.first { $0.label == "Other" }?.saved == 2)
        #expect(result.arrivalRows.reduce(0) { $0 + $1.finished } == 4)
    }

    @Test func sparseNinetyDayPaceShowsOutwardRoundedRange() {
        let unread = SavedWork(title: "Unread", author: "A")
        unread.wordCount = 540_000
        let recent = (25...31).map { dayOfMonth in
            fact(on: dayOfMonth, minutes: 30, words: 3_000)
        }
        let result = ReadingLibraryInsights.make(
            works: [unread], facts: recent, allFacts: recent,
            periodInterval: DateInterval(start: day(1), end: day(31, hour: 23)),
            calendar: calendar, now: day(31, hour: 23)
        )
        #expect(result.unreadWords == 540_000)
        #expect(result.monthsToClear == nil)
        #expect(result.monthsToClearRange == 4...8)
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
        let ao3Ratings = ["General Audiences", "Teen", "Mature", "Explicit", "Not Rated"]
        let works = ao3Ratings.enumerated().map { (index: Int, rating: String) -> SavedWork in
            let work = SavedWork(title: "Work \(index)", author: "A")
            work.rating = rating
            return work
        }
        let facts = works.enumerated().map { (index: Int, work: SavedWork) -> ReadingSessionFacts in
            fact(work: work.id, on: index + 1, minutes: 20, words: 100)
        }
        let taste = ReadingTasteInsights.make(works: works, facts: facts)
        // Every rating must be counted (never silently dropped) and short labels keep their words.
        #expect(taste.ratings.reduce(0) { $0 + $1.count } == 5)
        #expect(taste.ratings.first { $0.label == "Teen" }?.words == 100)
        #expect(taste.ratings.first { $0.label == "General" }?.words == 100)
        // Each rating has 20% (< 40% threshold), so Usual Fic reports "varied".
        #expect(taste.usualRating == "varied")
        #expect(taste.usualFicSummary.contains("varied"))
    }

    @Test func tasteRankToggleChangesTagStatusAndCompositeWeights() {
        let works = (0..<5).map { SavedWork(title: "\($0)", author: "A") }
        var facts: [ReadingSessionFacts] = []
        for (index, work) in works.enumerated() {
            let frequent = index < 3
            work.workTags = [frequent ? "Frequent" : "Heavy"]
            work.workCategories = ["F/M", "Gen"]
            work.workWarnings = ["No Archive Warnings Apply", "Some Warning"]
            work.isComplete = !frequent
            let words = frequent ? 1_000 : 10_000
            facts.append(fact(work: work.id, on: index + 1, minutes: 30, words: words))
        }
        let taste = ReadingTasteInsights.make(works: works, facts: facts)
        let byWorks = taste.ranked(byWorks: true)
        let byWords = taste.ranked(byWorks: false)
        #expect(byWorks.tags.first?.name == "Frequent")
        #expect(byWords.tags.first?.name == "Heavy")
        #expect(byWorks.statuses.first?.label == "Work in Progress")
        #expect(byWords.statuses.first?.label == "Complete")
        #expect(byWords.usualStatus == "Complete")
        #expect(byWords.usualTopTag == "Heavy")
        #expect(byWorks.usualLengthBand == "Under 5k")
        #expect(taste.categories.reduce(0) { $0 + $1.count } == 10)
        #expect(taste.warnings.reduce(0) { $0 + $1.count } == 10)
    }

    @Test func usualFicRequiresFiveReadWorksAndUsesFortyPercentForEachField() {
        let works = (0..<5).map { SavedWork(title: "\($0)", author: "A") }
        var facts: [ReadingSessionFacts] = []
        for (index, work) in works.enumerated() {
            work.wordCount = index < 3 ? 12_000 : 100_000
            work.workTags = index < 2 ? ["Common", "Second"] : ["Other"]
            facts.append(fact(work: work.id, on: index + 1, minutes: 20, words: 1_000))
        }
        let four = ReadingTasteInsights.make(works: works, facts: Array(facts.prefix(4)))
        #expect(four.usualChips.isEmpty)
        let five = ReadingTasteInsights.make(works: works, facts: facts).ranked(byWorks: true)
        #expect(five.usualLengthBand == "5–50k")
        #expect(five.usualTopTag != nil)
        #expect(five.usualSecondTag != nil)
        #expect(ReadingTasteInsights.make(works: works, facts: []).usualChips.isEmpty)
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

    @Test func habitsUseExplicitStopsAndFirstOpenCohort() {
        let stopped = SavedWork(title: "Stopped", author: "A")
        stopped.readingStatusRaw = "stopped"
        stopped.stoppedAt = day(2)
        stopped.stopReasonRaw = "lostInterest"
        stopped.lastReadDate = day(1)
        let openedEarlier = SavedWork(title: "Earlier", author: "A")
        openedEarlier.dateAdded = day(1)
        let old = fact(work: openedEarlier.id, on: 1, minutes: 20)
        let current = fact(work: openedEarlier.id, on: 2, minutes: 20)
        let period = DateInterval(start: day(2, hour: 0), end: day(3, hour: 0))
        let habits = ReadingHabitsInsights.make(
            works: [stopped, openedEarlier], facts: [current], allFacts: [old, current],
            periodInterval: period, calendar: calendar
        )
        #expect(habits.stoppedCount == 1)
        #expect(habits.stoppedInPeriodCount == 1)
        #expect(habits.stopReasons.first?.label == "Lost interest")
        #expect(habits.savedToOpenedCount == 0)
    }

    @Test func rereadTimeCountsOnlySittingsAfterFirstFinish() {
        let work = SavedWork(title: "Reread", author: "A")
        var finish = fact(work: work.id, on: 1, minutes: 30, didFinish: true)
        finish.sessionID = UUID()
        var reread = fact(work: work.id, on: 2, minutes: 60)
        reread.sessionID = UUID()
        let habits = ReadingHabitsInsights.make(
            works: [work], facts: [finish, reread], allFacts: [finish, reread], calendar: calendar
        )
        #expect(habits.rereadTimeShare == 2.0 / 3.0)
    }

    @Test func rereadWordDetailIncludesEverySittingAcrossReads() {
        let work = SavedWork(title: "Reread", author: "A")
        let facts = [
            fact(work: work.id, on: 1, minutes: 20, words: 100),
            fact(work: work.id, on: 2, minutes: 20, words: 200, didFinish: true),
            fact(work: work.id, on: 3, minutes: 20, words: 300),
            fact(work: work.id, on: 4, minutes: 20, words: 400, didFinish: true)
        ]
        let habits = ReadingHabitsInsights.make(
            works: [work], facts: facts, allFacts: facts, calendar: calendar
        )
        #expect(habits.rereads.first?.finishCount == 2)
        #expect(habits.rereads.first?.totalWordsAcrossReads == 1_000)
    }

    @Test func stoppedTagsNeedFiveOpenedWorksAndDoubleTheBaseline() {
        let works = (0..<10).map { SavedWork(title: "\($0)", author: "A") }
        for work in works { work.lastReadDate = day(1) }
        for work in works.prefix(5) { work.workTags = ["Trigger"] }
        for work in works.prefix(4) { work.readingStatusRaw = "stopped" }
        let habits = ReadingHabitsInsights.make(works: works, facts: [], allFacts: [], calendar: calendar)
        #expect(habits.commonStopTags.first?.name == "Trigger")
        #expect(habits.commonStopTags.first?.count == 4)
        works[4].workTags = []
        let belowFive = ReadingHabitsInsights.make(works: works, facts: [], allFacts: [], calendar: calendar)
        #expect(belowFive.commonStopTags.isEmpty)
    }

    @Test func timelineLeavesQuietMonthsBlankAndExcludesOtherYears() {
        let current = fact(on: 2, minutes: 30, words: 4_000, fandom: "F")
        var previousYear = fact(on: 2, minutes: 30, words: 100_000, fandom: "F")
        previousYear.startedAt = calendar.date(byAdding: .year, value: -1, to: current.startedAt) ?? current.startedAt
        let period = DateInterval(start: day(1), end: day(28))
        let quiet = ReadingHabitsInsights.make(
            works: [], facts: [current], allFacts: [previousYear, current],
            periodInterval: period, calendar: calendar
        )
        #expect(quiet.fandomTimeline.first?.monthlyActivity[7] == 0)
        var louder = current
        louder.wordsRead = 6_000
        let active = ReadingHabitsInsights.make(
            works: [], facts: [louder], allFacts: [previousYear, louder],
            periodInterval: period, calendar: calendar
        )
        #expect((active.fandomTimeline.first?.monthlyActivity[7] ?? 0) > 0)
    }

    @Test func calendarUsesPriorTwelveMonthReadingDayQuartiles() {
        let rows = (1...20).map { dayNumber in
            fact(on: dayNumber, minutes: 20, words: dayNumber * 1_000)
        }
        let end = day(28)
        let thresholds = ReadingHabitsInsights.calendarThresholds(
            allFacts: rows, through: end, calendar: calendar
        )
        #expect(thresholds == [6_000, 11_000, 16_000])
        let sparse = ReadingHabitsInsights.calendarThresholds(
            allFacts: Array(rows.prefix(19)), through: end, calendar: calendar
        )
        #expect(sparse == [5_000, 10_000, 20_000])
    }

    @Test func unreadPaceUsesNinetyDayHistoryAndRequiresReadingDays() {
        let unread = SavedWork(title: "Unread", author: "A")
        unread.wordCount = 30_000
        let interval = DateInterval(start: day(1), end: day(31))
        let sixDays = (21...26).map { fact(on: $0, minutes: 20, words: 1_000) }
        let six = ReadingLibraryInsights.make(
            works: [unread], facts: sixDays, allFacts: sixDays,
            periodInterval: interval, calendar: calendar, now: day(28)
        )
        #expect(six.monthsToClear == nil)
        #expect(six.monthsToClearRange == nil)
        let sevenDays = (21...27).map { fact(on: $0, minutes: 20, words: 1_000) }
        let seven = ReadingLibraryInsights.make(
            works: [unread], facts: sevenDays, allFacts: sevenDays,
            periodInterval: interval, calendar: calendar, now: day(28)
        )
        #expect(seven.monthsToClear == nil)
        #expect(seven.monthsToClearRange != nil)
        let thirtyDays = (1...30).map { fact(on: $0, minutes: 20, words: 1_000) }
        let thirty = ReadingLibraryInsights.make(
            works: [unread], facts: thirtyDays, allFacts: thirtyDays,
            periodInterval: interval, calendar: calendar, now: day(31)
        )
        #expect(thirty.monthsToClear == 1)
        #expect(thirty.monthsToClearRange == nil)
    }

    @Test func stillReadingPromptRequiresAnUnreadPostedChapter() {
        let period = DateInterval(start: day(1), end: day(31))

        let wip = SavedWork(title: "WIP", author: "A")
        wip.isComplete = false
        wip.chapters = "5/10"
        wip.lastSpineIndex = 2
        wip.lastReadDate = day(1)
        let eligible = ReadingLibraryInsights.make(
            works: [wip], facts: [], periodInterval: period,
            calendar: calendar, now: day(31)
        )
        #expect(eligible.stillReadingCandidate?.id == wip.id)

        // Paused mid-way inside the last posted chapter: NOT caught up, so still eligible.
        wip.lastSpineIndex = 4
        wip.lastScrollFraction = 0.30
        wip.legacyReaderProgress = 0.45
        let midFinalChapter = ReadingLibraryInsights.make(
            works: [wip], facts: [], periodInterval: period,
            calendar: calendar, now: day(31)
        )
        #expect(midFinalChapter.stillReadingCandidate?.id == wip.id)

        // Caught up on every posted chapter: never asked.
        wip.lastScrollFraction = 1
        wip.legacyReaderProgress = nil
        let caughtUp = ReadingLibraryInsights.make(
            works: [wip], facts: [], periodInterval: period,
            calendar: calendar, now: day(31)
        )
        #expect(caughtUp.stillReadingCandidate == nil)

        // Single-chapter work (1/1) at 40% untouched for 30 days: eligible.
        let oneshot = SavedWork(title: "Oneshot", author: "A")
        oneshot.isComplete = true
        oneshot.chapters = "1/1"
        oneshot.lastSpineIndex = 0
        oneshot.lastScrollFraction = 0.40
        oneshot.lastReadDate = day(1)
        let oneshotResult = ReadingLibraryInsights.make(
            works: [oneshot], facts: [], periodInterval: period,
            calendar: calendar, now: day(31)
        )
        #expect(oneshotResult.stillReadingCandidate?.id == oneshot.id)
        #expect(oneshotResult.stillReadingCandidate?.chapterProgress == "Chapter 1 of 1 · 40%")

        // Local EPUB with no fetched AO3 `chapters` string at 50%: eligible and no bogus "Chapter 1 of 1".
        let local = SavedWork(title: "Local EPUB", author: "A")
        local.chapters = ""
        local.lastScrollFraction = 0.50
        local.lastReadDate = day(1)
        let localResult = ReadingLibraryInsights.make(
            works: [local], facts: [], periodInterval: period,
            calendar: calendar, now: day(31)
        )
        #expect(localResult.stillReadingCandidate?.id == local.id)
        #expect(localResult.stillReadingCandidate?.chapterProgress == "50%")
    }

    @Test func checkShownFiguresReproduce() {
        let (facts, _, _) = checkFixture()
        let insights = ReadingInsights.make(facts: facts, calendar: calendar)
        let hours = insights.readingSeconds / 3_600
        #expect(abs(insights.wordsPerHour - Double(insights.totalWordsRead) / hours) < 1e-9)
        let words = 212_600
        #expect(ReadingInsights.novelsWorth(words: words) == (Double(words) / 70_000 * 2).rounded() / 2)

        // Production 90-day path with >= 30 reading days: 30 days x 2,000 words = 2,000/day -> 60k/month.
        let unread = SavedWork(title: "U", author: "A")
        unread.wordCount = 120_000
        let thirtyDays = (1...30).map { (d: Int) -> ReadingSessionFacts in
            fact(on: d, minutes: 30, words: 2_000)
        }
        let library = ReadingLibraryInsights.make(
            works: [unread],
            facts: thirtyDays,
            allFacts: thirtyDays,
            periodInterval: DateInterval(start: day(1, hour: 0), end: day(31, hour: 0)),
            periodMonths: 1,
            calendar: calendar,
            now: day(30, hour: 20)
        )
        let dailyAverage = Double(thirtyDays.reduce(0) { $0 + $1.wordsRead }) / 30.0
        #expect(library.monthsToClear == max(1, Int((120_000.0 / (dailyAverage * 30.0)).rounded())))
        #expect(library.monthsToClear == 2)
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

    @Test func usualFicFandomChipUsesFandomMaskingKind() {
        let works = (0..<5).map { index -> SavedWork in
            let work = SavedWork(title: "W\(index)", author: "A")
            work.workFandoms = ["Persuasion"]
            work.workFreeforms = ["Slow Burn"]
            work.rating = "Teen And Up Audiences"
            work.isComplete = true
            return work
        }
        let facts = works.enumerated().map { index, work in
            fact(work: work.id, on: index + 1, minutes: 20, words: 2_000, fandom: "Persuasion")
        }
        let taste = ReadingTasteInsights.make(works: works, facts: facts)
        #expect(taste.usualChips.contains { $0.text == "Persuasion" && $0.kind == .fandom })
        #expect(!taste.usualChips.contains { $0.text == "Persuasion" && $0.kind == .metadata })
    }

    @Test func libraryAuthorsFilterOrphanAndAnonymousAtDisplayTimeAndUseLiveQueueOnlyWorks() {
        let queued = SavedWork(title: "Queued", author: "raw_pseud")
        queued.isQueuedForLater = true
        queued.verifiedAuthorIdentities = [
            AO3AuthorIdentity(route: AO3AuthorRoute(username: "live_writer")!),
            AO3AuthorIdentity(route: AO3AuthorRoute(username: "orphan_account")!)
        ]
        let deletedID = UUID()
        var queuedFact = fact(work: queued.id, on: 2, minutes: 20, words: 1_500, didFinish: true)
        queuedFact.authorAccounts = ["raw_pseud"]
        var deletedFact = fact(work: deletedID, on: 3, minutes: 20, words: 2_000, didFinish: true)
        deletedFact.authorAccounts = [
            "deleted_writer", "Anonymous", "anonymous", "orphan_account", "old_pseud (orphan_account)"
        ]
        let period = DateInterval(start: day(1, hour: 0), end: day(31, hour: 0))
        let library = ReadingLibraryInsights.make(
            works: [],
            readingWorks: [queued],
            facts: [queuedFact, deletedFact],
            allFacts: [queuedFact, deletedFact],
            periodInterval: period,
            calendar: calendar
        )
        #expect(library.authors.map(\.name) == ["deleted_writer", "live_writer"])
        #expect(library.authors.first { $0.name == "live_writer" }?.words == 1_500)
        #expect(library.authors.first { $0.name == "deleted_writer" }?.words == 2_000)
    }

    @Test func readingDayPeriodFilterUsesFourAmSittingZoneBoundary() {
        let sep = DateInterval(start: instant(month: 9, 1, 0), end: instant(month: 10, 1, 0))
        let oct = DateInterval(start: instant(month: 10, 1, 0), end: instant(month: 11, 1, 0))
        let nov = DateInterval(start: instant(month: 11, 1, 0), end: instant(month: 12, 1, 0))

        let octEarlyMorning = sitting(at: instant(month: 10, 1, 1, 30), words: 1_000, tzHours: 0)
        #expect(ReadingInsights.isInPeriod(octEarlyMorning, period: sep, calendar: calendar))
        #expect(!ReadingInsights.isInPeriod(octEarlyMorning, period: oct, calendar: calendar))

        let novEarlyMorning = sitting(at: instant(month: 11, 1, 1, 30), words: 1_000, tzHours: 0)
        #expect(ReadingInsights.isInPeriod(novEarlyMorning, period: oct, calendar: calendar))
        #expect(!ReadingInsights.isInPeriod(novEarlyMorning, period: nov, calendar: calendar))

        let novFourAm = sitting(at: instant(month: 11, 1, 4, 0), words: 1_000, tzHours: 0)
        #expect(!ReadingInsights.isInPeriod(novFourAm, period: oct, calendar: calendar))
        #expect(ReadingInsights.isInPeriod(novFourAm, period: nov, calendar: calendar))

        // Oct 1 08:00 +09:00 is Sep 30 23:00 UTC; in its sitting zone it belongs to October.
        let tokyoMorning = sitting(at: instant(month: 10, 1, 8, 0, offsetHours: 9), words: 1_000, tzHours: 9)
        #expect(!ReadingInsights.isInPeriod(tokyoMorning, period: sep, calendar: calendar))
        #expect(ReadingInsights.isInPeriod(tokyoMorning, period: oct, calendar: calendar))
    }

    @Test func tagFiguresUseFreeformTagsOnlyAndStopTagsIncludeArchiveWarnings() {
        let works = (0..<10).map { index -> SavedWork in
            let work = SavedWork(title: "W\(index)", author: "A")
            work.lastReadDate = day(1)
            work.workFandoms = ["Persuasion"]
            work.workRelationships = ["Anne Elliot/Frederick Wentworth"]
            work.workCharacters = ["Anne Elliot"]
            work.workFreeforms = index < 5 ? ["Slow Burn", "Pining"] : []
            work.workTags = work.workFandoms + work.workRelationships + work.workCharacters + work.workFreeforms
            if index < 5 {
                work.workWarnings = ["Major Character Death"]
            }
            if index < 4 {
                work.readingStatusRaw = "stopped"
            }
            return work
        }
        let facts = works.enumerated().map { index, work in
            fact(work: work.id, on: index + 1, minutes: 20, words: 2_000, fandom: "Persuasion")
        }
        let taste = ReadingTasteInsights.make(works: works, facts: facts)
        #expect(Set(taste.tags.map(\.name)) == ["Slow Burn", "Pining"])
        #expect(taste.oftenTogether.contains {
            ($0.tagA == "Pining" && $0.tagB == "Slow Burn") || ($0.tagA == "Slow Burn" && $0.tagB == "Pining")
        })
        #expect(!taste.oftenTogether.contains { $0.tagA == "Persuasion" || $0.tagB == "Persuasion" })

        let habits = ReadingHabitsInsights.make(works: works, facts: facts, allFacts: facts, calendar: calendar)
        #expect(habits.commonStopTags.contains { $0.name == "Major Character Death" && $0.count == 4 })
        #expect(!habits.commonStopTags.contains { $0.name == "Persuasion" || $0.name == "Anne Elliot" })
    }

    @Test func tasteRankTogglePromotesHighCountFandomKeepsRemainderLastAndFormatsSmallWords() {
        var works: [SavedWork] = []
        var facts: [ReadingSessionFacts] = []
        // Four long fandoms: 1 work x 50,000 words each.
        for (idx, name) in ["Alpha", "Beta", "Gamma", "Delta"].enumerated() {
            let w = SavedWork(title: "Long \(name)", author: "A")
            w.workFandoms = [name]
            w.wordCount = 50_000
            works.append(w)
            facts.append(fact(work: w.id, on: idx + 1, minutes: 60, words: 50_000, fandom: name))
        }
        // Fifth fandom: 10 short works x 800 words each (8,000 total -> folded into remainder By Words, #1 By Works).
        for i in 0..<10 {
            let w = SavedWork(title: "Short \(i)", author: "A")
            w.workFandoms = ["Epsilon"]
            w.wordCount = 800
            works.append(w)
            facts.append(fact(work: w.id, on: 5 + i, minutes: 10, words: 800, fandom: "Epsilon"))
        }
        let taste = ReadingTasteInsights.make(works: works, facts: facts)
        let byWords = taste.ranked(byWorks: false)
        #expect(byWords.fandoms.last?.isRemainder == true)
        #expect(!byWords.fandoms.contains { $0.name == "Epsilon" })

        let byWorks = taste.ranked(byWorks: true)
        #expect(byWorks.fandoms.first?.name == "Epsilon")
        #expect(byWorks.fandoms.first?.worksCount == 10)
        #expect(byWorks.fandoms.last?.isRemainder == true)
        #expect(byWorks.usualTopFandom == "Epsilon")

        #expect(ReadingInsights.compactWordsLabel(850) == "850")
        #expect(ReadingInsights.compactWordsLabel(12_400) == "12.4k")
        #expect(ReadingInsights.compactWordsLabel(1_250_000) == "1.2M" || ReadingInsights.compactWordsLabel(1_250_000) == "1.3M")
    }

    @Test func fandomTimelineRanksYearTopFourByWordsAndShadesByMonthShare() {
        // Jan: FandomA 14k (70% -> tier 3), FandomB 5.5k (27.5% -> tier 2), Tiny 500 (2.5% -> tier 1).
        // Oct: Only OctFandom 10k. Viewing Oct must STILL keep FandomA in the year's top 4.
        let janA = sitting(at: instant(month: 1, 5, 12), minutes: 60, words: 14_000)
        var fJanA = janA; fJanA.fandom = "FandomA"
        var fJanB = sitting(at: instant(month: 1, 6, 12), minutes: 30, words: 5_500); fJanB.fandom = "FandomB"
        var fJanTiny = sitting(at: instant(month: 1, 7, 12), minutes: 5, words: 500); fJanTiny.fandom = "Tiny"
        var fOct = sitting(at: instant(month: 10, 2, 12), minutes: 40, words: 10_000); fOct.fandom = "OctFandom"

        let octPeriod = DateInterval(start: instant(month: 10, 1, 0), end: instant(month: 11, 1, 0))
        let habits = ReadingHabitsInsights.make(
            works: [],
            facts: [fOct],
            allFacts: [fJanA, fJanB, fJanTiny, fOct],
            periodInterval: octPeriod,
            calendar: calendar,
            now: instant(month: 10, 15, 12)
        )
        #expect(habits.fandomTimelineYear == 2026)
        #expect(habits.fandomTimeline.first?.name == "FandomA")
        #expect(habits.fandomTimeline.first { $0.name == "FandomA" }?.monthlyActivity[0] == 3)
        #expect(habits.fandomTimeline.first { $0.name == "FandomB" }?.monthlyActivity[0] == 2)
        // Tiny's 500 words is its own peak month, yet only 2.5% of Jan's 20k -> tier 1 (NOT tier 3).
        #expect(habits.fandomTimeline.first { $0.name == "Tiny" }?.monthlyActivity[0] == 1)
    }

    @Test func unreadNinetyDayPaceAnchorsOnEarliestHistoryAfterReadingBreak() {
        let unread = SavedWork(title: "Backlog", author: "A")
        unread.wordCount = 300_000
        let now = instant(month: 10, 31, 20)
        // History started > 90 days ago (Jan 10), then a long break, then 15 days x 10k = 150k in Oct.
        let old = sitting(at: instant(month: 1, 10, 12), minutes: 30, words: 5_000)
        let recent = (17...31).map { (d: Int) -> ReadingSessionFacts in
            sitting(at: instant(month: 10, d, 12), minutes: 30, words: 10_000)
        }
        let library = ReadingLibraryInsights.make(
            works: [unread],
            facts: recent,
            allFacts: [old] + recent,
            periodInterval: DateInterval(start: instant(month: 10, 1, 0), end: instant(month: 11, 1, 0)),
            calendar: calendar,
            now: now
        )
        // Elapsed must be 90 (not 15): 150k / 90 = 1,666.7/day = 50k/month -> 6 months (range 4...8).
        #expect(library.monthsToClear == nil)
        #expect(library.monthsToClearRange == 4...8)
    }

    @Test func foundEarlyPicksHighestGrowthAndReportsRecordedShareAndSince() {
        let flat = SavedWork(title: "No Growth", author: "A")
        flat.isFinished = true
        flat.statsSavedAt = day(2)
        flat.kudosAtSave = 490
        flat.kudos = 490

        let riser = SavedWork(title: "Big Riser", author: "A")
        riser.isFinished = true
        riser.statsSavedAt = day(1)
        riser.kudosAtSave = 50
        riser.kudos = 450

        let popular = SavedWork(title: "Already Popular", author: "A")
        popular.isFinished = true
        popular.statsSavedAt = day(3)
        popular.kudosAtSave = 600
        popular.kudos = 1_800

        let library = ReadingLibraryInsights.make(
            works: [flat, riser, popular],
            facts: [],
            periodInterval: DateInterval(start: day(1), end: day(10)),
            calendar: calendar
        )
        #expect(library.foundEarlyRecordedFinishedCount == 3)
        #expect(library.foundEarlyCount == 2)
        #expect(library.foundEarlyShare == 2.0 / 3.0)
        #expect(library.foundEarlySince == day(1))
        #expect(library.foundEarlyExampleItem?.workID == riser.id)
        #expect(library.foundEarlyExampleItem?.title == "Big Riser")
        #expect(library.foundEarlyExample?.contains("Big Riser · 50 then, 450 now") == true)
    }

    @Test func arrivalHidesWhenNoRecordedWorksFinishedAndOmitsZeroFinishedSources() {
        let unfinishedSearch = (0..<6).map { (i: Int) -> SavedWork in
            let w = SavedWork(title: "S\(i)", author: "A")
            w.importSourceRaw = WorkImportSource.search.rawValue
            w.importSourceSince = day(1)
            w.isFinished = false
            return w
        }
        let noneFinished = ReadingLibraryInsights.make(
            works: unfinishedSearch,
            facts: [],
            periodInterval: DateInterval(start: day(1), end: day(5)),
            calendar: calendar
        )
        #expect(noneFinished.arrivalRows.isEmpty)
        #expect(noneFinished.arrivalSince == nil)

        let finishedSeries = SavedWork(title: "Done", author: "A")
        finishedSeries.importSourceRaw = WorkImportSource.series.rawValue
        finishedSeries.importSourceSince = day(2)
        finishedSeries.isFinished = true
        let mixed = ReadingLibraryInsights.make(
            works: unfinishedSearch + [finishedSeries],
            facts: [],
            periodInterval: DateInterval(start: day(1), end: day(5)),
            calendar: calendar
        )
        // Search has 0 finished works and must not render a 0% share row.
        #expect(mixed.arrivalRows.count == 1)
        #expect(mixed.arrivalRows.first?.label == "Other")
        #expect(mixed.arrivalRows.first?.finished == 1)
    }

    @Test func seriesRequiresFinishedLastPartChecksDeletedPartsAndKudosRequiresLiveAO3() {
        let part1 = SavedWork(title: "Part 1", author: "A")
        part1.ao3WorkID = 201
        part1.ao3SeriesID = 99
        part1.seriesPosition = 1
        part1.lastReadDate = day(1)
        part1.isFinished = true

        let openedLast = SavedWork(title: "Part 2", author: "A")
        openedLast.ao3WorkID = 202
        openedLast.ao3SeriesID = 99
        openedLast.seriesPosition = 2
        openedLast.lastReadDate = day(2)
        openedLast.isFinished = false

        let snapshot = SavedSeriesSnapshot(
            ao3SeriesID: 99, title: "Duology", partCount: 2,
            isComplete: true, wordCount: 80_000, partWorkIDs: [201, 202]
        )

        // Part 2 is only opened (not finished): NOT read to the last part, and NOT waiting either.
        let openedResult = ReadingLibraryInsights.make(
            works: [part1, openedLast], facts: [], seriesSnapshots: [snapshot],
            periodInterval: DateInterval(start: day(1), end: day(5)), calendar: calendar
        )
        #expect(openedResult.seriesReadToLastCount == 0)
        #expect(openedResult.longestFinishedSeries == nil)
        #expect(openedResult.seriesNextWaitingCount == 0)

        // Deleted Part 2 recorded in allFacts: must NOT falsely report Next Part Waiting, and DOES count readToLast.
        var deletedPart2Fact = fact(work: UUID(), on: 2, minutes: 30, words: 40_000, didFinish: true)
        deletedPart2Fact.ao3WorkID = 202
        deletedPart2Fact.ao3SeriesID = 99
        deletedPart2Fact.seriesPosition = 2
        let deletedPartResult = ReadingLibraryInsights.make(
            works: [part1], facts: [deletedPart2Fact], allFacts: [deletedPart2Fact],
            seriesSnapshots: [snapshot], periodInterval: DateInterval(start: day(1), end: day(5)), calendar: calendar
        )
        #expect(deletedPartResult.seriesReadToLastCount == 1)
        #expect(deletedPartResult.seriesNextWaitingCount == 0)
        #expect(deletedPartResult.longestFinishedSeries?.title == "Duology")

        // Non-AO3 imported EPUB and gone AO3 work must be excluded from Kudos left and Favourites Without Kudos.
        let liveAO3 = SavedWork(title: "Live AO3", author: "A")
        liveAO3.ao3WorkID = 301
        liveAO3.isFinished = true
        liveAO3.hasGivenKudos = true

        let localEPUB = SavedWork(title: "Local", author: "A")
        localEPUB.isFinished = true
        localEPUB.isFavorite = true
        localEPUB.hasGivenKudos = false

        let goneAO3 = SavedWork(title: "Gone AO3", author: "A")
        goneAO3.ao3WorkID = 302
        goneAO3.ao3Unavailable = true
        goneAO3.isFinished = true
        goneAO3.isFavorite = true
        goneAO3.hasGivenKudos = false

        let kudosResult = ReadingLibraryInsights.make(
            works: [liveAO3, localEPUB, goneAO3], facts: [],
            periodInterval: DateInterval(start: day(1), end: day(5)), calendar: calendar
        )
        #expect(kudosResult.kudosLeftPercent == 100)
        #expect(kudosResult.favoriteWithoutKudosCount == 0)
    }

    @Test func readingAndListeningComputesWeightedPlaybackRateAndWorksCount() {
        let w1 = UUID()
        let w2 = UUID()
        var l1 = fact(work: w1, on: 1, minutes: 30, words: 3_000)
        l1.mode = .listen
        l1.playbackRate = 1.0
        var l2 = fact(work: w1, on: 2, minutes: 60, words: 6_000)
        l2.mode = .listen
        l2.playbackRate = 1.5
        var l3 = fact(work: w2, on: 3, minutes: 30, words: 4_000)
        l3.mode = .listen
        l3.playbackRate = 2.0
        let read = fact(work: w1, on: 4, minutes: 60, words: 10_000)

        let overview = ReadingInsights.make(facts: [l1, l2, l3, read], calendar: calendar)
        #expect(overview.listeningWorksCount == 2)
        // Weighted average: (30*1.0 + 60*1.5 + 30*2.0) / 120 = 1.5
        #expect(overview.listeningPlaybackRate == 1.5)
        #expect(overview.listeningSeconds == 120 * 60)
        #expect(overview.silentReadingSeconds == 60 * 60)
    }

    @Test func hourlyDurationBucketsCapsCorruptedFarFutureEndDate() {
        var corrupted = fact(on: 1, hour: 22, minutes: 30)
        corrupted.tzOffsetSeconds = 0
        corrupted.endedAt = corrupted.startedAt.addingTimeInterval(60 * 86_400)
        let hours = ReadingInsights.hourlyDurationBuckets(from: [corrupted], calendar: calendar)
        #expect(hours[22].seconds == 1_800)
        #expect(hours[2].seconds == 0)
        #expect(hours.reduce(0) { $0 + $1.seconds } == 1_800)
    }

    @Test func whenPostedUsesUtcAndShipConcentrationStaysWithinFandom() {
        let works = (0..<8).map { (i: Int) -> SavedWork in
            let w = SavedWork(title: "W\(i)", author: "A")
            w.workFandoms = [i < 4 ? "Fandom One" : "Fandom Two"]
            w.workRelationships = ["OFC/OMC"]
            w.datePublished = "2020-01-01"
            return w
        }
        let facts = works.enumerated().map { (i: Int, w: SavedWork) -> ReadingSessionFacts in
            fact(work: w.id, on: i + 1, minutes: 30, words: 10_000, fandom: w.workFandoms[0])
        }
        let taste = ReadingTasteInsights.make(works: works, facts: facts)
        #expect(taste.yearCounts.map(\.year) == [2020])
        #expect(taste.medianYear == 2020)
        #expect(taste.shipConcentrations.count == 2)
        #expect(taste.shipConcentrations.allSatisfy { $0.percentage == 100 })
    }
}
