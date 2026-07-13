import Foundation

/// The native half of the legacy (macOS) reader's intra-chapter position bridge
/// (A7-F2).
///
/// The reader's injected layout script reports one normalized, semantic
/// location for both layout modes: the fraction of the chapter's content above
/// the viewport's leading edge — `scrollY / scrollHeight` in scrolled mode,
/// `page / pageCount` in paged mode. Because the fraction is content-relative,
/// the same value restores the same reading spot across scrolled ↔ paged
/// switches, window resizes/reflows, and relaunches.
///
/// Everything about that fraction that doesn't need a web view lives here so
/// the iOS test suite (the only one `Scripts/verify.sh` runs) can cover it:
/// script-message parsing with stale-load gating, per-chapter session memory,
/// the paged-restore page mapping, and the SwiftData write debounce. The
/// macOS-only `ReaderController`/`ReaderView` consume it.

/// A message posted by the reader's injected layout script. Every payload
/// carries the load generation that produced it; `parse` drops messages whose
/// generation is stale, so late callbacks from an old chapter's document can
/// never overwrite the current chapter's state.
enum ReaderBridgeMessage: Equatable {
    /// Normalized intra-chapter position (0…1) at the viewport's leading edge.
    case progress(fraction: Double)
    /// 1-based page and page count within the current chapter (paged mode).
    case pagePosition(page: Int, total: Int)
    /// The user scrolled to the bottom of the chapter (scrolled mode).
    case reachedScrollBottom
    /// A page-turn key intercepted by the script (paged mode).
    case key(String)

    static func parse(_ body: Any, currentGeneration: Int) -> ReaderBridgeMessage? {
        guard let dict = body as? [String: Any],
              let generation = dict["gen"] as? Int,
              generation == currentGeneration
        else { return nil }
        if let key = dict["key"] as? String {
            return .key(key)
        }
        if let event = dict["event"] as? String {
            switch event {
            case "bottom":
                return .reachedScrollBottom
            case "progress":
                guard let fraction = dict["fraction"] as? Double, fraction.isFinite else { return nil }
                return .progress(fraction: min(max(fraction, 0), 1))
            default:
                return nil
            }
        }
        if dict["mode"] as? String == "paged" {
            let page = dict["page"] as? Int ?? 1
            let total = dict["total"] as? Int ?? 1
            return .pagePosition(page: max(1, page), total: max(1, total))
        }
        return nil
    }
}

/// Owns the current chapter's normalized position, remembers each visited
/// chapter's position for the session (so returning to a prior chapter lands
/// where the user left it), and decides when a streamed update is worth a
/// SwiftData write. Flush points (dismissal, chapter/mode transitions, app
/// termination) bypass the debounce via `fractionForFlush`.
@MainActor
final class ReaderProgressBridge {
    /// Write at most this often while progress streams in from scrolling.
    static let minPersistInterval: TimeInterval = 2
    /// Skip writes for changes smaller than this (noise-level scroll jitter).
    static let minPersistDelta: Double = 0.001

    /// The spine index the fraction below belongs to; nil before any chapter.
    private(set) var currentSpine: Int?
    /// Latest reported fraction for the current chapter (0…1).
    private(set) var currentFraction: Double = 0
    /// Session memory: the last fraction seen for each visited chapter.
    private var fractionBySpine: [Int: Double] = [:]

    private var lastPersistedFraction: Double?
    private var lastPersistAt: Date?

    /// Seeds session memory from the persisted position (the work's saved
    /// chapter + fraction) before the first chapter load, so reopening
    /// restores the exact saved spot.
    func seed(spine: Int, fraction: Double) {
        guard fraction > 0 else { return }
        fractionBySpine[spine] = min(max(fraction, 0), 1)
    }

    /// Begins a chapter and returns the fraction to restore in it: the
    /// session-remembered position for a revisit, or 0 (top) for a first visit.
    /// The caller persists this value alongside the spine index, so the
    /// persisted pair always describes the chapter actually on screen.
    func beginChapter(spine: Int) -> Double {
        let restore = fractionBySpine[spine] ?? 0
        currentSpine = spine
        currentFraction = restore
        return restore
    }

    /// Drops the remembered position for a chapter — used when the user
    /// explicitly re-picks the current chapter to reset it to its start.
    func forget(spine: Int) {
        fractionBySpine[spine] = nil
        if currentSpine == spine { currentFraction = 0 }
    }

    /// Records a fraction reported by the layout script for the current chapter.
    func recordProgress(_ fraction: Double) {
        guard let spine = currentSpine else { return }
        let clamped = min(max(fraction, 0), 1)
        currentFraction = clamped
        fractionBySpine[spine] = clamped
    }

    /// The fraction to write for an ordinary streamed update, or nil while the
    /// debounce window is open / the change is below the noise threshold.
    func fractionForDebouncedWrite(at now: Date = Date()) -> Double? {
        guard currentSpine != nil else { return nil }
        if let lastAt = lastPersistAt, now.timeIntervalSince(lastAt) < Self.minPersistInterval {
            return nil
        }
        if let last = lastPersistedFraction, abs(currentFraction - last) < Self.minPersistDelta {
            return nil
        }
        return currentFraction
    }

    /// The fraction to write at a flush point (dismissal, chapter/mode
    /// transition, termination), or nil when the persisted value is already
    /// current. Ignores the debounce window — a flush must never be dropped.
    func fractionForFlush() -> Double? {
        guard currentSpine != nil else { return nil }
        guard currentFraction != lastPersistedFraction else { return nil }
        return currentFraction
    }

    /// Marks `fraction` as durably written so the debounce baseline advances.
    func markPersisted(_ fraction: Double, at now: Date = Date()) {
        lastPersistedFraction = fraction
        lastPersistAt = now
    }

    /// Maps a normalized fraction to the 0-based page whose content contains
    /// it. Floors (never rounds up) so a restore can only land at or before
    /// the saved spot — re-reading a line beats skipping one. The `1e-9`
    /// epsilon only absorbs float error in `page/pageCount` round-trips (a
    /// billionth of a page); it cannot skip content, unlike the completion
    /// tolerance A7-F1 removed. Mirrored by `readerRestore` in
    /// `ReaderStylesheet.layoutScript` — keep the formulas identical.
    static func pageIndex(fraction: Double, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        let page = Int((clamped * Double(pageCount) + 1e-9).rounded(.down))
        return min(pageCount - 1, max(0, page))
    }
}
