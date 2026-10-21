import SwiftUI

extension ReaderTheme {
    /// Android uses this same page (Dark #0B0B0D, OLED black), not the reader's ground.
    func accentInk(for tint: Color) -> Color {
        switch self {
        case .dark, .oled: tint.readable(on: cardBackdrop)
        case .light, .sepia: tint
        }
    }
}

private struct AccentFillKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

private struct AccentInkKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    /// The original accent, independently of the readable tint used by text.
    var accentFill: Color {
        get { self[AccentFillKey.self] }
        set { self[AccentFillKey.self] = newValue }
    }

    var accentInk: Color {
        get { self[AccentInkKey.self] }
        set { self[AccentInkKey.self] = newValue }
    }
}

struct AccentInkStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color { environment.accentInk }
}

extension ShapeStyle where Self == AccentInkStyle {
    static var accentInk: AccentInkStyle { AccentInkStyle() }
}

struct AccentFillStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color { environment.accentFill }
}

extension ShapeStyle where Self == AccentFillStyle {
    static var accentFill: AccentFillStyle { AccentFillStyle() }
}

private struct AccentFill: ViewModifier {
    @Environment(\.accentFill) private var fill

    func body(content: Content) -> some View { content.tint(fill) }
}

extension View {
    /// Install both roles wherever a screen or sheet chooses an accent.
    func accentTint(_ tint: Color, on theme: ReaderTheme) -> some View {
        let ink = theme.accentInk(for: tint)
        return self.tint(ink)
            .environment(\.accentInk, ink)
            .environment(\.accentFill, tint)
    }

    /// Opt a filled control back into the exact accent; text inherits readable tint.
    func accentFill() -> some View { modifier(AccentFill()) }
}
