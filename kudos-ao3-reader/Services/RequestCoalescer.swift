import Foundation

/// Coalesces concurrent identical requests: while an operation for a given key is in
/// flight, callers asking for the same key await that single operation instead of
/// starting a duplicate. This is the "coalesce duplicate requests" politeness rule —
/// two screens asking for the same AO3 page at once make one network call, not two.
///
/// The in-flight entry is cleared once the operation finishes (success or failure),
/// so a later call re-runs (it's a de-duplicator, not a cache — caching is separate).
actor RequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private var inFlight: [Key: Task<Value, Error>] = [:]

    /// Runs `operation` for `key`, or — if one for `key` is already running — awaits
    /// that one and returns its result.
    func shared(_ key: Key, _ operation: @Sendable @escaping () async throws -> Value) async throws -> Value {
        if let existing = inFlight[key] {
            return try await existing.value
        }
        let task = Task { try await operation() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }
}
