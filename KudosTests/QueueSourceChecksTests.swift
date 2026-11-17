import Foundation
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct QueueSourceChecksTests {
    private actor Signal {
        private var fired = false
        private var waiter: CheckedContinuation<Void, Never>?

        func fire() {
            fired = true
            waiter?.resume()
            waiter = nil
        }

        func wait() async {
            if fired { return }
            await withCheckedContinuation { waiter = $0 }
        }
    }

    private func page(_ dates: [String]) -> AO3SearchPage {
        AO3SearchPage(works: dates.enumerated().map { index, date in
            var work = AO3WorkSummary.subscription(id: index + 1, title: "Work", authors: [])
            work.dateUpdated = date
            return work
        }, currentPage: 1, totalPages: 1)
    }

    private func filters(
        sort: AO3SearchFilters.Sort,
        direction: AO3SearchFilters.SortDirection = .descending
    ) -> AO3SearchFilters {
        var value = AO3SearchFilters()
        value.sort = sort
        value.sortDirection = direction
        return value
    }

    @Test func gateAndCapAreOldestFirst() {
        let now = Date(timeIntervalSince1970: 100_000)
        let checks = [now.addingTimeInterval(-30), nil, now.addingTimeInterval(-50_000),
                      now.addingTimeInterval(-40_000), now.addingTimeInterval(-30_000),
                      now.addingTimeInterval(-22_000), now.addingTimeInterval(-21_000),
                      now.addingTimeInterval(-21_601)]
        let selected = QueueSourceChecks.eligible(Array(checks.indices), checkedAt: { checks[$0] }, now: now)
        #expect(selected == [1, 2, 3, 4, 5])
        #expect(QueueSourceChecks.eligible([0], checkedAt: { _ in now.addingTimeInterval(-21_599) }, now: now).isEmpty)
        #expect(QueueSourceChecks.eligible([0], checkedAt: { _ in now.addingTimeInterval(-21_600) }, now: now) == [0])
    }

    @Test func sequentialGapAndFailedAttemptCooldown() async {
        var now = Date(timeIntervalSince1970: 100_000)
        var checked: [Int: Date] = [:]
        var starts: [Date] = []
        await QueueSourceChecks.run(
            sources: [1, 2, 3], checkedAt: { checked[$0] }, now: { now },
            sleep: { now.addTimeInterval($0) },
            attempt: { source, date in checked[source] = date; starts.append(date); return true },
            fetch: { source in
                if source == 1 { throw AO3Error.network("offline") }
                return page([])
            }, received: { _, _ in }
        )
        #expect(starts.count == 3)
        #expect(starts[1].timeIntervalSince(starts[0]) >= 3)
        #expect(starts[2].timeIntervalSince(starts[1]) >= 3)
        #expect(QueueSourceChecks.eligible([1, 2, 3], checkedAt: { checked[$0] }, now: now).isEmpty)
    }

    @Test func rateLimitStopsWithoutRetry() async {
        var fetches: [Int] = []
        await QueueSourceChecks.run(
            sources: [1, 2], checkedAt: { _ in nil }, now: { Date(timeIntervalSince1970: 100_000) },
            sleep: { _ in }, attempt: { _, _ in true },
            fetch: { source in fetches.append(source); throw AO3Error.rateLimited(retryAfter: nil) },
            received: { _, _ in }
        )
        #expect(fetches == [1])
    }

    @Test func cancellationStopsBeforeNextSource() async {
        var fetches: [Int] = []
        await QueueSourceChecks.run(
            sources: [1, 2], checkedAt: { _ in nil }, now: { Date(timeIntervalSince1970: 100_000) },
            sleep: { _ in }, attempt: { _, _ in true },
            fetch: { source in fetches.append(source); throw CancellationError() },
            received: { _, _ in }
        )
        #expect(fetches == [1])
    }

    @Test func cancellingThePageTaskStopsAnInFlightPass() async {
        let started = Signal()
        var fetches: [Int] = []
        let task = Task {
            await QueueSourceChecks.run(
                sources: [1, 2], checkedAt: { _ in nil }, now: Date.init,
                sleep: { _ in }, attempt: { _, _ in true },
                fetch: { source in
                    fetches.append(source)
                    await started.fire()
                    try await Task.sleep(for: .seconds(2))
                    return page([])
                }, received: { _, _ in }
            )
        }
        await started.wait()
        task.cancel()
        await task.value
        #expect(fetches == [1])
    }

    @Test func forbiddenAndMaintenanceStopThePass() async {
        for failure in [AO3Error.forbidden, AO3Error.maintenance] {
            var attempts: [Int] = []
            await QueueSourceChecks.run(
                sources: [1, 2], checkedAt: { _ in nil }, now: Date.init,
                sleep: { _ in }, attempt: { source, _ in attempts.append(source); return true },
                fetch: { _ in throw failure }, received: { _, _ in }
            )
            #expect(attempts == [1])
        }
    }

    @Test func oneRequestIsInFlightAtATime() async {
        var inFlight = 0
        var peak = 0
        await QueueSourceChecks.run(
            sources: [1, 2, 3], checkedAt: { _ in nil }, now: Date.init,
            sleep: { _ in }, attempt: { _, _ in true },
            fetch: { _ in
                inFlight += 1
                peak = max(peak, inFlight)
                await Task.yield()
                inFlight -= 1
                return page([])
            }, received: { _, _ in }
        )
        #expect(peak == 1)
    }

    @Test func countUsesUTCDayAndNilOpenedIsZero() {
        let opened = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00 UTC
        let midday = opened.addingTimeInterval(12 * 60 * 60)
        #expect(QueueSourceChecks.count(page(["02 Jan 2025", "31 Dec 2024"]), since: opened) == 1)
        #expect(QueueSourceChecks.count(page(["01 Jan 2025"]), since: midday) == 1)
        #expect(QueueSourceChecks.count(page(["31 Dec 2024"]), since: midday) == 0)
        #expect(QueueSourceChecks.count(page(["2025-01-01"]), since: midday) == 1)
        #expect(QueueSourceChecks.count(page(Array(repeating: "02 Jan 2025", count: 20)), since: opened) == 20)
        #expect(QueueSourceChecks.count(page(["02 Jan 2025", "01 Jan 2025"]), since: nil) == 0)
        #expect(QueueSourceChecks.badge(20) == "20+ new")
        #expect(QueueSourceChecks.badge(1) == "1 new")
    }

    @Test func unreachableErrorsStopThePassWithoutStamping() async {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed, .timedOut
        ]
        for code in codes {
            var stamped: [Int: Date] = [:]
            var fetches: [Int] = []
            await QueueSourceChecks.run(
                sources: [1, 2], checkedAt: { stamped[$0] }, now: { Date(timeIntervalSince1970: 100_000) },
                sleep: { _ in },
                attempt: { source, date in stamped[source] = date; return true },
                fetch: { source in fetches.append(source); throw URLError(code) },
                received: { _, _ in }
            )
            #expect(fetches == [1], "code \(code)")
            #expect(stamped.isEmpty, "code \(code)")
        }
    }

    @Test func visitIsRecordedAfterPage1OrImmediatelyWhenCached() {
        #expect(QueueSourceChecks.recordsOpenImmediately(hasCachedPage: true))
        #expect(!QueueSourceChecks.recordsOpenImmediately(hasCachedPage: false))
        #expect(QueueSourceChecks.shouldRecordOpen(page: 1, loadToken: 4, expectedToken: 4))
        #expect(!QueueSourceChecks.shouldRecordOpen(page: 2, loadToken: 4, expectedToken: 4))
        #expect(!QueueSourceChecks.shouldRecordOpen(page: 1, loadToken: 5, expectedToken: 4))
    }

    @Test func onlyDateDescendingSortsCount() {
        #expect(!QueueSourceChecks.countsNewResults(AO3SearchFilters()))
        #expect(QueueSourceChecks.countsNewResults(filters(sort: .dateUpdated)))
        #expect(QueueSourceChecks.countsNewResults(filters(sort: .datePosted)))
        #expect(!QueueSourceChecks.countsNewResults(filters(sort: .dateUpdated, direction: .ascending)))
        #expect(!QueueSourceChecks.countsNewResults(filters(sort: .kudos)))
        #expect(!QueueSourceChecks.countsNewResults(filters(sort: .relevance)))
        #expect(QueueSourceChecks.displayedCount(3, filters: filters(sort: .dateUpdated)) == 3)
        #expect(QueueSourceChecks.displayedCount(3, filters: filters(sort: .kudos)) == nil)
        #expect(QueueSourceChecks.displayedCount(0, filters: filters(sort: .dateUpdated)) == nil)
        #expect(QueueSourceChecks.savedSearchAccessibilityLabel(
            name: "Unlinked", count: nil, isLinked: false, filters: AO3SearchFilters()
        ) == "Open saved search Unlinked")
        #expect(QueueSourceChecks.cachedPageForFindMore(page(["01 Jan 2025"]), isLoggedIn: true) == nil)
        #expect(QueueSourceChecks.cachedPageForFindMore(page(["01 Jan 2025"]), isLoggedIn: false) != nil)
    }
}
