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

    @Test func cancellingTheOnlyWaiterCancelsTheInnerRequest() async throws {
        let coalescer = RequestCoalescer<String, Int>()
        let entered = Flag()
        let innerCancelled = Flag()
        let task = Task {
            try await coalescer.shared("k") {
                await entered.mark()
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch is CancellationError {
                    await innerCancelled.mark()
                    throw CancellationError()
                }
                return 1
            }
        }
        for _ in 0 ..< 1_000 {
            if await entered.isSet { break }
            await Task.yield()
        }
        let started = ContinuousClock.now
        task.cancel()
        let result = await task.result
        #expect(ContinuousClock.now - started < .seconds(1))
        guard case .failure(is CancellationError) = result else {
            Issue.record("cancelled waiter finished with \(result)")
            return
        }
        #expect(await innerCancelled.isSet)
    }

    @Test func cancellingOneWaiterLeavesTheSharedRequestRunning() async throws {
        let coalescer = RequestCoalescer<String, Int>()
        let started = Gate()
        let finish = Gate()
        let runs = Counter()
        let first = Task {
            try await coalescer.shared("k") {
                await runs.increment()
                await started.signal()
                await finish.wait()
                try Task.checkCancellation()
                return 7
            }
        }
        await started.wait()
        let second = Task {
            try await coalescer.shared("k") {
                await runs.increment()
                return 0
            }
        }
        for _ in 0 ..< 50 { await Task.yield() }
        second.cancel()
        for _ in 0 ..< 50 { await Task.yield() }
        await finish.signal()
        #expect(try await first.value == 7)
        #expect(await runs.count == 1)
    }
}

private actor Flag {
    private(set) var isSet = false
    func mark() { isSet = true }
}

private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        open = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
