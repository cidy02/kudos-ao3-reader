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

    @Test func neverExceedsTheLimit() async throws {
        let limit = 4
        let coordinator = AO3RequestCoordinator(limit: limit)
        let tracker = ConcurrencyTracker()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await coordinator.withSlot {
                        await tracker.enter()
                        try? await Task.sleep(nanoseconds: 15_000_000)  // ~15ms
                        await tracker.leave()
                    }
                }
            }
            try await group.waitForAll()
        }

        let peak = await tracker.peak
        #expect(peak <= limit)   // the safety bound
        #expect(peak >= 2)       // and it really did run in parallel
    }

    @Test func limitOfOneSerializes() async throws {
        let coordinator = AO3RequestCoordinator(limit: 1)
        let tracker = ConcurrencyTracker()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try await coordinator.withSlot {
                        await tracker.enter()
                        try? await Task.sleep(nanoseconds: 5_000_000)
                        await tracker.leave()
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(await tracker.peak == 1)
    }

    @Test func runsEveryOperationAndReturnsValues() async throws {
        let coordinator = AO3RequestCoordinator(limit: 3)

        let results = try await withThrowingTaskGroup(of: Int.self) { group -> [Int] in
            for index in 0..<10 {
                group.addTask { try await coordinator.withSlot { index * 2 } }
            }
            var collected: [Int] = []
            for try await value in group { collected.append(value) }
            return collected
        }

        #expect(results.count == 10)
        #expect(Set(results) == Set((0..<10).map { $0 * 2 }))
    }

    @Test func freesTheSlotWhenAnOperationThrows() async throws {
        struct Boom: Error {}
        let coordinator = AO3RequestCoordinator(limit: 1)

        await #expect(throws: Boom.self) {
            try await coordinator.withSlot { throw Boom() }
        }

        // The single slot must have been released, so the next op still runs.
        let ranAfterThrow = try await coordinator.withSlot { true }
        #expect(ranAfterThrow)
    }

    /// A cancelled waiter must stop waiting immediately — it must not be handed a
    /// slot at all (so the next real waiter isn't shortchanged), and it must not sit
    /// parked until some unrelated slot-holder happens to finish. This is what makes
    /// a long, sequential pull-to-refresh (e.g. a large Reading Queue) actually stop
    /// promptly when its task is cancelled while queued behind other AO3 activity.
    @Test func cancelledWaiterStopsWaitingWithoutConsumingASlot() async throws {
        let coordinator = AO3RequestCoordinator(limit: 1)
        let holderHasSlot = Signal()
        let releaseHolder = Signal()

        let holderTask = Task {
            try await coordinator.withSlot {
                await holderHasSlot.fire()
                await releaseHolder.wait()
            }
        }
        await holderHasSlot.wait()

        let waiterTask = Task {
            try await coordinator.withSlot { true }
        }
        // Give the waiter a brief moment to actually enqueue itself (there's no
        // synchronous "enqueued" signal to await) before cancelling it.
        try await Task.sleep(nanoseconds: 20_000_000)
        waiterTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await waiterTask.value
        }

        await releaseHolder.fire()
        try await holderTask.value
    }

    /// A one-shot async gate used to deterministically sequence two concurrent tasks
    /// in `cancelledWaiterStopsWaitingWithoutConsumingASlot`.
    private actor Signal {
        private var fired = false
        private var continuation: CheckedContinuation<Void, Never>?

        func fire() {
            fired = true
            continuation?.resume()
            continuation = nil
        }

        func wait() async {
            if fired { return }
            await withCheckedContinuation { continuation = $0 }
        }
    }
}
