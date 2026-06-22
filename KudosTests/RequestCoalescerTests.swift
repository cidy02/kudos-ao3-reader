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
}
