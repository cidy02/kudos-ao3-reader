import Foundation
import Testing
@testable import Kudos

/// Reading History's timeline (T-462): which period, day and bar a sitting lands
/// in, where a streak breaks, and which chapters a sitting is drawn reading.
///
/// No `ModelContainer`: the rules take `ReadingSessionFacts`, as Reading
/// Insights' do. August 2026 begins on a Saturday, so Sunday 2 and Monday 3 are
/// the two places a week can start.
struct ReadingHistoryTimelineTests {
    private typealias Span = ReadingHistoryTimeline.ChapterSpan

    private func calendar(firstWeekday: Int = 2, zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(
        _ day: Int, _ hour: Int = 12, minute: Int = 0, month: Int = 8, year: Int = 2026,
        in calendar: Calendar? = nil
    ) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return (calendar ?? self.calendar()).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func sitting(
        work: UUID = UUID(),
        at start: Date,
        minutes: Double = 30,
        ending: Double = 0.5,
        chapters: Int = 4,
        didFinish: Bool = false
    ) -> ReadingSessionFacts {
        ReadingSessionFacts(
            workID: work, startedAt: start, durationSeconds: minutes * 60, wordCount: 1_000,
            didFinish: didFinish, sessionID: UUID(), title: "A Work", endingProgress: ending,
            chapterCount: chapters
        )
    }

    // MARK: Empty

    @Test func anEmptyHistoryIsAnEmptyWeekNotAMissingOne() {
        let cal = calendar()
        let timeline = ReadingHistoryTimeline.make(
            scope: .week, containing: date(5), facts: [], now: date(5), calendar: cal
        )
        #expect(timeline.totalSeconds == 0)
        #expect(timeline.days.isEmpty)
        // Seven bars still draw, so the chart keeps the shape of a week.
        #expect(timeline.buckets.count == 7)
        #expect(timeline.streakDays == 0)
        #expect(timeline.peakBucket == nil)
        #expect(timeline.chartSummary(periodName: "This week", calendar: cal) == "This week: no reading")
    }

    // MARK: Days and midnight

    @Test func aSittingAcrossMidnightBelongsWholeToTheDayItStarted() {
        let cal = calendar()
        let late = sitting(at: date(4, 23, minute: 30), minutes: 70)
        let timeline = ReadingHistoryTimeline.make(
            scope: .week, containing: date(5), facts: [late], now: date(6), calendar: cal
        )
        #expect(timeline.days.map(\.start) == [date(4, 0)])
        #expect(timeline.days.first?.totalSeconds == 70 * 60.0)
        let tuesday = timeline.buckets.first { $0.start == date(4, 0) }
        let wednesday = timeline.buckets.first { $0.start == date(5, 0) }
        #expect(tuesday?.seconds == 70 * 60.0)
        #expect(wednesday?.seconds == 0)
        #expect(timeline.daysRead == 1)
    }

    @Test func daysAndTheirSittingsRunNewestFirst() {
        let cal = calendar()
        let facts = [
            sitting(at: date(3, 8)), sitting(at: date(4, 9)), sitting(at: date(4, 21)), sitting(at: date(3, 20))
        ]
        let timeline = ReadingHistoryTimeline.make(
            scope: .week, containing: date(5), facts: facts, now: date(5), calendar: cal
        )
        #expect(timeline.days.map(\.start) == [date(4, 0), date(3, 0)])
        #expect(timeline.days.first?.sittings.map(\.startedAt) == [date(4, 21), date(4, 9)])
    }

    // MARK: Streaks

    @Test func aStreakEndsAtTheFirstDayWithoutReading() {
        let cal = calendar()
        // 1, 2, 3, a gap on 4, then 5 and 6.
        let facts = [1, 2, 3, 5, 6].map { sitting(at: date($0)) }
        #expect(ReadingHistoryTimeline.streak(through: date(6), isToday: false, facts: facts, calendar: cal) == 2)
        #expect(ReadingHistoryTimeline.streak(through: date(3), isToday: false, facts: facts, calendar: cal) == 3)
        // A past day with no reading has no streak through it.
        #expect(ReadingHistoryTimeline.streak(through: date(4), isToday: false, facts: facts, calendar: cal) == 0)
    }

    @Test func todayWithoutReadingYetDoesNotBreakTheStreak() {
        let cal = calendar()
        let facts = [5, 6].map { sitting(at: date($0)) }
        #expect(ReadingHistoryTimeline.streak(through: date(7, 9), isToday: true, facts: facts, calendar: cal) == 2)
        // Yesterday missed too: that one is over, and it broke the run.
        #expect(ReadingHistoryTimeline.streak(through: date(8, 9), isToday: true, facts: facts, calendar: cal) == 0)
        let withToday = facts + [sitting(at: date(7, 8))]
        #expect(ReadingHistoryTimeline.streak(through: date(7, 9), isToday: true, facts: withToday, calendar: cal) == 3)
    }

    @Test func aWeeksStreakCountsBackPastTheWeeksFirstDay() {
        let cal = calendar()
        // Saturday 1 and Sunday 2 belong to the week before Monday 3.
        let facts = [1, 2, 3, 4].map { sitting(at: date($0)) }
        let timeline = ReadingHistoryTimeline.make(
            scope: .week, containing: date(4), facts: facts, now: date(4, 18), calendar: cal
        )
        #expect(timeline.streakDays == 4)
        #expect(timeline.daysRead == 2)
    }

    // MARK: Period boundaries

    @Test func theWeekStartsOnTheReadersFirstWeekday() {
        let sunday = sitting(at: date(2))
        let nextSunday = sitting(at: date(9))
        let mondayFirst = ReadingHistoryTimeline.make(
            scope: .week, containing: date(5), facts: [sunday, nextSunday], now: date(20), calendar: calendar()
        )
        #expect(mondayFirst.period.start == date(3, 0))
        #expect(mondayFirst.days.map(\.start) == [date(9, 0)])
        #expect(mondayFirst.buckets.first?.start == date(3, 0))

        let sundayCalendar = calendar(firstWeekday: 1)
        let sundayFirst = ReadingHistoryTimeline.make(
            scope: .week, containing: date(5), facts: [sunday, nextSunday], now: date(20), calendar: sundayCalendar
        )
        #expect(sundayFirst.period.start == date(2, 0))
        #expect(sundayFirst.days.map(\.start) == [date(2, 0)])
    }

    @Test func theMonthFollowsTheReadersTimeZone() {
        // 23:30 UTC on 31 August is already 1 September in Berlin.
        let late = sitting(at: date(31, 23, minute: 30))
        let utc = ReadingHistoryTimeline.make(
            scope: .month, containing: date(15), facts: [late], now: date(20, month: 9), calendar: calendar()
        )
        #expect(utc.totalSeconds == 30 * 60)
        #expect(utc.buckets.count == 31)

        let berlin = calendar(zone: "Europe/Berlin")
        let august = ReadingHistoryTimeline.make(
            scope: .month, containing: date(15), facts: [late], now: date(20, month: 9), calendar: berlin
        )
        #expect(august.totalSeconds == 0)
        let september = ReadingHistoryTimeline.make(
            scope: .month, containing: date(15, month: 9), facts: [late], now: date(20, month: 9), calendar: berlin
        )
        #expect(september.totalSeconds == 30 * 60)
        #expect(september.buckets.count == 30)
    }

    @Test func aYearIsTwelveMonthsAndEndsBeforeTheNextOneBegins() {
        let cal = calendar()
        let lastMinute = sitting(at: date(31, 23, minute: 59, month: 12))
        let newYear = sitting(at: date(1, 0, month: 1, year: 2027))
        let timeline = ReadingHistoryTimeline.make(
            scope: .year, containing: date(5), facts: [lastMinute, newYear], now: date(2, month: 2, year: 2027),
            calendar: cal
        )
        #expect(timeline.buckets.count == 12)
        #expect(timeline.buckets.last?.seconds == 30 * 60.0)
        #expect(timeline.totalSeconds == 30 * 60)
        #expect(!timeline.isCurrent)
    }

    @Test func daysStillToComeAreDrawnEmptyAndLeftOutOfTheAverage() {
        let cal = calendar()
        // Monday 3 and Tuesday 4 read; it is Wednesday 5.
        let facts = [sitting(at: date(3), minutes: 30), sitting(at: date(4), minutes: 60)]
        let timeline = ReadingHistoryTimeline.make(
            scope: .week, containing: date(5), facts: facts, now: date(5, 9), calendar: cal
        )
        #expect(timeline.buckets.filter(\.isFuture).count == 4)
        #expect(timeline.averageBucketSeconds == 30 * 60)
        #expect(timeline.daysElapsed == 3)
        #expect(
            timeline.chartSummary(periodName: "This week", calendar: cal)
                == "This week: 1 hour 30 minutes, most on Tuesday"
        )
    }

    // MARK: Chapters and badges

    @Test func chapterSpansMatchBoardTwo() {
        // "Chapters 3–4", finishing a four-chapter work begun halfway.
        let finishing = Span.make(total: 4, start: 0.5, end: 1, finished: true)
        #expect(finishing == Span(total: 4, first: 3, last: 4))
        // "Chapters 6–7 · 58% through": 5/12 must land on chapter 6, not 5.
        let middle = Span.make(total: 12, start: 5.0 / 12, end: 0.58, finished: false)
        #expect(middle == Span(total: 12, first: 6, last: 7))
        #expect(middle?.readBefore == 5)
        #expect(middle?.toCome == 5)
        #expect(Span.make(total: 1, start: 0, end: 1, finished: true)?.label == "One-shot")
        // A count the log never recorded draws no cells rather than invented ones.
        #expect(Span.make(total: 0, start: 0, end: 0.5, finished: false) == nil)
    }

    @Test func aSittingStartsWhereTheWorksLastSittingEnded() {
        let cal = calendar()
        let work = UUID()
        let facts = [
            sitting(work: work, at: date(3), ending: 0.25),
            sitting(work: work, at: date(4), ending: 0.75)
        ]
        let timeline = ReadingHistoryTimeline.make(
            scope: .week, containing: date(5), facts: facts, now: date(5), calendar: cal
        )
        let second = timeline.days.first?.sittings.first
        #expect(second?.chapters == Span(total: 4, first: 2, last: 3))
        #expect(second?.badge == nil)
        #expect(timeline.days.last?.sittings.first?.badge == .started)
        #expect(second?.detailLine == "Chapters 2–3 of 4 · 30 min · 75% through")
    }

    @Test func aRereadStartsAgainFromTheTopAndSaysWhichReadItIs() {
        let cal = calendar()
        let work = UUID()
        let facts = [
            sitting(work: work, at: date(3), ending: 1, didFinish: true),
            sitting(work: work, at: date(4), ending: 0.25)
        ]
        let timeline = ReadingHistoryTimeline.make(
            scope: .week, containing: date(5), facts: facts, now: date(5), calendar: cal
        )
        let reread = timeline.days.first?.sittings.first
        #expect(reread?.chapters?.first == 1)
        #expect(reread?.readThrough == 2)
        #expect(reread?.badge == .started)
        #expect(timeline.days.last?.sittings.first?.badge == .finished)
        // Works, not sittings: one work read twice is one work, finished once.
        #expect(timeline.workCount == 1)
        #expect(timeline.finishedCount == 1)
    }

    @Test func startingProgressIsTheRuleWordsReadUses() {
        let work = UUID()
        let facts = [
            sitting(work: work, at: date(3), ending: 0.4),
            sitting(work: work, at: date(4), ending: 0.3),
            sitting(work: work, at: date(5), ending: 1, didFinish: true),
            sitting(work: work, at: date(6), ending: 0.2)
        ]
        // Went back on the 4th, so the 5th starts from there; a finish resets to the top.
        #expect(ReadingInsights.startingProgress(of: facts) == [0, 0.4, 0.3, 0])
    }

    @Test func spokenDurationsReadAsWords() {
        #expect(ReadingHistoryTimeline.spokenDuration(0) == "under a minute")
        #expect(ReadingHistoryTimeline.spokenDuration(60) == "1 minute")
        #expect(ReadingHistoryTimeline.spokenDuration(3_600) == "1 hour")
        #expect(ReadingHistoryTimeline.spokenDuration(15_000) == "4 hours 10 minutes")
    }
}
