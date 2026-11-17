import SwiftUI

extension ReaderTheme {
    /// Mixes against `cardBackdrop` — the app's page, not the reader's ground.
    /// A named accent uses its one Dark/OLED step on both of those themes. A custom
    /// colour, and any legacy hex that is not a named fill, still mixes toward white.
    ///
    /// **Android parity is currently broken here.** Both platforms used to mix against
    /// Dark #0B0B0D; `4ab92874` unified iOS's two dark page colours onto #16161B
    /// (`appBaseBackground`) and Android's `WorkStats.kt` page was not moved with it.
    /// The named accents' Dark steps are fixed hexes, so they are unaffected; only a
    /// custom or legacy tint can now resolve to a different step on the two platforms.
    /// `AccentInkTests.legacyRedMatchesAndroidsByteRoundedWhiteMix` still passes —
    /// #C26666 clears 4.5:1 on both grounds — so the divergence is latent, not visible
    /// today. Close it by moving Android's page, not by re-splitting iOS's.
    func accentInk(for tint: Color) -> Color {
        switch self {
        case .dark, .oled:
            if let named = AppAccent.named(hex: tint.hexString),
               let step = Color(hex: named.darkInkHex) {
                return step
            }
            return tint.readable(on: cardBackdrop)
        case .light, .sepia:
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

private struct SecondaryInkKey: EnvironmentKey {
    static let defaultValue: Color? = nil
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

    /// Theme-routed secondary ink (`nil` keeps the system's `.secondary`).
    var secondaryInk: Color? {
        get { self[SecondaryInkKey.self] }
        set { self[SecondaryInkKey.self] = newValue }
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

/// Secondary text ink routed through the theme: Sepia's warm brown-grey when
/// installed via `accentTint(_:on:)`, or the untouched system `.secondary`
/// everywhere else (Light, Dark, OLED).
struct SecondaryInkStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        if let color = Self.themeInk(environment.secondaryInk, scheme: environment.colorScheme) {
            return AnyShapeStyle(color)
        }
        return AnyShapeStyle(.secondary)
    }

    /// Sepia's brown is measured against its cream page; a card that forces a dark
    /// scheme (the cover-wearing cards) keeps the system grey, which stays readable
    /// there (seen 2026-11-17: the brown byline measured 2.6:1 on the Resume card).
    static func themeInk(_ ink: Color?, scheme: ColorScheme) -> Color? {
        scheme == .light ? ink : nil
    }
}

extension ShapeStyle where Self == SecondaryInkStyle {
    static var secondaryInk: SecondaryInkStyle { SecondaryInkStyle() }
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
            .environment(\.secondaryInk, theme.appSecondaryInk)
    }

    /// Opt a filled control back into the exact accent; text inherits readable tint.
    func accentFill() -> some View { modifier(AccentFill()) }
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
