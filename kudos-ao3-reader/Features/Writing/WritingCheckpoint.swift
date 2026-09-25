import Foundation

/// When a field editor checkpoints (docs/WRITING_EDITOR_ARCHITECTURE.md §8.1):
/// `idleDelay` after the last edit, and never later than `maxInterval` after the
/// first edit that hasn't been checkpointed, so continuous typing still saves.
/// Android uses the same numbers; change them in the doc first.
nonisolated struct WritingCheckpointPolicy: Equatable, Sendable {
    var idleDelay: Duration = .milliseconds(1500)
    var maxInterval: Duration = .seconds(20)

    /// The instant pending edits have to be checkpointed by.
    func deadline(
        lastEdit: ContinuousClock.Instant,
        firstPendingEdit: ContinuousClock.Instant
    ) -> ContinuousClock.Instant {
        min(lastEdit + idleDelay, firstPendingEdit + maxInterval)
    }
}

/// Runs a checkpoint on `WritingCheckpointPolicy`'s schedule.
///
/// `noteEdit()` runs on every keystroke, so it only records the time: one timer
/// task sleeps until the current deadline, re-reads it when it wakes (typing
/// moves it), and fires once the deadline has really passed. That is at most
/// one wake-up per `idleDelay` while typing, rather than a task per keystroke.
@MainActor
final class WritingCheckpointScheduler {
    private let policy: WritingCheckpointPolicy
    private let checkpoint: @MainActor () -> Void
    private var firstPendingEdit: ContinuousClock.Instant?
    private var lastEdit: ContinuousClock.Instant?
    private var timer: Task<Void, Never>?
    /// How many checkpoints have run. Increases in the order they ran, so it
    /// doubles as the sequence number `WritingRecoveryWriter` orders writes by.
    private(set) var checkpointCount = 0

    init(
        policy: WritingCheckpointPolicy = WritingCheckpointPolicy(),
        checkpoint: @escaping @MainActor () -> Void
    ) {
        self.policy = policy
        self.checkpoint = checkpoint
    }

    /// Records an edit. O(1).
    func noteEdit() {
        let now = ContinuousClock.now
        if firstPendingEdit == nil { firstPendingEdit = now }
        lastEdit = now
        if timer == nil { startTimer() }
    }

    /// Checkpoints now — Done, leaving the screen, restoring a copy, a scene
    /// change — and drops the pending deadline. Runs even when nothing is
    /// pending: the checkpoint itself decides whether the text changed.
    func fireNow() {
        timer?.cancel()
        timer = nil
        firstPendingEdit = nil
        lastEdit = nil
        checkpointCount += 1
        checkpoint()
    }

    /// Stops the timer without checkpointing, for teardown.
    func cancel() {
        timer?.cancel()
        timer = nil
        firstPendingEdit = nil
        lastEdit = nil
    }

    private var pendingDeadline: ContinuousClock.Instant? {
        guard let firstPendingEdit, let lastEdit else { return nil }
        return policy.deadline(lastEdit: lastEdit, firstPendingEdit: firstPendingEdit)
    }

    private func startTimer() {
        timer = Task { [weak self] in
            while true {
                guard let deadline = self?.pendingDeadline else { return }
                let remaining = deadline - ContinuousClock.now
                if remaining <= .zero {
                    self?.fireNow()
                    return
                }
                do {
                    try await Task.sleep(for: remaining)
                } catch {
                    return // cancelled by fireNow() or cancel()
                }
            }
        }
    }
}

/// The editor footer's word count, run off the main thread at checkpoints
/// (§8.2 step 6). It is the same count as before: tags stripped, then
/// whitespace-separated runs. Only where it runs changed. AO3's own algorithm
/// (§3.6) is E2, pending OD3.
nonisolated enum WritingWordCount {
    static func count(_ html: String) -> Int {
        html.strippingHTML().split(whereSeparator: \.isWhitespace).count
    }
}
