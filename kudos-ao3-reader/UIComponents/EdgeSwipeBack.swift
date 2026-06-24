#if os(iOS)
import SwiftUI

/// Adds a left-screen-edge swipe that runs `action` (a "back" affordance), for
/// screens where the navigation stack's own interactive pop gesture doesn't fire:
/// the reader, whose full-screen web view swallows the system edge swipe and whose
/// immersive mode hides the navigation bar; and the focused Search mode, whose Back
/// button leaves to the previous tab rather than popping.
///
/// A thin transparent strip pinned to the leading edge captures the drag before the
/// content beneath it. The drag keeps tracking once it leaves the strip, so a normal
/// edge swipe registers its full horizontal translation.
private struct EdgeSwipeBackModifier: ViewModifier {
    var isActive: Bool = true
    let action: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if isActive {
                Color.clear
                    .frame(width: 20)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onEnded { value in
                                // A deliberate rightward swipe (not a vertical scroll).
                                guard value.translation.width > 44,
                                      abs(value.translation.height) < value.translation.width
                                else { return }
                                action()
                            }
                    )
                    .ignoresSafeArea()
            }
        }
    }
}

extension View {
    /// Triggers `action` on a left-edge swipe (iOS swipe-to-go-back). `isActive`
    /// gates it off when there's nothing to go back to (e.g. a deeper view is pushed).
    func edgeSwipeToGoBack(isActive: Bool = true, perform action: @escaping () -> Void) -> some View {
        modifier(EdgeSwipeBackModifier(isActive: isActive, action: action))
    }
}
#endif
