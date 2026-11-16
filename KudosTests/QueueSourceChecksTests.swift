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
        var attempts: [Int] = []
        await QueueSourceChecks.run(
            sources: [1, 2], checkedAt: { _ in nil }, now: { Date(timeIntervalSince1970: 100_000) },
            sleep: { _ in }, attempt: { source, _ in attempts.append(source); return true },
            fetch: { _ in throw AO3Error.rateLimited(retryAfter: nil) }, received: { _, _ in }
        )
        #expect(attempts == [1])
    }

    @Test func cancellationStopsBeforeNextSource() async {
        var attempts: [Int] = []
        await QueueSourceChecks.run(
            sources: [1, 2], checkedAt: { _ in nil }, now: { Date(timeIntervalSince1970: 100_000) },
            sleep: { _ in }, attempt: { source, _ in attempts.append(source); return true },
            fetch: { _ in throw CancellationError() }, received: { _, _ in }
        )
        #expect(attempts == [1])
    }

    @Test func cancellingThePageTaskStopsAnInFlightPass() async {
        let started = Signal()
        var attempts: [Int] = []
        let task = Task {
            await QueueSourceChecks.run(
                sources: [1, 2], checkedAt: { _ in nil }, now: Date.init,
                sleep: { _ in }, attempt: { source, _ in attempts.append(source); return true },
                fetch: { _ in
                    await started.fire()
                    try await Task.sleep(for: .seconds(2))
                    return page([])
                }, received: { _, _ in }
            )
        }
        await started.wait()
        task.cancel()
        await task.value
        #expect(attempts == [1])
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

    @Test func countUsesOnlyFirstPageAndCapsBadge() {
        let opened = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC
        #expect(QueueSourceChecks.count(page(["02 Jan 2025", "31 Dec 2024"]), since: opened) == 1)
        #expect(QueueSourceChecks.count(page(Array(repeating: "02 Jan 2025", count: 20)), since: opened) == 20)
        #expect(QueueSourceChecks.badge(20) == "20+ new")
        #expect(QueueSourceChecks.badge(1) == "1 new")
    }
}
