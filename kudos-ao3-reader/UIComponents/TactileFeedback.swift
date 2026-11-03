import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Press feedback for tappable cards and rows: a slight dim and shrink while the finger is
/// down, colours untouched (unlike the system accent tint). Respects Reduce Motion.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .cardPressed(configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardPressStyle {
    static var cardPress: CardPressStyle { CardPressStyle() }
}

extension View {
    /// The shared visual for both native button presses and List's UIKit touch observer.
    func cardPressed(_ isPressed: Bool) -> some View {
        modifier(CardPressEffect(isPressed: isPressed))
    }
}

extension View {
    /// SwiftUI `List` consumes touch-down before `ButtonStyle.isPressed` changes
    /// (filmed 2026-11-03), so List cards observe the UIKit touch without owning it.
    func listCardPressFeedback() -> some View {
        #if canImport(UIKit)
        modifier(ListCardPressFeedbackModifier())
        #else
        self
        #endif
    }
}

private struct CardPressEffect: ViewModifier {
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1)
            .opacity(isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isPressed)
    }
}

#if canImport(UIKit)
private struct ListCardPressFeedbackModifier: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .cardPressed(isPressed)
            .background {
                ListCardPressRecognizer(isPressed: $isPressed)
            }
    }
}

private struct ListCardPressRecognizer: UIViewRepresentable {
    @Binding var isPressed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPressed: $isPressed)
    }

    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        context.coordinator.markerView = view
        return view
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {
        context.coordinator.isPressed = $isPressed
        context.coordinator.installGesture(for: uiView)
    }

    static func dismantleUIView(_: MarkerView, coordinator: Coordinator) {
        coordinator.removeGesture()
    }

    final class MarkerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            coordinator?.installGesture(for: self)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.installGesture(for: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isPressed: Binding<Bool>
        weak var markerView: UIView?
        weak var hostView: UIView?
        private var initialLocation: CGPoint?
        private var isTrackingPress = false

        private lazy var gesture: UILongPressGestureRecognizer = {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleGesture))
            gesture.minimumPressDuration = 0
            gesture.allowableMovement = .greatestFiniteMagnitude
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            return gesture
        }()

        init(isPressed: Binding<Bool>) {
            self.isPressed = isPressed
        }

        func installGesture(for markerView: UIView) {
            self.markerView = markerView
            let host = gestureHost(for: markerView)
            guard host !== hostView else { return }
            removeGesture()
            hostView = host
            host?.addGestureRecognizer(gesture)
        }

        func removeGesture() {
            hostView?.removeGestureRecognizer(gesture)
            hostView = nil
            endPress()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let markerView, markerView.window != nil else { return false }
            return markerView.bounds.contains(touch.location(in: markerView))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handleGesture(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                initialLocation = gesture.location(in: gesture.view)
                isTrackingPress = true
                setPressed(true)
            case .changed:
                guard isTrackingPress, let initialLocation else { return }
                let location = gesture.location(in: gesture.view)
                if hypot(location.x - initialLocation.x, location.y - initialLocation.y) > 10 {
                    endPress()
                }
            case .ended, .cancelled, .failed:
                endPress()
            default:
                break
            }
        }

        private func gestureHost(for markerView: UIView) -> UIView? {
            var ancestor = markerView.superview
            while let view = ancestor {
                if view is UIScrollView { return view }
                ancestor = view.superview
            }
            return markerView.window
        }

        private func endPress() {
            initialLocation = nil
            isTrackingPress = false
            setPressed(false)
        }

        private func setPressed(_ pressed: Bool) {
            guard isPressed.wrappedValue != pressed else { return }
            isPressed.wrappedValue = pressed
        }
    }
}
#endif

/// Haptics for the few actions whose view disappears with the action (a row deleted from a list),
/// where `.sensoryFeedback(trigger:)` has no surviving view to fire from. Everywhere the view
/// survives, use `.sensoryFeedback` instead.
@MainActor
enum Haptics {
    /// A local toggle the user tapped, in a menu or swipe row that closes with the tap.
    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
    /// A soft delete was committed.
    static func deleted() { impact(.medium) }
    /// A permanent delete was committed.
    static func permanentlyDeleted() { impact(.heavy) }

    private static func impact(_ style: HapticImpactStyle) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: style == .heavy ? .heavy : .medium).impactOccurred()
        #endif
    }

    private enum HapticImpactStyle { case medium, heavy }
}
