import Foundation

/// Debounced durable writes for the iOS Readium reader's `Locator` stream
/// (scrolled-mode hang fix / T-98).
///
/// Readium calls `locationDidChange` after each scroll settle (~0.3s quiet).
/// Persisting on every call — JSON + `markProgressModified` + `modelContext.save()` —
/// hammered the main thread and still-mounted `@Query` graphs. This type keeps the
/// latest locator in memory and decides when a SwiftData write is worth it, mirroring
/// the macOS `ReaderProgressBridge` policy:
///
/// - Streamed updates: at most every `minPersistInterval`, and only when
///   `totalProgression` moved by at least `minProgressionDelta` (or the href/string
///   identity changed when progression is unknown).
/// - Flush points (dismiss, background, disappear): always write if the latest
///   locator differs from what was last marked persisted.
///
/// Pure decision layer — no SwiftData, no Readium imports — so the iOS test suite
/// can cover it without a navigator.
@MainActor
final class ReadiumProgressPersistence {
    /// Write at most this often while progress streams in from scrolling/page turns.
    static let minPersistInterval: TimeInterval = 2
    /// Skip writes for changes smaller than this (noise-level progression jitter).
    static let minProgressionDelta: Double = 0.001

    /// Latest locator JSON reported by the navigator (may be ahead of disk).
    private(set) var latestLocatorString: String?
    /// Latest whole-publication progression (0…1), when Readium provided one.
    private(set) var latestTotalProgression: Double?

    private var lastPersistedString: String?
    private var lastPersistedProgression: Double?
    private var lastPersistAt: Date?

    /// Trailing-edge task so a single settle still persists after the window
    /// without waiting for another scroll event.
    private var trailingTask: Task<Void, Never>?

    /// Called when a debounced or trailing write should hit SwiftData.
    /// Argument is the locator persistence string to store.
    var onDebouncedWrite: ((String) -> Void)?

    deinit {
        trailingTask?.cancel()
    }

    /// Seeds the baseline from the work's already-persisted locator so the first
    /// identical callback after open does not rewrite the store.
    func seed(persistedLocatorString: String?) {
        let seeded = persistedLocatorString.flatMap { $0.isEmpty ? nil : $0 }
        latestLocatorString = seeded
        lastPersistedString = seeded
        latestTotalProgression = nil
        lastPersistedProgression = nil
        lastPersistAt = nil
        trailingTask?.cancel()
        trailingTask = nil
    }

    /// Updates the in-memory latest locator without writing. Used by flush
    /// paths that need the freshest navigator value before `locatorForFlush`.
    func record(locatorString: String, totalProgression: Double?) {
        guard !locatorString.isEmpty else { return }
        latestLocatorString = locatorString
        if let totalProgression, totalProgression.isFinite {
            latestTotalProgression = min(max(totalProgression, 0), 1)
        } else {
            latestTotalProgression = nil
        }
    }

    /// Records a locator from `locationDidChange`. May fire `onDebouncedWrite`
    /// immediately or schedule a trailing write when the debounce window elapses.
    func note(locatorString: String, totalProgression: Double?, at now: Date = Date()) {
        record(locatorString: locatorString, totalProgression: totalProgression)
        if let ready = locatorForDebouncedWrite(at: now) {
            emitDebounced(ready, at: now)
            return
        }
        // Only arm a trailing write when there is a real pending change blocked by
        // the interval. Noise-only notes must not cancel/reset an existing trailing
        // task that is waiting to commit a meaningful earlier settle.
        if isMeaningfullyChanged() {
            scheduleTrailingWrite(from: now)
        }
    }

    /// The locator string to write for an ordinary streamed update, or nil while
    /// the debounce window is open / the change is below the noise threshold.
    func locatorForDebouncedWrite(at now: Date = Date()) -> String? {
        guard let latest = latestLocatorString else { return nil }
        if let lastAt = lastPersistAt, now.timeIntervalSince(lastAt) < Self.minPersistInterval {
            return nil
        }
        if !isMeaningfullyChanged() {
            return nil
        }
        return latest
    }

    /// The locator string to write at a flush point, or nil when disk already
    /// matches the latest in-memory value. Ignores the debounce window.
    func locatorForFlush() -> String? {
        guard let latest = latestLocatorString else { return nil }
        guard latest != lastPersistedString else { return nil }
        return latest
    }

    /// Whether a flush should still run a shelf stamp (`markProgressModified`)
    /// even when the locator string is unchanged — true once the user has a
    /// known position this session (open/dismiss always refresh Continue Reading).
    var hasSessionPosition: Bool {
        latestLocatorString != nil
    }

    /// Marks `locatorString` as durably written so the debounce baseline advances.
    func markPersisted(locatorString: String, totalProgression: Double? = nil, at now: Date = Date()) {
        lastPersistedString = locatorString
        if let totalProgression, totalProgression.isFinite {
            lastPersistedProgression = min(max(totalProgression, 0), 1)
        } else if locatorString == latestLocatorString {
            lastPersistedProgression = latestTotalProgression
        }
        lastPersistAt = now
        trailingTask?.cancel()
        trailingTask = nil
    }

    /// Cancels any pending trailing write (e.g. before a synchronous flush).
    func cancelTrailingWrite() {
        trailingTask?.cancel()
        trailingTask = nil
    }

    // MARK: Private

    private func isMeaningfullyChanged() -> Bool {
        guard let latest = latestLocatorString else { return false }
        // Prefer totalProgression delta when both sides have it: the locator JSON
        // changes on every settle, so string inequality alone would never filter noise.
        // Delta is measured against the *last persisted* progression, so slow reading
        // that accumulates past the threshold still commits (not per-event only).
        if let latestP = latestTotalProgression, let lastP = lastPersistedProgression {
            return abs(latestP - lastP) >= Self.minProgressionDelta
        }
        // No progression on one side (or first post-seed write): any new string counts.
        return latest != lastPersistedString
    }

    private func emitDebounced(_ locatorString: String, at now: Date) {
        markPersisted(
            locatorString: locatorString,
            totalProgression: latestTotalProgression,
            at: now
        )
        onDebouncedWrite?(locatorString)
    }

    private func scheduleTrailingWrite(from now: Date) {
        let remaining: TimeInterval
        if let lastAt = lastPersistAt {
            remaining = max(0, Self.minPersistInterval - now.timeIntervalSince(lastAt))
        } else {
            remaining = Self.minPersistInterval
        }
        trailingTask?.cancel()
        trailingTask = Task { @MainActor [weak self] in
            let nanos = UInt64(remaining * 1_000_000_000)
            if nanos > 0 {
                try? await Task.sleep(nanoseconds: nanos)
            }
            guard !Task.isCancelled, let self else { return }
            let writeAt = Date()
            guard let ready = self.locatorForDebouncedWrite(at: writeAt) else { return }
            self.emitDebounced(ready, at: writeAt)
        }
    }
}
