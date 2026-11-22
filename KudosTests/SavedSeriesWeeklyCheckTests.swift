import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-519b: the weekly saved-series check is spread over the week, most viewed first, capped, and mail first.
@MainActor
struct SavedSeriesWeeklyCheckTests {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([SavedSeries.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func defaults(enabled: Bool? = nil) -> UserDefaults {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        if let enabled { store.set(enabled, forKey: SavedSeriesWeeklyCheck.enabledKey) }
        return store
    }

    private func seriesHTML(works: Int, listed: Int = 0) -> String {
        let blurbs = (0..<listed).map { i in
            "<li class=\"work blurb group\" id=\"work_\(900 + i)\"><h4 class=\"heading\">"
                + "<a href=\"/works/\(900 + i)\">W\(i)</a></h4></li>"
        }.joined()
        return """
        <h2 class="heading">S</h2><dl class="series meta group"><dd class="stats"><dl class="stats">
        <dd class="words">100</dd><dd class="works">\(works)</dd><dt>Complete:</dt><dd>No</dd></dl></dd></dl>
        <ul class="series work index group">\(blurbs)</ul>
        """
    }

    private func update(
        workID: UInt64, seriesID: Int, series: String? = nil, words: UInt64? = nil, at: Date = Date()
    ) -> SubscriptionUpdate {
        SubscriptionUpdate(
            uid: 1, workID: workID, chapterID: nil, chapterNumber: nil, isNewWork: true, isContested: false,
            isAnchoredToWork: true, workTitle: "W", author: "A", at: at, source: .series("Series #\(seriesID)"),
            words: words, series: series
        )
    }

    private func insertDue(_ ids: [Int], in context: ModelContext) -> [SavedSeries] {
        let rows = ids.map { SavedSeries(ao3SeriesID: $0, checkedAt: .distantPast) }
        for row in rows { context.insert(row) }
        return rows
    }

    @Test func slotsSpreadAcrossTheWeekAndKeepTheirHourThroughDST() {
        var counts = [Int](repeating: 0, count: 168)
        for id in 1...1_000 { counts[SavedSeriesWeeklyCheck.homeSlot(seriesID: id)] += 1 }
        #expect(counts.max()! <= 3 * (1_000 / 168 + 1))
        let ny = calendar("America/New_York")
        // A slot at 03:00 on a day after Sunday 1 November 2026, the fall-back day: counting raw hours from the week's
        // start would land it at 02:00 local time.
        let id = (1...20_000).first {
            let slot = SavedSeriesWeeklyCheck.homeSlot(seriesID: $0)
            return slot % 24 == 3 && (1...5).contains(slot / 24)
        }!
        let now = ny.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 23))!
        let slot = SavedSeriesWeeklyCheck.lastSlotTime(seriesID: id, now: now, calendar: ny)
        #expect(ny.component(.hour, from: slot) == 3)
        #expect(ny.component(.day, from: slot) == 1 + SavedSeriesWeeklyCheck.homeSlot(seriesID: id) / 24)
    }

    @Test func dueOnlyAfterItsSlotAndAtLeastSixDaysAfterTheLastCheck() {
        let cal = calendar()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let slot = SavedSeriesWeeklyCheck.lastSlotTime(seriesID: 7, now: now, calendar: cal)
        let beforeSlot = slot.addingTimeInterval(-60)
        // Checked just before the slot came round, long enough ago: due.
        #expect(SavedSeriesWeeklyCheck.isDue(seriesID: 7, checkedAt: beforeSlot.addingTimeInterval(-6 * 86_400),
                                             now: now, calendar: cal))
        // Checked after this week's slot: not due again until the next slot.
        #expect(!SavedSeriesWeeklyCheck.isDue(seriesID: 7, checkedAt: slot.addingTimeInterval(60), now: now,
                                              calendar: cal))
        // Before the slot but less than six days ago: the floor holds it back.
        let fiveDaysBefore = now.addingTimeInterval(-5 * 86_400)
        if fiveDaysBefore < slot {
            #expect(!SavedSeriesWeeklyCheck.isDue(seriesID: 7, checkedAt: fiveDaysBefore, now: now, calendar: cal))
        }
    }

    @Test func planTakesMostViewedFirstCappedAndSkipsCovered() throws {
        let context = try makeContext()
        let rows = (1...5).map { SavedSeries(ao3SeriesID: $0, checkedAt: Date(timeIntervalSince1970: Double($0))) }
        for row in rows { context.insert(row) }
        rows[0].viewCount = 1; rows[1].viewCount = 9; rows[2].viewCount = 9; rows[3].viewCount = 4
        let picks = SavedSeriesWeeklyCheck.plan(rows, isCoveredByMail: { $0.ao3SeriesID == 4 }, now: Date(),
                                                calendar: calendar())
        #expect(picks.map(\.ao3SeriesID) == [2, 3, 1])
    }

    @Test func passIsSequentialStopsOn429AndStampsOnlyWhatItAsked() async throws {
        let context = try makeContext()
        let rows = insertDue([1, 2, 3], in: context)
        rows[0].viewCount = 3; rows[1].viewCount = 2; rows[2].viewCount = 1
        let now = Date()
        var fetched: [Int] = []
        var slept: [TimeInterval] = []
        await SavedSeriesWeeklyCheck.run(
            in: context, mail: { (false, []) }, isScreenActive: { true }, defaults: defaults(), now: { now },
            sleep: { slept.append($0) }, isHeld: { false },
            fetch: { id in
                fetched.append(id)
                if id == 2 { throw AO3Error.rateLimited(retryAfter: 60) }
                return seriesHTML(works: 2, listed: 2)
            }
        )
        #expect(fetched == [1, 2])
        #expect(slept == [SavedSeriesWeeklyCheck.settleDelay, SavedSeriesWeeklyCheck.spacing])
        #expect(rows[0].partCount == 2 && rows[0].partWorkIDs.count == 2 && rows[0].checkedAt == now)
        #expect(rows[1].checkedAt == now)
        #expect(rows[2].checkedAt == .distantPast)
    }

    @Test func aHoldOrALeftScreenSendsNothingAndStampsNothing() async throws {
        let context = try makeContext()
        let rows = insertDue([1], in: context)
        var fetched = 0
        await SavedSeriesWeeklyCheck.run(in: context, mail: { (false, []) }, isScreenActive: { true },
                                         defaults: defaults(), sleep: { _ in }, isHeld: { true },
                                         fetch: { _ in fetched += 1; return "" })
        var active = true
        await SavedSeriesWeeklyCheck.run(in: context, mail: { (false, []) }, isScreenActive: { active },
                                         defaults: defaults(), sleep: { _ in active = false }, isHeld: { false },
                                         fetch: { _ in fetched += 1; return "" })
        #expect(fetched == 0)
        #expect(rows[0].checkedAt == .distantPast)
    }

    @Test func coveredMeansSubscribedWithMailConnectedNotJustOldMail() async throws {
        let context = try makeContext()
        let rows = insertDue([1, 2], in: context)
        rows[0].isSubscribed = true
        // Series 2 was unsubscribed after its last notification; that old notification is still in the mail store.
        rows[1].lastNotifiedAt = Date(timeIntervalSince1970: 2_000)
        let oldMail = [update(workID: 5, seriesID: 2, at: Date(timeIntervalSince1970: 1_000))]
        var fetched: [Int] = []
        let html = seriesHTML(works: 1)
        await SavedSeriesWeeklyCheck.run(in: context, mail: { (true, oldMail) }, isScreenActive: { true },
                                         defaults: defaults(), sleep: { _ in }, isHeld: { false },
                                         fetch: { fetched.append($0); return html })
        #expect(fetched == [2])
        #expect(!rows[1].isSubscribed)
        // Mail not connected: being subscribed covers nothing.
        rows[0].checkedAt = .distantPast
        fetched = []
        await SavedSeriesWeeklyCheck.run(in: context, mail: { (false, []) }, isScreenActive: { true },
                                         defaults: defaults(), sleep: { _ in }, isHeld: { false },
                                         fetch: { fetched.append($0); return html })
        #expect(fetched == [1])
    }

    @Test func mailAppliesOnceOldestFirstEvenWithTheCheckOff() async throws {
        let context = try makeContext()
        var fetched = 0
        let t0 = Date(timeIntervalSince1970: 1_000)
        // The mail store lists newest first.
        let updates = [update(workID: 66, seriesID: 8, series: "Part 2 of Horizon", words: 500, at: t0 + 60),
                       update(workID: 55, seriesID: 8, series: "Part 1 of Horizon", words: 1_000, at: t0)]
        for _ in 0..<3 {
            await SavedSeriesWeeklyCheck.run(in: context, mail: { (true, updates) }, isScreenActive: { true },
                                             defaults: defaults(enabled: false), sleep: { _ in }, isHeld: { false },
                                             fetch: { _ in fetched += 1; return "" })
        }
        let saved = try #require(SavedSeriesStore.series(for: 8, in: context))
        #expect(fetched == 0)
        #expect(saved.partWorkIDs == [55, 66] && saved.partCount == 2)
        #expect(saved.wordCount == 1_500)   // three passes, counted once
        #expect(saved.isSubscribed)
        // A part far beyond the list raises the count without pretending the list is whole; an absurd one is ignored.
        SavedSeriesWeeklyCheck.applyMail([update(workID: 99, seriesID: 8, series: "Part 9 of Horizon", at: t0 + 120),
                                          update(workID: 98, seriesID: 8, series: "Part 999999 of H", at: t0 + 180)],
                                         in: context)
        #expect(saved.partWorkIDs == [55, 66] && saved.partCount == 10)
    }

    @Test func oneEmailWithTwoWorksOfASeriesAppliesBoth() throws {
        let context = try makeContext()
        let at = Date(timeIntervalSince1970: 5_000)
        let batch = [update(workID: 1, seriesID: 3, series: "Part 1 of S", words: 10, at: at),
                     update(workID: 2, seriesID: 3, series: "Part 2 of S", words: 20, at: at)]
        SavedSeriesWeeklyCheck.applyMail(batch, in: context)
        SavedSeriesWeeklyCheck.applyMail(batch, in: context)
        let saved = try #require(SavedSeriesStore.series(for: 3, in: context))
        #expect(saved.partWorkIDs == [1, 2] && saved.wordCount == 30)
    }

    @Test func viewsCountOncePerCall() throws {
        let context = try makeContext()
        let saved = SavedSeries(ao3SeriesID: 4)
        context.insert(saved)
        SavedSeriesWeeklyCheck.recordView(seriesID: 4, in: context)
        SavedSeriesWeeklyCheck.recordView(seriesID: 404, in: context)
        SavedSeriesWeeklyCheck.recordView(seriesID: nil, in: context)
        #expect(saved.viewCount == 1 && saved.lastViewedAt != nil)
    }

    @Test func anAnonymousViewThatCountsFewerWorksKeepsWhatWeHad() async throws {
        let context = try makeContext()
        let rows = insertDue([1], in: context)
        rows[0].partCount = 3
        rows[0].partWorkIDs = [1, 2, 3]
        await SavedSeriesWeeklyCheck.run(in: context, mail: { (false, []) }, isScreenActive: { true },
                                         defaults: defaults(), sleep: { _ in }, isHeld: { false },
                                         fetch: { _ in seriesHTML(works: 1, listed: 1) })
        #expect(rows[0].partCount == 3 && rows[0].partWorkIDs == [1, 2, 3])
        #expect(rows[0].checkedAt != .distantPast)
    }

    @Test func theSettingTravelsInBackupsAndAnAbsentKeyLeavesItAlone() {
        let source = defaults(enabled: false)
        #expect(KudosBackupSettings.capture(defaults: source).checksSavedSeriesWeekly == false)
        let target = defaults()
        KudosBackupSettings.capture(defaults: source).apply(to: target)
        #expect(target.object(forKey: SavedSeriesWeeklyCheck.enabledKey) as? Bool == false)
        let untouched = defaults(enabled: false)
        KudosBackupSettings.capture(defaults: defaults()).apply(to: untouched)
        #expect(untouched.object(forKey: SavedSeriesWeeklyCheck.enabledKey) as? Bool == false)
    }
}
