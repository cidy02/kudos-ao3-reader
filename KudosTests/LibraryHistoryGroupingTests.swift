import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Artboards 1ah and 1ai — how Reading History buckets its rows. Each test pins a
/// choice that could plausibly have gone the other way.
@MainActor
@Suite(.serialized)
struct LibraryHistoryGroupingTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func work(
        _ title: String,
        lastRead: Date? = nil,
        finished: Bool = false,
        hasEPUB: Bool = true,
        started: Bool = false,
        fandoms: [String] = []
    ) -> SavedWork {
        let work = SavedWork(title: title, author: "A")
        work.lastReadDate = lastRead
        work.isFinished = finished
        work.hasEPUB = hasEPUB
        if started { work.lastSpineIndex = 2 }
        work.workFandoms = fandoms
        return work
    }

    private func titles(
        _ grouping: LibraryHistoryGrouping,
        _ works: [SavedWork],
        isAbandoned: @escaping (SavedWork) -> Bool = { _ in false }
    ) -> [String] {
        LibraryHistoryGrouping.groups(
            grouping, works: works, now: now, calendar: calendar, isAbandoned: isAbandoned
        ).map(\.title)
    }

    // MARK: Order

    @Test func timeBucketsKeepTheirSourceOrderRatherThanSortingBySize() {
        let today = work("Today", lastRead: now)
        let old1 = work("Old 1", lastRead: now.addingTimeInterval(-200 * 86_400))
        let old2 = work("Old 2", lastRead: now.addingTimeInterval(-300 * 86_400))
        let old3 = work("Old 3", lastRead: now.addingTimeInterval(-400 * 86_400))

        // Earlier has three works and Today has one. Ranked by size, Earlier would
        // come first — and a list whose sections reshuffle as you read is one you
        // cannot learn the shape of.
        #expect(titles(.time, [today, old1, old2, old3]) == ["Today", "Earlier"])
    }

    @Test func aWorkNeverOpenedIsItsOwnBucketNotTheOldestOne() {
        let never = work("Never")
        let old = work("Old", lastRead: now.addingTimeInterval(-400 * 86_400))
        let buckets = titles(.time, [old, never])

        // "Never opened" and "a long time ago" are different answers, and the second
        // implies the first happened.
        #expect(buckets == ["Earlier", "Never opened"])
    }

    @Test func emptyBucketsAreDroppedRatherThanDrawnEmpty() {
        #expect(titles(.time, [work("Today", lastRead: now)]) == ["Today"])
    }

    // MARK: State

    @Test func aFreedFileThatWasNeverFinishedIsReadNotFinished() {
        // This is the bucket Reading History actually fills: the shelf selects
        // !hasEPUB, so nothing on it can be `.inProgress`.
        let freed = work("Freed", lastRead: now, hasEPUB: false, started: true)
        #expect(titles(.state, [freed]) == ["Read, not finished"])
    }

    @Test func abandonedWinsOverInProgressSoNoWorkIsCountedTwice() {
        let stalled = work("Stalled", lastRead: now, started: true)
        let active = work("Active", lastRead: now, started: true)
        let buckets = LibraryHistoryGrouping.groups(
            .state, works: [stalled, active], now: now, calendar: calendar,
            isAbandoned: { $0.title == "Stalled" }
        )

        #expect(buckets.map(\.title) == ["In progress", "Abandoned"])
        #expect(buckets.flatMap(\.workIDs).count == 2)
        // The same work must not appear under both.
        #expect(Set(buckets.flatMap(\.workIDs)).count == 2)
    }

    @Test func finishedWinsOverEverythingIncludingAFreedFile() {
        let finishedAndFreed = work("Done", lastRead: now, finished: true, hasEPUB: false)
        #expect(titles(.state, [finishedAndFreed]) == ["Finished"])
    }

    // MARK: Fandom

    @Test func fandomGroupsRankBySizeBecauseTheyHaveNoNaturalOrder() {
        let works = [
            work("A", fandoms: ["Naruto"]),
            work("B", fandoms: ["Naruto"]),
            work("C", fandoms: ["Dracula"]),
            work("D", fandoms: [])
        ]
        // Size first, then alphabetical — stable across renders, unlike a dictionary's
        // own order. A work with no fandom is named rather than dropped.
        #expect(titles(.fandom, works) == ["Naruto", "Dracula", "No fandom"])
    }

    @Test func everyWorkLandsInExactlyOneBucketUnderEveryGrouping() {
        let works = [
            work("A", lastRead: now, finished: true),
            work("B", lastRead: now.addingTimeInterval(-400 * 86_400), hasEPUB: false, started: true),
            work("C", fandoms: ["Naruto"]),
            work("D", lastRead: now, started: true)
        ]
        for grouping in LibraryHistoryGrouping.allCases {
            let buckets = LibraryHistoryGrouping.groups(
                grouping, works: works, now: now, calendar: calendar, isAbandoned: { _ in false }
            )
            let ids = buckets.flatMap(\.workIDs)
            #expect(ids.count == works.count, "\(grouping) dropped or duplicated a work")
            #expect(Set(ids).count == works.count, "\(grouping) put a work in two buckets")
        }
    }

    // MARK: Flat

    @Test func flatIsOneBucketAndEmptyInputIsNoBuckets() {
        #expect(titles(.flat, [work("A"), work("B")]) == ["All"])
        #expect(titles(.flat, []).isEmpty)
    }
}
