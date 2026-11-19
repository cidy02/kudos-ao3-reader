import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-519b: the weekly saved-series check is spread over the week, most viewed first, capped, and mail first.
@MainActor
struct SavedSeriesWeeklyCheckTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func makeContext() throws -> ModelContext {
        let schema = Schema([SavedSeries.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func seriesHTML(works: Int) -> String {
        """
        <h2 class="heading">S</h2><dl class="series meta group"><dd class="stats"><dl class="stats">
        <dd class="words">100</dd><dd class="works">\(works)</dd><dt>Complete:</dt><dd>No</dd></dl></dd></dl>
        """
    }

    private func update(workID: UInt64, seriesID: Int) -> SubscriptionUpdate {
        SubscriptionUpdate(
            uid: 1, workID: workID, chapterID: nil, chapterNumber: nil, isNewWork: true, isContested: false,
            isAnchoredToWork: true, workTitle: "W", author: "A", at: Date(), source: .series("Series #\(seriesID)")
        )
    }

    @Test func slotsSpreadAcrossTheWeek() {
        var counts = [Int](repeating: 0, count: 168)
        for id in 1...1_000 { counts[SavedSeriesWeeklyCheck.homeSlot(seriesID: id)] += 1 }
        #expect(counts.max()! <= 3 * (1_000 / 168 + 1))
        #expect(SavedSeriesWeeklyCheck.homeSlot(seriesID: 42) == SavedSeriesWeeklyCheck.homeSlot(seriesID: 42))
    }

    @Test func dueOnlyAfterItsSlotAndSixDaysAfterTheLastCheck() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let slot = SavedSeriesWeeklyCheck.lastSlotTime(seriesID: 7, now: now, calendar: calendar)
        #expect(slot <= now && now.timeIntervalSince(slot) < 7 * 86_400)
        let justBeforeSlot = slot.addingTimeInterval(-60)
        // Checked 6 days 23 h ago but after the slot came round: not due again until the next slot.
        #expect(!SavedSeriesWeeklyCheck.isDue(seriesID: 7, checkedAt: slot.addingTimeInterval(60), now: now,
                                              calendar: calendar))
        #expect(!SavedSeriesWeeklyCheck.isDue(seriesID: 7, checkedAt: now.addingTimeInterval(-3_600), now: now,
                                              calendar: calendar))
        #expect(SavedSeriesWeeklyCheck.isDue(seriesID: 7, checkedAt: justBeforeSlot.addingTimeInterval(-6 * 86_400),
                                             now: now, calendar: calendar))
    }

    @Test func planTakesMostViewedFirstCappedAndSkipsMailCovered() throws {
        let context = try makeContext()
        let old = Date(timeIntervalSince1970: 0)
        let rows = (1...5).map { id in
            SavedSeries(ao3SeriesID: id, checkedAt: old.addingTimeInterval(Double(id)))
        }
        for row in rows { context.insert(row) }
        rows[0].viewCount = 1; rows[1].viewCount = 9; rows[2].viewCount = 9; rows[3].viewCount = 4
        let picks = SavedSeriesWeeklyCheck.plan(rows, isCoveredByMail: { $0.ao3SeriesID == 4 }, now: Date(),
                                                calendar: calendar)
        #expect(picks.map(\.ao3SeriesID) == [2, 3, 1])
    }

    @Test func passFetchesSequentiallyStopsOn429AndStampsFailures() async throws {
        let context = try makeContext()
        let rows = (1...3).map { SavedSeries(ao3SeriesID: $0, checkedAt: .distantPast) }
        for row in rows { context.insert(row) }
        rows[0].viewCount = 3; rows[1].viewCount = 2; rows[2].viewCount = 1
        let now = Date()
        var fetched: [Int] = []
        var slept: [TimeInterval] = []
        await SavedSeriesWeeklyCheck.run(
            in: context, isMailConnected: false, mailUpdates: [], isScreenActive: { true },
            defaults: UserDefaults(suiteName: UUID().uuidString)!, now: { now },
            sleep: { slept.append($0) },
            fetch: { id in
                fetched.append(id)
                if id == 2 { throw AO3Error.rateLimited(retryAfter: 60) }
                return seriesHTML(works: 2)
            }
        )
        #expect(fetched == [1, 2])
        #expect(slept == [SavedSeriesWeeklyCheck.settleDelay, SavedSeriesWeeklyCheck.spacing])
        #expect(rows[0].partCount == 2 && rows[0].checkedAt == now)
        #expect(rows[1].checkedAt == now)
        #expect(rows[2].checkedAt == .distantPast)
    }

    @Test func offOrMailCoveredMeansNoRequest() async throws {
        let context = try makeContext()
        let saved = SavedSeries(ao3SeriesID: 8, checkedAt: .distantPast)
        context.insert(saved)
        var fetched = 0
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(false, forKey: SavedSeriesWeeklyCheck.enabledKey)
        await SavedSeriesWeeklyCheck.run(in: context, isMailConnected: true, mailUpdates: [], isScreenActive: { true },
                                         defaults: defaults, sleep: { _ in }, fetch: { _ in fetched += 1; return "" })
        defaults.set(true, forKey: SavedSeriesWeeklyCheck.enabledKey)
        await SavedSeriesWeeklyCheck.run(
            in: context, isMailConnected: true, mailUpdates: [update(workID: 99, seriesID: 8)],
            isScreenActive: { true }, defaults: defaults, sleep: { _ in }, fetch: { _ in fetched += 1; return "" }
        )
        #expect(fetched == 0)
        // The notification still added its work, with no request.
        #expect(saved.partWorkIDs == [99] && saved.partCount == 1 && saved.isSubscribed)
    }

    @Test func theSettingTravelsInBackupsAndAnAbsentKeyLeavesItAlone() {
        let source = UserDefaults(suiteName: UUID().uuidString)!
        source.set(false, forKey: SavedSeriesWeeklyCheck.enabledKey)
        #expect(KudosBackupSettings.capture(defaults: source).checksSavedSeriesWeekly == false)
        let target = UserDefaults(suiteName: UUID().uuidString)!
        KudosBackupSettings.capture(defaults: source).apply(to: target)
        #expect(target.object(forKey: SavedSeriesWeeklyCheck.enabledKey) as? Bool == false)
        let untouched = UserDefaults(suiteName: UUID().uuidString)!
        untouched.set(false, forKey: SavedSeriesWeeklyCheck.enabledKey)
        KudosBackupSettings.capture(defaults: UserDefaults(suiteName: UUID().uuidString)!).apply(to: untouched)
        #expect(untouched.object(forKey: SavedSeriesWeeklyCheck.enabledKey) as? Bool == false)
    }
}
