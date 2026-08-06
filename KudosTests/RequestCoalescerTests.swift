import Foundation
import Testing
@testable import Kudos

/// Covers request coalescing: concurrent identical requests share one run, different
/// keys run independently, and a key re-runs once its previous run has finished.
struct RequestCoalescerTests {

    private actor Counter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    @Test func coalescesConcurrentIdenticalRequests() async throws {
        let coalescer = RequestCoalescer<String, Int>()
        let counter = Counter()

        let results = try await withThrowingTaskGroup(of: Int.self) { group -> [Int] in
            for _ in 0..<10 {
                group.addTask {
                    try await coalescer.shared("same") {
                        await counter.increment()
                        try? await Task.sleep(nanoseconds: 30_000_000)
                        return 42
                    }
                }
            }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }

        #expect(results == Array(repeating: 42, count: 10))
        #expect(await counter.count == 1)   // ran once despite 10 concurrent callers
    }

    @Test func differentKeysRunIndependently() async throws {
        let coalescer = RequestCoalescer<String, String>()
        let counter = Counter()

        async let a = coalescer.shared("a") { await counter.increment(); return "A" }
        async let b = coalescer.shared("b") { await counter.increment(); return "B" }
        let (resultA, resultB) = try await (a, b)

        #expect(resultA == "A")
        #expect(resultB == "B")
        #expect(await counter.count == 2)
    }

    @Test func reRunsAfterPreviousFinished() async throws {
        let coalescer = RequestCoalescer<String, Int>()
        let counter = Counter()

        _ = try await coalescer.shared("k") { await counter.increment(); return 1 }
        _ = try await coalescer.shared("k") { await counter.increment(); return 1 }

        #expect(await counter.count == 2)   // sequential (non-overlapping) calls each run
    }

    @Test func cancellingOneCallerLeavesTheOtherWaitersResultIntact() async throws {
        // Cancellation is reference-counted. The shared work has to outlive any
        // single caller, so cancelling it on the *first* caller's cancellation
        // would let one screen going away break every other screen waiting on
        // the same page — this pins the behaviour that prevents that.
        let coalescer = RequestCoalescer<String, Int>()
        let counter = Counter()

        let survivor = Task {
            try await coalescer.shared("page-1") {
                await counter.increment()
                try await Task.sleep(nanoseconds: 120_000_000)
                return 42
            }
        }
        // Let the survivor register as the first waiter and start the work.
        try await Task.sleep(nanoseconds: 20_000_000)

        let doomed = Task {
            try await coalescer.shared("page-1") {
                await counter.increment()
                return -1
            }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        doomed.cancel()

        #expect(try await survivor.value == 42)
        #expect(await counter.count == 1)
    }

    @Test func coalescingSurvivesAMidFlightCancellationByAnotherWaiter() async throws {
        // A cancelled waiter reaches `release` twice — once from `onCancel`,
        // once from its own `defer` as the await unwinds — which is why release
        // is keyed by waiter identity rather than a bare count. This asserts the
        // property that matters: one waiter cancelling must not stop a later
        // caller from joining the run that is still in flight.
        //
        // Honest note: this passes against a plain-counter implementation too.
        // The double release turns out to be benign, because a cancelled
        // waiter's `defer` only fires when the shared task completes — the same
        // moment the other waiters release — so the count converges. The
        // identity set is kept for being obviously correct rather than
        // needing-an-argument correct, not because a failing case was found.
        let coalescer = RequestCoalescer<String, Int>()
        let counter = Counter()

        let survivor = Task {
            try await coalescer.shared("page-1") {
                await counter.increment()
                try await Task.sleep(nanoseconds: 250_000_000)
                return 42
            }
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        let doomed = Task {
            try await coalescer.shared("page-1") { await counter.increment(); return -1 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        doomed.cancel()
        try await Task.sleep(nanoseconds: 40_000_000)

        // Joins while the original run is still going: must coalesce, not re-run.
        let latecomer = Task {
            try await coalescer.shared("page-1") { await counter.increment(); return -2 }
        }

        #expect(try await survivor.value == 42)
        #expect(try await latecomer.value == 42)
        #expect(await counter.count == 1)
    }
}
