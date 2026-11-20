#if os(iOS)
import SwiftUI
import UIKit

/// The physical edge of the system's vertical bar (`UITraitCollection.verticalBarEdge`,
/// iOS 27.1): the status bar and the app's bars stand on the side of the screen, as on
/// the iPhone Duo's cover and its inner screen in landscape. A layout trait, not a
/// device check — it is `.none` on every screen whose status bar runs along the top.
nonisolated enum ReaderVerticalBar: Equatable, Sendable {
    case none, left, right
}

/// Where the system's own furniture sits in the reader host, in host points. Read
/// from the host's traits and reserved regions (iOS 27.1) — never from a device check.
nonisolated struct ReaderHostRegions: Equatable, Sendable {
    var verticalBar: ReaderVerticalBar = .none
    /// Bottom of the status block at the top of the vertical bar (the occlusion
    /// region on that edge); 0 when there is none to clear.
    var barStatusBottom: CGFloat = 0
    /// The screen's fold, active or not: a flat-open Duo still has one.
    var fold: CGRect?

    /// Keeps the last status-block bottom while the status bar is hidden, so the
    /// rail does not jump as it fades. A new size or bar edge starts afresh.
    func merging(previous: Self, sameSize: Bool) -> Self {
        guard sameSize, previous.verticalBar == verticalBar, barStatusBottom <= 0 else { return self }
        var next = self
        next.barStatusBottom = previous.barStatusBottom
        return next
    }
}

/// Full host geometry, independent of the navigator's horizontally inset bounds.
struct ReaderPageBoxGeometry: Equatable {
    var size: CGSize = .zero
    var safeInsets: UIEdgeInsets = .zero
    var verticalBar: ReaderVerticalBar = .none

    /// What the page keeps clear on the vertical bar's edge: the reader's 64 pt rail
    /// and its 8 pt from the screen edge (Duo boards, `DuoSideBar`). The system's own
    /// inset there comes and goes with the status bar, so the page holds this instead
    /// and showing the controls never reflows the text (T-562a).
    static let verticalBarReserve: CGFloat = 72

    func horizontalInsets(in direction: LayoutDirection) -> EdgeInsets {
        EdgeInsets(
            top: 0, leading: direction == .leftToRight ? safeInsets.left : safeInsets.right,
            bottom: 0, trailing: direction == .leftToRight ? safeInsets.right : safeInsets.left
        )
    }

    func updating(
        size: CGSize, safeInsets: UIEdgeInsets, verticalBar: ReaderVerticalBar = .none,
        preserveStatusBarTop: Bool
    ) -> Self {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 1, size.height > 1 else { return self }
        let sizeChanged = abs(size.width - self.size.width) > 1
            || abs(size.height - self.size.height) > 1
            || verticalBar != self.verticalBar
        var safe = UIEdgeInsets(
            top: max(0, safeInsets.top), left: max(0, safeInsets.left),
            bottom: max(0, safeInsets.bottom), right: max(0, safeInsets.right)
        )
        // The vertical bar's edge: at least the rail, and never smaller than it was
        // for this size, so hiding the status bar there cannot widen the page.
        switch verticalBar {
        case .none: break
        case .left:
            safe.left = max(safe.left, Self.verticalBarReserve, sizeChanged ? 0 : self.safeInsets.left)
        case .right:
            safe.right = max(safe.right, Self.verticalBarReserve, sizeChanged ? 0 : self.safeInsets.right)
        }
        let otherInsetsChanged = abs(safe.left - self.safeInsets.left) > 1
            || abs(safe.bottom - self.safeInsets.bottom) > 1
            || abs(safe.right - self.safeInsets.right) > 1
        // A top-only status-bar hide must not grow the page or move its chrome.
        if !sizeChanged, !otherInsetsChanged, preserveStatusBarTop, safe.top == 0 {
            safe.top = self.safeInsets.top
        }
        let insetsChanged = otherInsetsChanged || abs(safe.top - self.safeInsets.top) > 1
        guard sizeChanged || insetsChanged else { return self }
        return Self(size: size, safeInsets: safe, verticalBar: verticalBar)
    }
}
#endif
