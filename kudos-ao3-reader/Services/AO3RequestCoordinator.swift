import Foundation

/// Bounds how many AO3 requests run concurrently so the app can fire *independent*
/// fetches in parallel (e.g. per-category fandom counts) while still behaving like a
/// respectful browser session — a handful of requests at once, never a flood.
///
/// This is the shared concurrency gate the prompt's "AO3RequestCoordinator" calls
/// for. It does **not** replace `AO3Client` (which still owns the actual fetch,
/// retry, and Retry-After handling) — callers wrap their `AO3Client` calls in
/// `withSlot { … }`, and only `limit` of them proceed at a time; the rest suspend
/// (no busy-waiting) until a slot frees. A waiter that's still queued when its task
/// is cancelled is woken immediately (via `withTaskCancellationHandler`) rather than
/// waiting out its turn — `withSlot` throws `CancellationError` for it without ever
/// running the wrapped operation or consuming a slot.
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
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    init(limit: Int = 3) {
        precondition(limit >= 1, "AO3RequestCoordinator needs at least one slot")
        self.limit = limit
        self.available = limit
    }

    /// Runs `operation` once a concurrency slot is free, releasing the slot when it
    /// finishes (whether it returns or throws). At most `limit` operations run at once.
    /// Throws `CancellationError` (without ever running `operation`) if the calling
    /// task is cancelled while still queued for a slot — a long-running sequential
    /// refresh (e.g. a large Reading Queue's pull-to-refresh) shouldn't have to wait
    /// out its turn just to notice it was already cancelled.
    func withSlot<T>(_ operation: () async throws -> T) async throws -> T {
        guard await acquire() else {
            throw CancellationError()
        }
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

    /// Returns `true` once a slot is actually held, `false` if this waiter was
    /// cancelled before one became available (in which case no slot was consumed —
    /// `release()` never sees this waiter, so the next real waiter is unaffected).
    private func acquire() async -> Bool {
        if available > 0 {
            available -= 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Removes a cancelled waiter from the queue and wakes it with `false`, so it
    /// stops waiting immediately instead of only after some unrelated slot-holder
    /// finishes. No-op if it already got a real slot via `release()`.
    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    private func release() {
        if waiters.isEmpty {
            available = min(available + 1, limit)
        } else {
            // Hand the freed slot directly to the longest-waiting caller (FIFO).
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }
}
