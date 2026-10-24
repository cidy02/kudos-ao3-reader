#if os(iOS)
import SwiftUI
import UIKit

/// Full host geometry, independent of the navigator's horizontally inset bounds.
struct ReaderPageBoxGeometry: Equatable {
    var size: CGSize = .zero
    var safeInsets: UIEdgeInsets = .zero

    func horizontalInsets(in direction: LayoutDirection) -> EdgeInsets {
        EdgeInsets(
            top: 0, leading: direction == .leftToRight ? safeInsets.left : safeInsets.right,
            bottom: 0, trailing: direction == .leftToRight ? safeInsets.right : safeInsets.left
        )
    }

    func updating(size: CGSize, safeInsets: UIEdgeInsets, preserveStatusBarTop: Bool) -> Self {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 1, size.height > 1 else { return self }
        let sizeChanged = abs(size.width - self.size.width) > 1
            || abs(size.height - self.size.height) > 1
        var safe = UIEdgeInsets(
            top: max(0, safeInsets.top), left: max(0, safeInsets.left),
            bottom: max(0, safeInsets.bottom), right: max(0, safeInsets.right)
        )
        let otherInsetsChanged = abs(safe.left - self.safeInsets.left) > 1
            || abs(safe.bottom - self.safeInsets.bottom) > 1
            || abs(safe.right - self.safeInsets.right) > 1
        // A top-only status-bar hide must not grow the page or move its chrome.
        if !sizeChanged, !otherInsetsChanged, preserveStatusBarTop, safe.top == 0 {
            safe.top = self.safeInsets.top
        }
        let insetsChanged = otherInsetsChanged || abs(safe.top - self.safeInsets.top) > 1
        guard sizeChanged || insetsChanged else { return self }
        return Self(size: size, safeInsets: safe)
    }
}
#endif
