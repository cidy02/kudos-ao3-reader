import SwiftUI

/// A persistent, non-interactive scroll-position indicator on the trailing edge.
///
/// No system scrollbar ever appears in the Readium navigator's `WKWebView` —
/// confirmed on-device, not just in the simulator — so there was nothing to fall
/// back on. Chapter-local (page/pageCount), matching what the position card's own
/// scrub slider already tracks; non-interactive by design, since that slider
/// already owns dragging and duplicating the gesture here would just fight it.
struct ReaderScrollIndicator: View {
    let page: Int
    let pageCount: Int
    let tint: Color

    private var fraction: CGFloat {
        guard pageCount > 1 else { return 0 }
        return CGFloat(page - 1) / CGFloat(pageCount - 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let trackHeight = geometry.size.height
            // A minimum thumb height so a long chapter's sliver stays visible and
            // grabbable-looking even though the indicator itself isn't draggable.
            let thumbHeight = min(trackHeight, max(28, trackHeight / CGFloat(max(pageCount, 1))))
            let travel = max(0, trackHeight - thumbHeight)
            Capsule()
                .fill(tint.opacity(0.5))
                .frame(width: 3, height: thumbHeight)
                .offset(y: travel * fraction)
                .animation(.easeOut(duration: 0.2), value: fraction)
        }
        .frame(width: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
