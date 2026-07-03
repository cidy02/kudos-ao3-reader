#if os(iOS)
import SwiftUI
import UIKit

/// Adds a left-**screen-edge** swipe that runs `action` (a "back" affordance), for
/// screens where the navigation stack's own interactive pop gesture doesn't fire:
/// the reader, whose full-screen web view swallows the system edge swipe and whose
/// immersive mode hides the navigation bar; and the focused Search mode, whose Back
/// button leaves to the previous tab rather than popping.
///
/// Uses a real `UIScreenEdgePanGestureRecognizer`, so it fires **only** for swipes
/// that originate at the very screen edge. In-content swipes (e.g. the reader's
/// previous-page swipe, which starts inward) are never mistaken for "go back".
private struct EdgeSwipeBackModifier: ViewModifier {
    var isActive: Bool = true
    let action: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if isActive {
                // A slim strip pinned to the leading edge hosts the edge-pan recognizer.
                // The recognizer only begins for touches starting at the bezel, so the
                // strip's width just needs to cover x≈0; keeping it narrow minimises any
                // overlap with content gestures.
                ScreenEdgePanView(action: action)
                    .frame(width: 16)
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
    }
}

/// Hosts a `UIScreenEdgePanGestureRecognizer(.left)` and fires `action` once a clear
/// edge-originating rightward swipe completes.
private struct ScreenEdgePanView: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let recognizer = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        recognizer.edges = .left
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func handle(_ gesture: UIScreenEdgePanGestureRecognizer) {
            // The recognizer already guarantees an edge origin; require a clear inward
            // travel so a tiny edge graze doesn't dismiss.
            guard gesture.state == .ended,
                  gesture.translation(in: gesture.view).x > 40 else { return }
            action()
        }
    }
}

extension View {
    /// Triggers `action` on a left-**edge** swipe (iOS swipe-to-go-back). `isActive`
    /// gates it off when there's nothing to go back to (e.g. a deeper view is pushed).
    func edgeSwipeToGoBack(isActive: Bool = true, perform action: @escaping () -> Void) -> some View {
        modifier(EdgeSwipeBackModifier(isActive: isActive, action: action))
    }
}
#endif
