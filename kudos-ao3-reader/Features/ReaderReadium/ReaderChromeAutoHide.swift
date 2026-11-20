#if os(iOS)
import Foundation
import SwiftUI

/// How the reader's controls come and go (T-562b, owner 2026-11-20, after Apple Books):
/// every show and hide fades, and turning a page hides them.
///
/// Pure, so the rules are testable without a navigator. `ReadiumBook` classifies each
/// settle (`isUserTurn`); the view decides whether that turn may hide the controls
/// (`hidesControls`) and hides them through `ReadiumBook.setChromeHidden`, the one
/// place the show/hide state changes.
nonisolated enum ReaderChromeAutoHide {
    /// The fade every show and hide uses: the bars, the position bar and the status
    /// bar. Kept under Reduce Motion (a fade has no movement); it used to be dropped
    /// there, and the bars inside the peel host never had it at all, so they snapped.
    static let fadeDuration: TimeInterval = 0.25
    static var fade: Animation { .easeInOut(duration: fadeDuration) }

    /// How long after a programmatic jump settles a location report is still its
    /// echo rather than a turn.
    static let jumpEchoWindow: TimeInterval = 0.6
    /// The same after the page is laid out again (preferences, size, rotation),
    /// which can take several settles.
    static let relayoutEchoWindow: TimeInterval = 1.2

    /// The parts of a Readium locator that say which page is showing.
    struct Place: Equatable {
        var href: String
        var position: Int?
        var progression: Double?
    }

    /// Another resource, another position, or the progression moved (a page in
    /// the same position, or scroll mode).
    static func moved(from old: Place, to new: Place) -> Bool {
        if old.href != new.href { return true }
        if let oldPosition = old.position, let newPosition = new.position, oldPosition != newPosition {
            return true
        }
        guard let oldProgression = old.progression, let newProgression = new.progression else { return false }
        return abs(oldProgression - newProgression) > 0.0001
    }

    /// A settle the reader caused by turning (swipe, curl drag, flick, edge tap,
    /// key): never one while a jump is in flight or just after it (scrubber,
    /// Contents, bookmarks, search, Read Aloud), during a scrub, or just after a
    /// relayout or rotation. The first settle after opening has no `previous`.
    static func isUserTurn(
        from previous: Place?, to next: Place,
        jumpInFlight: Bool, isScrubbing: Bool, echoUntil: Date, now: Date
    ) -> Bool {
        guard let previous, !jumpInFlight, !isScrubbing, now >= echoUntil else { return false }
        return moved(from: previous, to: next)
    }

    /// Whether a turn hides the controls: only while they show, never while a
    /// panel, sheet or Contents is open over the page, and never while VoiceOver
    /// runs (the controls stay where VoiceOver found them).
    static func hidesControls(controlsShowing: Bool, overlayOpen: Bool, voiceOverRunning: Bool) -> Bool {
        controlsShowing && !overlayOpen && !voiceOverRunning
    }
}
#endif
