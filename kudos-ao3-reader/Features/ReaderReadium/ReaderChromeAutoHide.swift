#if os(iOS)
import Foundation
import SwiftUI

/// How the reader's controls come and go (T-562b, owner 2026-11-20, after Apple Books):
/// every show and hide fades, and turning a page hides them.
///
/// A turn hides the controls only when the reader's own input commits it, reported
/// once at that moment by the input path (T-562f): an accepted edge tap, key,
/// page-turner or `goForward`/`goBackward` (`ReadiumPageTurnController`), and a Slide
/// or Curl drag or a trackpad Slide turn, which Readium itself reports once it has
/// landed (`didCommitUserPageTurn`, T-562g). Nothing is inferred from a locator or viewport
/// change, so a reflow, a link, a jump, a scrub or Read Aloud can never hide them.
/// The view decides whether a reported turn may hide the controls (`hidesControls`)
/// and hides them through `ReadiumBook.setChromeHidden`, the one place the
/// show/hide state changes.
nonisolated enum ReaderChromeAutoHide {
    /// The fade every show and hide uses: the bars, the position bar and the status
    /// bar. Kept under Reduce Motion (a fade has no movement); it used to be dropped
    /// there, and the bars inside the peel host never had it at all, so they snapped.
    static let fadeDuration: TimeInterval = 0.25
    static var fade: Animation { .easeInOut(duration: fadeDuration) }

    /// Whether a turn hides the controls: only while they show, never while a
    /// panel, sheet or Contents is open over the page, and never while VoiceOver
    /// runs (the controls stay where VoiceOver found them).
    static func hidesControls(controlsShowing: Bool, overlayOpen: Bool, voiceOverRunning: Bool) -> Bool {
        controlsShowing && !overlayOpen && !voiceOverRunning
    }
}
#endif
