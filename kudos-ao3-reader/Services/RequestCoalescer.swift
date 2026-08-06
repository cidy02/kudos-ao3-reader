import Foundation

/// Coalesces concurrent identical requests: while an operation for a given key is in
/// flight, callers asking for the same key await that single operation instead of
/// starting a duplicate. This is the "coalesce duplicate requests" politeness rule —
/// two screens asking for the same AO3 page at once make one network call, not two.
///
/// The in-flight entry is cleared once the operation finishes (success or failure),
/// so a later call re-runs (it's a de-duplicator, not a cache — caching is separate).
///
/// **Cancellation is reference-counted.** The shared work has to run in an
/// unstructured `Task` so it can outlive any single caller — that is the whole
/// point — but unstructured tasks don't inherit cancellation, so without the
/// bookkeeping below a cancelled caller would leave the fetch running to
/// completion. Cancelling the shared task on the *first* caller's cancellation
/// would be worse still: one screen going away would break every other screen
/// waiting on the same page. So each waiter is counted, and the task is
/// cancelled only when the last one leaves.
actor RequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let task: Task<Value, Error>
        /// Waiter *identities*, not a count. A cancelled waiter reaches
        /// `release` twice — once from `onCancel`, once from its own `defer` as
        /// the await unwinds — and a plain counter would therefore drop by two,
        /// evicting the entry while another waiter was still registered and
        /// silently letting the next caller start a duplicate fetch. Removing
        /// from a set is idempotent, so the second release is a no-op.
        var waiters: Set<UUID>
    }

    private var inFlight: [Key: Entry] = [:]

    /// Runs `operation` for `key`, or — if one for `key` is already running — awaits
    /// that one and returns its result. Throws `CancellationError` if the calling
    /// task is cancelled; the underlying work is cancelled too, but only once no
    /// other caller is still waiting on it.
    func shared(_ key: Key, _ operation: @Sendable @escaping () async throws -> Value) async throws -> Value {
        let id = UUID()
        let task: Task<Value, Error>
        if var existing = inFlight[key] {
            existing.waiters.insert(id)
            inFlight[key] = existing
            task = existing.task
        } else {
            let created = Task { try await operation() }
            inFlight[key] = Entry(task: created, waiters: [id])
            task = created
        }

        return try await withTaskCancellationHandler {
            defer { Task { await self.release(key, id: id, task: task) } }
            return try await task.value
        } onCancel: {
            Task { await self.release(key, id: id, task: task, cancelled: true) }
        }
    }

    /// Drops one waiter. The entry is removed once nobody is left; if the last
    /// waiter left because it was *cancelled*, the shared work is cancelled with
    /// it rather than running on with no one to receive the result.
    ///
    /// Two guards, both load-bearing: task identity, so a late release from a
    /// finished round can't evict a newer entry that reused the same key; and
    /// set membership, so the same waiter releasing twice (see `Entry.waiters`)
    /// only counts once.
    private func release(_ key: Key, id: UUID, task: Task<Value, Error>, cancelled: Bool = false) {
        guard var entry = inFlight[key], entry.task == task else { return }
        guard entry.waiters.remove(id) != nil else { return }
        if entry.waiters.isEmpty {
            inFlight[key] = nil
            if cancelled { entry.task.cancel() }
        } else {
            inFlight[key] = entry
        }
    }
}
