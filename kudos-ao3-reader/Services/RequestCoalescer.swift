import Foundation

/// Coalesces concurrent identical requests: while an operation for a given key is in
/// flight, callers asking for the same key await that single operation instead of
/// starting a duplicate. This is the "coalesce duplicate requests" politeness rule —
/// two screens asking for the same AO3 page at once make one network call, not two.
///
/// The in-flight entry is cleared once the operation finishes (success or failure),
/// so a later call re-runs (it's a de-duplicator, not a cache — caching is separate).
actor RequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private struct Flight {
        var task: Task<Value, Error>
        var waiters: Set<UUID>
    }

    private var inFlight: [Key: Flight] = [:]

    /// Runs `operation` for `key`, or — if one for `key` is already running — awaits
    /// that one and returns its result.
    ///
    /// The inner task is unstructured, so cancelling a waiter does not cancel it on
    /// its own. When the last waiter goes, cancel that task instead of leaving the
    /// waiter blocked until the request finishes.
    func shared(_ key: Key, _ operation: @Sendable @escaping () async throws -> Value) async throws -> Value {
        let waiter = UUID()
        let task: Task<Value, Error>
        if var flight = inFlight[key] {
            flight.waiters.insert(waiter)
            inFlight[key] = flight
            task = flight.task
        } else {
            let created = Task { try await operation() }
            inFlight[key] = Flight(task: created, waiters: [waiter])
            task = created
        }
        defer { abandon(key, waiter) }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.abandon(key, waiter) }
        }
    }

    private func abandon(_ key: Key, _ waiter: UUID) {
        guard var flight = inFlight[key], flight.waiters.remove(waiter) != nil else { return }
        if flight.waiters.isEmpty {
            flight.task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = flight
        }
    }
}
