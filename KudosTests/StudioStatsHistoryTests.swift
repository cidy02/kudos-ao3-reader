import Foundation
import Testing
@testable import Kudos

/// The Stats history: what is saved, the weekly buckets, the changes, the period filter.
/// Plain values and a temp folder only: no network, no AO3, no view.
@MainActor
struct StudioStatsHistoryTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2 // Mondays: Nov 2, 9, 16, 23 and 30, 2026
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        let parts = DateComponents(year: 2026, month: month, day: day, hour: hour)
        return Self.calendar.date(from: parts) ?? .distantPast
    }

    private func snapshot(_ month: Int, _ day: Int, kudos: Int, year: Int? = nil, hour: Int = 12) -> StudioStatsSnapshot {
        StudioStatsSnapshot(
            date: date(month, day, hour: hour), year: year,
            totals: [StudioStatsMetric.kudos.rawValue: kudos], works: []
        )
    }

    private func work(_ id: Int, kudos: Int, hits: Int = 0) -> AO3UserStats.Work {
        AO3UserStats.Work(
            id: id, title: "Work \(id)", fandoms: ["Fandom"], wordCount: 1000, hits: hits,
            kudos: kudos, commentThreads: 2, bookmarks: 3, subscriptions: 4, sourceOrder: id
        )
    }

    private func page(kudos: Int, works: [AO3UserStats.Work]) -> AO3UserStats {
        AO3UserStats(
            wordCount: 5000, kudos: kudos, hits: 900, bookmarks: 30, commentThreads: 20, subscriptions: 10,
            fandomGroups: [AO3UserStats.FandomGroup(name: "Fandom", works: works)]
        )
    }

    private func withStore(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    // MARK: The store

    @Test func savesTotalsAndEachWorkAndReadsThemBack() throws {
        try withStore { folder in
            let store = StudioStatsHistoryStore(account: "saltwindow", directory: folder)
            store.record(
                page(kudos: 100, works: [work(1, kudos: 60, hits: 500), work(2, kudos: 40)]),
                year: nil, at: date(11, 26), calendar: Self.calendar
            )
            let loaded = StudioStatsHistoryStore(account: "saltwindow", directory: folder).load()
            #expect(loaded.count == 1)
            #expect(loaded.first?.total(.kudos) == 100)
            #expect(loaded.first?.total(.words) == 5000)
            #expect(loaded.first?.works.count == 2)
            #expect(loaded.first?.work(id: 1)?.figure(.hits) == 500)
            #expect(loaded.first?.work(id: 2)?.figure(.kudos) == 40)
        }
    }

    @Test func oneSnapshotADayAndTheLaterLookWins() throws {
        try withStore { folder in
            let store = StudioStatsHistoryStore(account: "a", directory: folder)
            store.record(page(kudos: 10, works: []), year: nil, at: date(11, 26, hour: 8), calendar: Self.calendar)
            store.record(page(kudos: 12, works: []), year: nil, at: date(11, 26, hour: 20), calendar: Self.calendar)
            let sameDay = store.load()
            #expect(sameDay.count == 1)
            #expect(sameDay.first?.total(.kudos) == 12)

            store.record(page(kudos: 15, works: []), year: nil, at: date(11, 27), calendar: Self.calendar)
            // Another year filter on the same day is its own history.
            store.record(page(kudos: 3, works: []), year: 2025, at: date(11, 27), calendar: Self.calendar)
            #expect(store.load().count == 3)
        }
    }

    @Test func keepsAYearAndNoMore() {
        let now = date(11, 26)
        func ago(_ days: Int) -> Date { Self.calendar.date(byAdding: .day, value: -days, to: now) ?? now }
        let old = [400, 366, 365, 10].map {
            StudioStatsSnapshot(date: ago($0), year: nil, totals: [:], works: [])
        }
        let today = StudioStatsSnapshot(date: now, year: nil, totals: [:], works: [])
        let kept = StudioStatsHistoryStore.merging(old, adding: today, calendar: Self.calendar)
        #expect(kept.map(\.date) == [ago(365), ago(10), now])
    }

    @Test func anUnreadableFileIsSetAsideNotOverwritten() throws {
        try withStore { folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("a.json")
            try Data("not json".utf8).write(to: file)
            let store = StudioStatsHistoryStore(account: "a", directory: folder)
            let result = store.record(page(kudos: 1, works: []), year: nil, at: date(11, 26), calendar: Self.calendar)
            #expect(result.count == 1)
            let aside = try String(contentsOf: file.appendingPathExtension("unreadable"), encoding: .utf8)
            #expect(aside == "not json")
        }
    }

    // MARK: Weeks

    @Test func weeklyBucketsTakeEachWeeksLastLookAndNameTheBestWeek() {
        let snaps = [
            snapshot(11, 3, kudos: 100), snapshot(11, 5, kudos: 110), // week of Nov 2 ends at 110
            snapshot(11, 10, kudos: 130), // +20
            snapshot(11, 17, kudos: 135), // +5
            snapshot(11, 24, kudos: 200) // +65
        ]
        let weeks = StudioStatsHistory.weeks(snaps, metric: .kudos, calendar: Self.calendar)
        #expect(weeks.map(\.gain) == [20, 5, 65])
        #expect(weeks.map(\.start) == [date(11, 9, hour: 0), date(11, 16, hour: 0), date(11, 23, hour: 0)])
        let anyEstimate = weeks.contains { $0.isEstimate }
        #expect(!anyEstimate)
        let best = StudioStatsHistory.best(weeks)
        #expect(best?.gain == 65)
        #expect(best?.start == date(11, 23, hour: 0))
    }

    @Test func aWeekNobodyLookedIsSpreadAndMarkedAnEstimate() {
        let snaps = [snapshot(11, 3, kudos: 100), snapshot(11, 24, kudos: 131)]
        let weeks = StudioStatsHistory.weeks(snaps, metric: .kudos, calendar: Self.calendar)
        #expect(weeks.map(\.gain) == [10, 10, 11])
        let allEstimates = weeks.allSatisfy { $0.isEstimate }
        #expect(allEstimates)
        #expect(weeks.map(\.start) == [date(11, 9, hour: 0), date(11, 16, hour: 0), date(11, 23, hour: 0)])
    }

    @Test func aFallDrawsAsZeroAndNoGrowthHasNoBestWeek() {
        let snaps = [snapshot(11, 3, kudos: 100), snapshot(11, 10, kudos: 90)]
        let weeks = StudioStatsHistory.weeks(snaps, metric: .kudos, calendar: Self.calendar)
        #expect(weeks.map(\.gain) == [0])
        #expect(StudioStatsHistory.best(weeks) == nil)
    }

    // MARK: Changes

    @Test func changeIsMeasuredAgainstTheLookNearestAWeekAgo() {
        let snaps = [snapshot(11, 5, kudos: 100), snapshot(11, 12, kudos: 120), snapshot(11, 19, kudos: 130)]
        let now = date(11, 26)
        let baseline = StudioStatsHistory.baseline(snaps, now: now, calendar: Self.calendar)
        #expect(baseline?.total(.kudos) == 130)
        #expect(StudioStatsHistory.change(150, since: baseline?.total(.kudos)) == 20)
        #expect(StudioStatsHistory.change(150, since: nil) == nil)
    }

    @Test func aShortHistoryUsesItsEarliestEarlierDayAndTodayIsNeverTheBaseline() {
        let now = date(11, 26)
        let threeDaysAgo = [snapshot(11, 23, kudos: 90)]
        #expect(StudioStatsHistory.baseline(threeDaysAgo, now: now, calendar: Self.calendar)?.total(.kudos) == 90)
        let onlyToday = [snapshot(11, 26, kudos: 95, hour: 8)]
        #expect(StudioStatsHistory.baseline(onlyToday, now: now, calendar: Self.calendar) == nil)
        #expect(StudioStatsHistory.baseline([], now: now, calendar: Self.calendar) == nil)
    }

    @Test func aWorkNewSinceTheBaselineHasNoChange() {
        let before = StudioStatsSnapshot(
            stats: page(kudos: 100, works: [work(1, kudos: 60)]), year: nil, at: date(11, 19)
        )
        #expect(StudioStatsHistory.change(70, since: before.work(id: 1)?.figure(.kudos)) == 10)
        #expect(StudioStatsHistory.change(5, since: before.work(id: 2)?.figure(.kudos)) == nil)
    }

    @Test func sparklineScalesBetweenLowAndHighAndNeedsTwoWeeks() {
        let rising = [snapshot(11, 3, kudos: 100), snapshot(11, 10, kudos: 110), snapshot(11, 17, kudos: 130)]
        let bars = StudioStatsHistory.sparkline(rising, metric: .kudos, calendar: Self.calendar)
        #expect(bars.count == 3)
        #expect(bars[0] == 0)
        #expect(abs(bars[1] - 1.0 / 3.0) < 1e-9)
        #expect(bars[2] == 1)
        #expect(StudioStatsHistory.sparkline([rising[0]], metric: .kudos, calendar: Self.calendar).isEmpty)
        let flat = [snapshot(11, 3, kudos: 100), snapshot(11, 10, kudos: 100)]
        #expect(StudioStatsHistory.sparkline(flat, metric: .kudos, calendar: Self.calendar) == [0.5, 0.5])
    }

    // MARK: Period filter

    @Test func eachYearFilterReadsItsOwnHistory() {
        let all = [
            snapshot(11, 3, kudos: 100), snapshot(11, 10, kudos: 150),
            snapshot(11, 3, kudos: 10, year: 2025), snapshot(11, 10, kudos: 14, year: 2025),
            snapshot(11, 10, kudos: 40, year: 2026)
        ]
        #expect(StudioStatsHistory.snapshots(all, year: nil).count == 2)
        #expect(StudioStatsHistory.snapshots(all, year: 2025).count == 2)
        #expect(StudioStatsHistory.snapshots(all, year: 2026).count == 1)
        #expect(StudioStatsHistory.snapshots(all, year: 2024).isEmpty)
        let allYears = StudioStatsHistory.weeks(StudioStatsHistory.snapshots(all, year: nil), metric: .kudos, calendar: Self.calendar)
        let year2025 = StudioStatsHistory.weeks(StudioStatsHistory.snapshots(all, year: 2025), metric: .kudos, calendar: Self.calendar)
        #expect(allYears.map(\.gain) == [50])
        #expect(year2025.map(\.gain) == [4])
    }

    // MARK: Empty history

    @Test func beforeAWeekOfHistoryTheChartSaysWhenItBegins() {
        let none = StudioStatsHistory.emptyChartMessage([], calendar: Self.calendar)
        #expect(none.hasPrefix("Charts begin once"))
        // First look on a Thursday: the first bar can exist the week of Monday Nov 30.
        let first = [snapshot(11, 26, kudos: 100), snapshot(11, 27, kudos: 104)]
        #expect(StudioStatsHistory.weeks(first, metric: .kudos, calendar: Self.calendar).isEmpty)
        #expect(StudioStatsHistory.chartsBegin(first, calendar: Self.calendar) == date(11, 30, hour: 0))
        let message = StudioStatsHistory.emptyChartMessage(first, calendar: Self.calendar)
        #expect(message.hasPrefix("Charts begin the week of"))
        #expect(message.contains("30"))
    }
}
