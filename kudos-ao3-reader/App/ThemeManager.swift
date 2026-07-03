import SwiftUI

/// Central theme state for the whole app. `appTheme` themes the app (pages, menus,
/// sheets, navigation bars); the reader can follow it or use its own theme.
///
/// By default the two are linked (`matchAppAndReader`), so changing either changes
/// both — pick a theme in Settings or in the reader and the whole app follows. Turn
/// the match off to give the reader an independent theme. Backed by `UserDefaults`,
/// reusing the existing `readerTheme` key so saved preferences carry over.
@MainActor @Observable
final class ThemeManager {
    /// Whole-app theme.
    var appTheme: ReaderTheme {
        didSet { store(appTheme, forKey: "appTheme") }
    }

    /// When on, the reader mirrors the app theme.
    var matchAppAndReader: Bool {
        didSet { UserDefaults.standard.set(matchAppAndReader, forKey: Self.matchKey) }
    }

    /// The reader's own theme, used only while unlinked.
    private var readerThemeStored: ReaderTheme {
        didSet { store(readerThemeStored, forKey: "readerTheme") }
    }

    /// The user's chosen accent colour as a `#RRGGBB` hex string; defaults to AO3 red.
    var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: Self.accentKey) }
    }

    /// AO3's signature dark red — the default app accent.
    static let ao3Red = "#990000"
    private static let matchKey = "matchAppReaderTheme"
    private static let accentKey = "accentColorHex"

    init() {
        let defaults = UserDefaults.standard
        let storedReader = ReaderTheme(rawValue: defaults.string(forKey: "readerTheme") ?? "") ?? .light
        // Seed the (new) app theme from the existing reader theme on first launch so
        // an upgrading user keeps the look they already had.
        if let raw = defaults.string(forKey: "appTheme"), let theme = ReaderTheme(rawValue: raw) {
            appTheme = theme
        } else {
            appTheme = storedReader
        }
        matchAppAndReader = (defaults.object(forKey: Self.matchKey) as? Bool) ?? true
        readerThemeStored = storedReader
        accentHex = defaults.string(forKey: Self.accentKey) ?? Self.ao3Red
    }

    /// The user's accent colour (falls back to AO3 red if the stored hex is bad).
    var accentColor: Color {
        Color(hex: accentHex) ?? Color(hex: Self.ao3Red)!
    }

    /// The control/link tint for the whole app: Sepia keeps its cohesive warm
    /// brown; Light/Dark use the user's accent (default AO3 red).
    var effectiveTint: Color {
        appTheme.appTint ?? accentColor
    }

    /// Sets the accent from a picked colour (stored as hex).
    func setAccent(_ color: Color) {
        accentHex = color.hexString
    }

    /// Restores the default AO3-red accent.
    func resetAccent() {
        accentHex = Self.ao3Red
    }

    /// The theme the reader renders with — mirrors the app theme while linked, so
    /// changing one changes the other.
    var readerTheme: ReaderTheme {
        get { matchAppAndReader ? appTheme : readerThemeStored }
        set {
            if matchAppAndReader { appTheme = newValue } else { readerThemeStored = newValue }
        }
    }

    private func store(_ theme: ReaderTheme, forKey key: String) {
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }
}
