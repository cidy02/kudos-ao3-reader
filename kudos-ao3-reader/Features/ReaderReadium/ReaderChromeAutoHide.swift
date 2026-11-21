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
    /// How long after an explicit directional user turn (edge tap, key, `goForward`/
    /// `goBackward`) its resulting settle is attributed as a committed user turn.
    static let explicitTurnWindow: TimeInterval = 1.2
    /// How long after the reader follows an internal EPUB link (Readium jumps on its
    /// own, bypassing `ReadiumBook.jump`) the destination's settles are echoes.
    static let linkJumpLead: TimeInterval = 2.0

    /// Minimum scroll delta (fraction of one viewport height) in scrolled mode so
    /// a tiny accidental finger nudge does not hide controls.
    static let scrolledViewportFractionThreshold: Double = 0.15
    /// Fallback progression delta in scrolled mode when page count has not been measured yet.
    static let fallbackProgressionThreshold: Double = 0.01

    /// The parts of a Readium locator that say which page is showing.
    struct Place: Equatable {
        var href: String
        var position: Int?
        var progression: Double?
        /// Visible resource progression range (`first...last`) from Readium's
        /// `NavigatorViewport`. In paged mode, `upperBound - lowerBound` is
        /// `viewportWidth / scrollWidth` (`1 / visualPageCount`), letting us tell
        /// a real visual page turn apart from a same-page wobble before `pageBarReady`.
        var viewportProgression: ClosedRange<Double>?

        init(
            href: String,
            position: Int? = nil,
            progression: Double? = nil,
            viewportProgression: ClosedRange<Double>? = nil
        ) {
            self.href = href
            self.position = position
            self.progression = progression
            self.viewportProgression = viewportProgression
        }
    }

    /// Another resource, a committed visual page change in paged mode (from
    /// measured `pageCount`, Readium's `viewportProgression` span, or an explicit
    /// committed turn when neither is available), or a meaningful scroll in
    /// scrolled mode (never a cancelled sub-page wobble or 1 px nudge).
    static func moved(
        from old: Place, to new: Place,
        isPaged: Bool = true, pageCount: Int? = nil,
        explicitUserTurn: Bool = false
    ) -> Bool {
        if old.href != new.href { return true }
        if !isPaged {
            guard let oldProgression = old.progression, let newProgression = new.progression,
                  oldProgression.isFinite, newProgression.isFinite else { return false }
            let threshold = if let pageCount, pageCount > 0 {
                scrolledViewportFractionThreshold / Double(pageCount)
            } else {
                fallbackProgressionThreshold
            }
            return abs(oldProgression - newProgression) >= threshold
        }
        if let pageCount, pageCount >= 1,
           let oldProgression = old.progression, let newProgression = new.progression,
           oldProgression.isFinite, newProgression.isFinite {
            return ReaderPageMetrics.pageFromLeadingProgression(oldProgression, pageCount: pageCount)
                != ReaderPageMetrics.pageFromLeadingProgression(newProgression, pageCount: pageCount)
        }
        // Before `pageBarReady`, Readium's own `NavigatorViewport` gives the
        // visible page's progression span (`scrollX/scrollW ... (scrollX+vw)/scrollW`),
        // so committed Slide swipes and Curl drags in the first ~450 ms still hide
        // while same-page wobbles and layout-width reflows stay silent.
        if let visualMoved = viewportVisualPageMoved(from: old, to: new, explicitUserTurn: explicitUserTurn) {
            return visualMoved
        }
        // When neither `pageCount` nor a usable `viewportProgression` is available,
        // only a confirmed explicit user turn that moved may hide on the same resource.
        guard explicitUserTurn else { return false }
        return old.position != new.position || old.progression != new.progression
    }

    /// Classifies a same-resource paged move from Readium's `NavigatorViewport`
    /// progression span (`first...last`). Returns `nil` when neither settle has a
    /// usable span.
    private static func viewportVisualPageMoved(
        from old: Place, to new: Place, explicitUserTurn: Bool
    ) -> Bool? {
        func validSpan(_ range: ClosedRange<Double>?) -> Double? {
            guard let range,
                  range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
            let span = range.upperBound - range.lowerBound
            guard span > 1e-6, span <= 1.0 + 1e-6 else { return nil }
            return min(1.0, span)
        }

        let oldSpan = validSpan(old.viewportProgression)
        let newSpan = validSpan(new.viewportProgression)
        guard oldSpan != nil || newSpan != nil else { return nil }

        // When both settles are unclamped (`upperBound < 0.999`), `lowerBound / span`
        // equals `scrollX / viewportWidth` (the 0-based column index). Comparing that
        // keeps async font/image reflows silent while catching every real page turn.
        if let oldRange = old.viewportProgression, let oldSpan,
           let newRange = new.viewportProgression, let newSpan,
           oldRange.upperBound < 0.999, newRange.upperBound < 0.999 {
            // A different span means the page count changed (async font/image reflow):
            // the two column indices belong to different layouts and cannot be compared,
            // so only a confirmed user turn may hide; otherwise it is a baseline update.
            if abs(oldSpan - newSpan) / max(oldSpan, newSpan) > 0.005 {
                return explicitUserTurn && old.progression != new.progression
            }
            let oldCol = oldRange.lowerBound / oldSpan
            let newCol = newRange.lowerBound / newSpan
            return Int(oldCol.rounded()) != Int(newCol.rounded())
                && abs(newCol - oldCol) >= 0.45
        }

        guard let span = [oldSpan, newSpan].compactMap({ $0 }).max() else { return nil }
        // Single-page resource (`0...1`): no intra-resource turns exist.
        guard span < 0.999 else { return false }

        let oldProgression = old.progression ?? old.viewportProgression?.lowerBound
        let newProgression = new.progression ?? new.viewportProgression?.lowerBound
        guard let oldP = oldProgression, let newP = newProgression,
              oldP.isFinite, newP.isFinite else { return nil }

        let pageCount = max(1, Int((1.0 / span).rounded()))
        let oldPage = ReaderPageMetrics.pageFromLeadingProgression(oldP, pageCount: pageCount)
        let newPage = ReaderPageMetrics.pageFromLeadingProgression(newP, pageCount: pageCount)
        return oldPage != newPage && abs(newP - oldP) >= span * 0.45
    }

    /// A settle the reader caused by turning (swipe, curl drag, flick, edge tap,
    /// key): never one while a jump is in flight or just after it (scrubber,
    /// Contents, bookmarks, search, Read Aloud), during a scrub, while a paged
    /// scroll view is still dragging/bouncing, or just after a relayout or
    /// rotation. Explicit user turns (confirmed edge tap / key / `goForward` /
    /// `goBackward`, or a committed swipe / curl drag) carry their own attribution,
    /// scoped to a generation that started after the last jump or relayout, so
    /// neither echo window can mask them; a locator-inferred settle never bypasses.
    /// The first settle after opening has no `previous`.
    static func isUserTurn(
        from previous: Place?, to next: Place,
        jumpInFlight: Bool, isScrubbing: Bool,
        isScrollInteracting: Bool = false,
        isPaged: Bool = true, pageCount: Int? = nil,
        explicitUserTurn: Bool = false,
        jumpEchoUntil: Date = .distantPast,
        relayoutEchoUntil: Date = .distantPast,
        now: Date
    ) -> Bool {
        guard let previous, !jumpInFlight, !isScrubbing,
              !(isPaged && isScrollInteracting),
              explicitUserTurn || (now >= relayoutEchoUntil && now >= jumpEchoUntil) else { return false }
        return moved(
            from: previous, to: next,
            isPaged: isPaged, pageCount: pageCount,
            explicitUserTurn: explicitUserTurn
        )
    }

    /// Whether a turn hides the controls: only while they show, never while a
    /// panel, sheet or Contents is open over the page, and never while VoiceOver
    /// runs (the controls stay where VoiceOver found them).
    static func hidesControls(controlsShowing: Bool, overlayOpen: Bool, voiceOverRunning: Bool) -> Bool {
        controlsShowing && !overlayOpen && !voiceOverRunning
    }
}
#endif
