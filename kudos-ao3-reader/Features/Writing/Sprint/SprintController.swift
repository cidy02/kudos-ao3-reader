import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

/// A light tap for every 100 words of a sprint (iOS only).
@MainActor
enum SprintHaptics {
    static func lightTap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

/// Owns the sprint of one editor screen: start, words, haptics, the end, and the history line.
@MainActor @Observable
final class SprintController {
    static let durations = [10, 15, 25, 45]
    static let defaultMinutes = 25

    private(set) var active: SprintState?
    /// Set when a sprint ends; drives the Sprint Done sheet.
    var result: SprintResult?
    var isChoosingDuration = false

    @ObservationIgnored private let history: SprintHistory
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var records: [SprintRecord] = []
    @ObservationIgnored var tap: () -> Void = { SprintHaptics.lightTap() }

    init(history: SprintHistory = SprintHistory(), calendar: Calendar = .current) {
        self.history = history
        self.calendar = calendar
    }

    var statusInfo: SprintStatusInfo? {
        active.map { SprintStatusInfo(startedAt: $0.startedAt, endsAt: $0.endsAt, words: $0.words) }
    }

    /// Loaded when a sprint starts (it runs at least ten minutes), so the end needs no disk read.
    func loadHistory() async {
        let stored = (try? await history.list()) ?? []
        let known = Set(stored.map(\.id))
        records = stored + records.filter { !known.contains($0.id) }
    }

    /// The ••• menu item: ends a running sprint, or asks how long.
    func toggleFromMenu(now: Date = Date()) {
        if active != nil {
            finish(now: now)
        } else {
            isChoosingDuration = true
        }
    }

    func start(minutes: Int, currentWords: Int, workID: UUID?, now: Date = Date()) {
        guard active == nil else { return }
        active = SprintState(startedAt: now, plannedMinutes: minutes, startWords: currentWords, workID: workID)
        Task { await loadHistory() }
    }

    func noteWords(_ current: Int, now: Date = Date()) {
        guard var state = active else { return }
        let crossed = state.update(currentWords: current, now: now)
        active = state
        if !crossed.isEmpty { tap() }
    }

    /// Ends the sprint if its time is up. Called when the app comes back to the foreground.
    func tick(now: Date = Date()) {
        if let active, now >= active.endsAt { finish(now: now) }
    }

    func runUntilEnd() async {
        while let active, !Task.isCancelled {
            let left = active.endsAt.timeIntervalSinceNow
            if left <= 0 {
                finish()
                return
            }
            try? await Task.sleep(for: .seconds(min(left, 1)))
        }
    }

    /// Ends the sprint and writes it to the history. `showsResult: false` is for an editor that
    /// is closing, which has nowhere to show the sheet.
    @discardableResult
    func finish(now: Date = Date(), showsResult: Bool = true) -> SprintResult? {
        guard let state = active else { return nil }
        var finished = state.finish(now: now)
        finished.isBestThisWeek = SprintMath.isBestThisWeek(
            words: finished.words,
            at: finished.endedAt,
            among: records,
            calendar: calendar
        )
        let record = SprintRecord(
            id: finished.id,
            date: finished.endedAt,
            minutes: finished.minutes,
            words: finished.words,
            workID: finished.workID
        )
        records.append(record)
        let history = history
        Task { try? await history.append(record) }
        active = nil
        if showsResult { result = finished }
        return finished
    }
}
