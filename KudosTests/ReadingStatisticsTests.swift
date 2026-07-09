import Foundation
import Testing
@testable import Kudos

@MainActor
struct ReadingStatisticsTests {
    @Test func separatesStartedFinishedAndInProgressWorks() {
        let unread = work("Unread")
        let reading = work("Reading")
        reading.lastScrollFraction = 0.25
        let finished = work("Finished")
        finished.isFinished = true

        let statistics = ReadingStatistics(works: [unread, reading, finished])

        #expect(statistics.totalWorks == 3)
        #expect(statistics.startedWorks == 2)
        #expect(statistics.finishedWorks == 1)
        #expect(statistics.inProgressWorks == 1)
        #expect(statistics.completionRate == 0.5)
    }

    @Test func wordsReadCountsOnlyFinishedWorksWithKnownTotals() {
        let finished = work("Known")
        finished.isFinished = true
        finished.wordCount = 12_500

        let reading = work("Still reading")
        reading.lastReadDate = Date()
        reading.wordCount = 90_000

        let unknown = work("Unknown")
        unknown.isFinished = true

        let statistics = ReadingStatistics(works: [finished, reading, unknown])

        #expect(statistics.wordsRead == 12_500)
    }

    @Test func recentActivityUsesDistinctWorksAndCalendarDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 20, hour: 12
        )))

        let today = work("Today")
        today.lastReadDate = now
        let sixDaysAgo = work("Six days ago")
        sixDaysAgo.lastReadDate = calendar.date(byAdding: .day, value: -6, to: now)
        let tenDaysAgo = work("Ten days ago")
        tenDaysAgo.lastReadDate = calendar.date(byAdding: .day, value: -10, to: now)
        let old = work("Old")
        old.lastReadDate = calendar.date(byAdding: .day, value: -31, to: now)

        let statistics = ReadingStatistics(
            works: [today, sixDaysAgo, tenDaysAgo, old],
            now: now,
            calendar: calendar
        )

        #expect(statistics.openedLast7Days == 2)
        #expect(statistics.openedLast30Days == 3)
        #expect(statistics.latestReadDate == now)
    }

    @Test func readiumOnlyWorkCountsAsStarted() {
        // Regression: a private re-listing of the "started" fields here once missed
        // the Readium locator, undercounting works read only in the iOS reader.
        let readiumOnly = work("Readium only")
        readiumOnly.readiumLocator =
            #"{"href":"c1.xhtml","type":"application/xhtml+xml","locations":{"totalProgression":0.3}}"#

        let statistics = ReadingStatistics(works: [readiumOnly])

        #expect(statistics.startedWorks == 1)
        #expect(statistics.inProgressWorks == 1)
    }

    @Test func topFandomsCountEachFandomOncePerStartedWork() {
        let first = work("First")
        first.lastReadDate = Date()
        first.workFandoms = ["Naruto", "Naruto", "Bleach"]

        let second = work("Second")
        second.isFinished = true
        second.workFandoms = ["Naruto"]

        let unread = work("Unread")
        unread.workFandoms = ["Bleach"]

        let statistics = ReadingStatistics(works: [first, second, unread])

        #expect(statistics.topFandoms == [
            .init(name: "Naruto", count: 2),
            .init(name: "Bleach", count: 1),
        ])
    }

    private func work(_ title: String) -> SavedWork {
        SavedWork(title: title, author: "Author")
    }
}
