import Foundation
import Testing
@testable import Kudos

/// Words per Day draws every elapsed day of a short period, so one day of reading is one
/// slot among empty ones, not a bar the width of the chart.
struct WordsPerDayChartTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    @Test func aMonthStopsAtTodayAndAYearDrawsReadingDaysOnly() throws {
        let november = DateInterval(start: date(1), end: date(1, month: 12))
        let days = try #require(ReadingInsights.chartDays(for: november, now: date(3).addingTimeInterval(3600), calendar: calendar))
        #expect(days.start == date(1))
        #expect(days.end == date(4))

        let year = DateInterval(start: date(1, month: 1), end: date(1, month: 12))
        #expect(ReadingInsights.chartDays(for: year, now: date(3), calendar: calendar) == nil)
    }

    @Test func emptyDaysAreSlotsButNeverTheBiggestDay() {
        let range = DateInterval(start: date(1), end: date(4))
        let insights = ReadingInsights.make(facts: [], dayRange: range, calendar: calendar)
        #expect(insights.dailyWords.map(\.dayNumber) == [1, 2, 3])
        #expect(insights.dailyWords.allSatisfy { $0.words == 0 })
        #expect(insights.biggestDay == nil)
    }
}
