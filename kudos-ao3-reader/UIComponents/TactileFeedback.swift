import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Press feedback for tappable cards and rows: a slight dim and shrink while the finger is
/// down, colours untouched (unlike the system accent tint). Respects Reduce Motion.
struct CardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardPressStyle {
    static var cardPress: CardPressStyle { CardPressStyle() }
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
