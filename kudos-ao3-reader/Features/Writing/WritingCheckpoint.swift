import Foundation

/// Monotonic clock for editor checkpoints, cooldowns, and timeouts.
/// Production uses `SystemWritingClock` (`ContinuousClock`); tests inject a
/// manual clock so 1.5 s / 20 s / 60 s schedules run deterministically.
nonisolated protocol WritingClock: Sendable {
    var now: Duration { get }
    func sleep(for duration: Duration) async throws
}

nonisolated struct SystemWritingClock: WritingClock {
    private let origin: ContinuousClock.Instant

    init(origin: ContinuousClock.Instant = ContinuousClock.now) {
        self.origin = origin
    }

    var now: Duration {
        ContinuousClock.now - origin
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

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

    /// Monotonic-duration form used by `WritingCheckpointScheduler` with an
    /// injected `WritingClock`.
    func deadline(lastEdit: Duration, firstPendingEdit: Duration) -> Duration {
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
    private let clock: any WritingClock
    private let checkpoint: @MainActor () -> Void
    private var firstPendingEdit: Duration?
    private var lastEdit: Duration?
    private var timer: Task<Void, Never>?
    /// How many checkpoints have run. Increases in the order they ran, so it
    /// doubles as the sequence number `WritingRecoveryWriter` orders writes by.
    private(set) var checkpointCount = 0

    init(
        policy: WritingCheckpointPolicy = WritingCheckpointPolicy(),
        clock: any WritingClock = SystemWritingClock(),
        checkpoint: @escaping @MainActor () -> Void
    ) {
        self.policy = policy
        self.clock = clock
        self.checkpoint = checkpoint
    }

    /// Records an edit. O(1).
    func noteEdit() {
        let now = clock.now
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

    /// Allocates the next monotonic write sequence number when a caller runs
    /// an async checkpoint directly (e.g. a mode hand-off) without re-entering
    /// the synchronous `checkpoint` callback, cancelling any pending idle timer.
    func consumeSequenceForManualCheckpoint() -> Int {
        timer?.cancel()
        timer = nil
        firstPendingEdit = nil
        lastEdit = nil
        checkpointCount += 1
        return checkpointCount
    }

    private var pendingDeadline: Duration? {
        guard let firstPendingEdit, let lastEdit else { return nil }
        return policy.deadline(lastEdit: lastEdit, firstPendingEdit: firstPendingEdit)
    }

    private func startTimer() {
        let clock = self.clock
        timer = Task { [weak self] in
            while true {
                guard let deadline = self?.pendingDeadline else { return }
                let remaining = deadline - clock.now
                if remaining <= .zero {
                    self?.fireNow()
                    return
                }
                do {
                    try await clock.sleep(for: remaining)
                } catch {
                    return // cancelled by fireNow() or cancel()
                }
            }
        }
    }
}

/// The editor rule's word count, run off the main thread at checkpoints
/// (§8.2 step 6). Since E2 it is AO3's own count (`AO3WordCounter`, OD3), so
/// the number matches what AO3 prints once the chapter is posted.
nonisolated enum WritingWordCount {
    static func count(_ html: String) -> Int {
        AO3WordCounter.count(html)
    }
}
