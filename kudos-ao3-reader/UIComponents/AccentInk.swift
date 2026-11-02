import SwiftUI

extension ReaderTheme {
    /// Android uses this same page (Dark #0B0B0D, OLED black), not the reader's ground.
    /// A named accent uses its one Dark/OLED step on both of those themes. A custom
    /// colour, and any legacy hex that is not a named fill, still mixes toward white.
    func accentInk(for tint: Color) -> Color {
        switch self {
        case .dark, .oled:
            if let named = AppAccent.all.first(where: { Color(hex: $0.fillHex) == tint })
                ?? AppAccent.named(hex: tint.hexString),
               let step = Color(hex: named.darkInkHex) {
                return step
            }
            return tint.readable(on: cardBackdrop)
        case .sepia:
            // Sepia text/glyph ink darkens the control tint to the theme's dark warm brown
            // so contrast on tan chip/button fills is >= 4.5:1 (P3 10).
            return Color(red: 0.34, green: 0.22, blue: 0.08)
        case .light:
            return tint
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

private struct AccentInkModifier: ViewModifier {
    @Environment(\.accentInk) private var ink

    func body(content: Content) -> some View { content.tint(ink) }
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

    /// Opt a slider or progress fill into the lighter accent ink tint.
    func accentInk() -> some View { modifier(AccentInkModifier()) }
}

#if os(iOS)
/// Scope sheets choose the app palette instead of inheriting their presenter's subject colour.
struct ScopeSurfaceAccent: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager

    func body(content: Content) -> some View {
        content.accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
    }
}
#endif
