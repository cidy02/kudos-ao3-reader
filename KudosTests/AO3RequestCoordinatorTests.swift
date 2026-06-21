import Foundation
import Testing
@testable import Kudos

/// Covers the bounded-concurrency gate that keeps parallel AO3 fetches polite:
/// it never runs more than `limit` operations at once, serializes when `limit == 1`,
/// runs every queued operation, and frees a slot even when an operation throws.
struct AO3RequestCoordinatorTests {

    /// Tracks how many operations are running at once and the peak reached.
    private actor ConcurrencyTracker {
        private(set) var current = 0
        private(set) var peak = 0
        func enter() {
            current += 1
            peak = max(peak, current)
        }
        func leave() { current -= 1 }
    }

    @Test func neverExceedsTheLimit() async {
        let limit = 4
        let coordinator = AO3RequestCoordinator(limit: limit)
        let tracker = ConcurrencyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await coordinator.withSlot {
                        await tracker.enter()
                        try? await Task.sleep(nanoseconds: 15_000_000)  // ~15ms
                        await tracker.leave()
                    }
                }
            }
        }

        let peak = await tracker.peak
        #expect(peak <= limit)   // the safety bound
        #expect(peak >= 2)       // and it really did run in parallel
    }

    @Test func limitOfOneSerializes() async {
        let coordinator = AO3RequestCoordinator(limit: 1)
        let tracker = ConcurrencyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await coordinator.withSlot {
                        await tracker.enter()
                        try? await Task.sleep(nanoseconds: 5_000_000)
                        await tracker.leave()
                    }
                }
            }
        }

        #expect(await tracker.peak == 1)
    }

    @Test func runsEveryOperationAndReturnsValues() async {
        let coordinator = AO3RequestCoordinator(limit: 3)

        let results = await withTaskGroup(of: Int.self) { group -> [Int] in
            for index in 0..<10 {
                group.addTask { await coordinator.withSlot { index * 2 } }
            }
            var collected: [Int] = []
            for await value in group { collected.append(value) }
            return collected
        }

        #expect(results.count == 10)
        #expect(Set(results) == Set((0..<10).map { $0 * 2 }))
    }

    @Test func freesTheSlotWhenAnOperationThrows() async {
        struct Boom: Error {}
        let coordinator = AO3RequestCoordinator(limit: 1)

        await #expect(throws: Boom.self) {
            try await coordinator.withSlot { throw Boom() }
        }

        // The single slot must have been released, so the next op still runs.
        let ranAfterThrow = await coordinator.withSlot { true }
        #expect(ranAfterThrow)
    }
}
