import Foundation

/// Bounds how many AO3 requests run concurrently so the app can fire *independent*
/// fetches in parallel (e.g. per-category fandom counts) while still behaving like a
/// respectful browser session — a handful of requests at once, never a flood.
///
/// This is the shared concurrency gate the prompt's "AO3RequestCoordinator" calls
/// for. It does **not** replace `AO3Client` (which still owns the actual fetch,
/// retry, and Retry-After handling) — callers wrap their `AO3Client` calls in
/// `withSlot { … }`, and only `limit` of them proceed at a time; the rest suspend
/// (no busy-waiting) until a slot frees. Cancellation propagates normally because a
/// cancelled task simply never enters or exits `withSlot` around its work.
///
/// The default limit (3) matches the polite "2–3 concurrent metadata requests"
/// guideline. Coalescing of duplicate in-flight requests and response caching are
/// layered on separately by callers/`AO3Client`; this type's single job is the
/// concurrency bound.
actor AO3RequestCoordinator {
    /// Shared gate for AO3 metadata/summary fetches.
    static let shared = AO3RequestCoordinator()

    let limit: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int = 3) {
        precondition(limit >= 1, "AO3RequestCoordinator needs at least one slot")
        self.limit = limit
        self.available = limit
    }

    /// Runs `operation` once a concurrency slot is free, releasing the slot when it
    /// finishes (whether it returns or throws). At most `limit` operations run at once.
    func withSlot<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    // MARK: Slot bookkeeping (a fair, suspension-based semaphore)

    private func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        // No slot free: suspend until a `release()` hands this waiter the slot.
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            available = min(available + 1, limit)
        } else {
            // Hand the freed slot directly to the longest-waiting caller (FIFO).
            waiters.removeFirst().resume()
        }
    }
}
