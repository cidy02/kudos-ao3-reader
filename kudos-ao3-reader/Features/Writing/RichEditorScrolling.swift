import Foundation

/// Scroll behavior for the Rich Text canvas (docs/WRITING_EDITOR_ARCHITECTURE.md §10.3 N4).
nonisolated enum RichEditorScrollMode: String, CaseIterable, Equatable, Hashable, Sendable {
    /// Scrolls only when the caret approaches or leaves the visible bounds.
    case followCaret
    /// Keeps the caret anchored at a fixed vertical fraction of the visible viewport.
    case typewriter
}

/// Pure scroll-offset calculator for N4 native scrolling (caret-follow and
/// typewriter mode). Operates on the WebView's own scroll view metrics so the
/// document never uses an inner JS scroll container.
nonisolated enum RichEditorScrollCalculator {
    static let defaultCaretMargin: Double = 36
    static let defaultTypewriterFraction: Double = 0.42

    /// Returns the target `contentOffset.y` to keep `caret` visible (or pinned in
    /// typewriter mode), or `nil` when no scroll movement is needed.
    static func targetOffsetY(
        caret: RichEditorCaretRect,
        currentOffsetY: Double,
        viewportHeight: Double,
        contentHeight: Double,
        topInset: Double = 0,
        bottomInset: Double = 0,
        mode: RichEditorScrollMode,
        margin: Double = defaultCaretMargin,
        typewriterFraction: Double = defaultTypewriterFraction
    ) -> Double? {
        let visibleHeight = viewportHeight - topInset - bottomInset
        guard visibleHeight > 0 else { return nil }

        let minOffsetY = -topInset
        let maxOffsetY = max(minOffsetY, contentHeight - viewportHeight + bottomInset)

        let rawTarget: Double
        switch mode {
        case .followCaret:
            let visibleTop = currentOffsetY + topInset
            let visibleBottom = visibleTop + visibleHeight
            let effectiveMargin = min(margin, max(0, (visibleHeight - caret.height) / 2))
            let caretTop = caret.y
            let caretBottom = caret.y + caret.height

            if caretTop < visibleTop + effectiveMargin {
                rawTarget = caretTop - effectiveMargin - topInset
            } else if caretBottom > visibleBottom - effectiveMargin {
                rawTarget = caretBottom + effectiveMargin - visibleHeight - topInset
            } else {
                return nil
            }

        case .typewriter:
            let clampedFraction = min(max(typewriterFraction, 0.1), 0.9)
            let caretMidY = caret.y + caret.height / 2
            let desiredYInViewport = visibleHeight * clampedFraction
            rawTarget = caretMidY - desiredYInViewport - topInset
        }

        let clamped = min(max(rawTarget, minOffsetY), maxOffsetY)
        return abs(clamped - currentOffsetY) < 0.5 ? nil : clamped
    }
}
