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
    /// The visual half of `CardPressStyle`, also used when an invisible background
    /// NavigationLink owns the native press state but its sibling draws the card.
    func cardPressed(_ isPressed: Bool) -> some View {
        modifier(CardPressEffect(isPressed: isPressed))
    }
}

/// Reports a background button's native press state without drawing its empty label.
struct CardPressStateStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
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
