import SwiftUI

/// One of the six Appearance accents. Dark and OLED share `darkInkHex`; anything
/// else — a custom colour, or a legacy value such as the old `#990000` — takes
/// `Color.readable(on:)` instead of a named step.
struct AppAccent: Identifiable, Equatable {
    let name: String
    let fillHex: String
    let darkInkHex: String

    var id: String { fillHex }
    var isDefault: Bool { fillHex == Self.ao3Red.fillHex }

    static let ao3Red = AppAccent(name: "AO3 Red", fillHex: "#821019", darkInkHex: "#EE8A93")
    static let plum = AppAccent(name: "Plum", fillHex: "#7B2D6B", darkInkHex: "#D88BC7")
    static let inkBlue = AppAccent(name: "Ink Blue", fillHex: "#24508F", darkInkHex: "#7FA6E8")
    static let deepTeal = AppAccent(name: "Deep Teal", fillHex: "#11707A", darkInkHex: "#5CC3CC")
    static let forest = AppAccent(name: "Forest", fillHex: "#2F6B4F", darkInkHex: "#7CC59E")
    static let ochre = AppAccent(name: "Ochre", fillHex: "#9A5B00", darkInkHex: "#E7A84B")

    static let all: [AppAccent] = [ao3Red, plum, inkBlue, deepTeal, forest, ochre]

    /// Case-insensitive `#RRGGBB` match against the fill, not the text step.
    static func named(hex: String) -> AppAccent? {
        all.first { $0.fillHex.caseInsensitiveCompare(hex) == .orderedSame }
    }
}

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
        didSet {
            store(appTheme, forKey: "appTheme")
            // While the reader follows the app, this *is* picking a reader preset.
            if matchAppAndReader { readerCustomPaperHex = nil }
        }
    }

    /// When on, the reader mirrors the app theme.
    var matchAppAndReader: Bool {
        didSet { UserDefaults.standard.set(matchAppAndReader, forKey: Self.matchKey) }
    }

    /// The reader's own theme, used only while unlinked.
    private var readerThemeStored: ReaderTheme {
        didSet { store(readerThemeStored, forKey: "readerTheme") }
    }

    /// The reader's accent as `#RRGGBB`. `didSet` does not run from `init`, so a
    /// missing `accentColorHex` stays missing until they pick a colour.
    var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: Self.accentKey) }
    }

    /// Default accent when nothing is stored. A stored value is never rewritten
    /// to this.
    nonisolated static let ao3Red = AppAccent.ao3Red.fillHex
    /// The pre-2026-10-29 default. Old builds, and the current Android build,
    /// write this when the reader never chose a colour, so it carries no choice.
    nonisolated static let legacyUnchosenAccentHex = "#990000"

    nonisolated static func isLegacyUnchosenAccent(_ hex: String) -> Bool {
        hex.caseInsensitiveCompare(legacyUnchosenAccentHex) == .orderedSame
    }
    private static let matchKey = "matchAppReaderTheme"
    nonisolated private static let accentKey = "accentColorHex"
    /// Reader-only paper colour from the theme well. Not a `ReaderTheme` raw
    /// value, and not written into `.kudosbackup` (the backup has no field for it).
    static let paperKey = "readerCustomPaperHex"

    /// Exact page colour (`#RRGGBB`), or `nil` while a preset theme is in use.
    var readerCustomPaperHex: String? {
        didSet { storePaperHex() }
    }

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
        // `didSet` does not run from `init`, so a stored custom paper survives
        // launch. An unreadable value is dropped here rather than left to fight
        // the preset.
        let storedPaper = ReadingAnnotationColorStorage.customHex(
            fromRaw: defaults.string(forKey: Self.paperKey) ?? ""
        )
        readerCustomPaperHex = storedPaper
        if defaults.string(forKey: Self.paperKey) != storedPaper {
            if let storedPaper {
                defaults.set(storedPaper, forKey: Self.paperKey)
            } else {
                defaults.removeObject(forKey: Self.paperKey)
            }
        }
        // `didSet` does not run from `init`, so an absent accent is not written.
        accentHex = defaults.string(forKey: Self.accentKey) ?? Self.ao3Red
    }

    /// The user's accent colour (falls back to AO3 red if the stored hex is bad).
    var accentColor: Color {
        Color(hex: accentHex) ?? Color(hex: Self.ao3Red)!
    }

    /// The exact control fill for the whole app: Sepia keeps its cohesive warm
    /// brown; Light, Dark and OLED use the reader's accent.
    var effectiveTint: Color {
        SubjectPalette.controlColor(appTheme.appTint ?? accentColor, on: appTheme)
    }

    /// Text, glyphs and text-button labels; filled controls keep `effectiveTint`.
    var accentInk: Color { appTheme.accentInk(for: effectiveTint) }

    /// The palette every *scope*-level surface in the redesign draws from — the
    /// Account hub, the pushed Home and Library sections, the inbox, Writing.
    ///
    /// Scope-level screens use the reader's accent (or Sepia's warm brown) for
    /// both identity and wash. Work-, fandom-, collection-, and queue-scoped
    /// screens still use their subject colour for identity and wash, but not for
    /// app controls.
    var scopePalette: SubjectPalette {
        SubjectPalette(color: effectiveTint, theme: appTheme)
    }

    /// A foreground guaranteed to stay readable on top of `effectiveTint` — the
    /// color controls actually render with (Sepia's warm brown, or the accent).
    var onEffectiveTint: Color {
        Self.label(on: effectiveTint)
    }

    /// The one app-control tint for a theme. Subject palettes call this too so a
    /// screen's identity colour never leaks into buttons, toggles, pills or chrome.
    /// Reads the stored accent directly: this is not a view, so it cannot observe
    /// `accentHex`. Screens that must refresh use `effectiveTint`.
    static func appTint(for theme: ReaderTheme) -> Color {
        let hex = UserDefaults.standard.string(forKey: accentKey) ?? ao3Red
        let accent = Color(hex: hex) ?? Color(hex: ao3Red)!
        return SubjectPalette.controlColor(theme.appTint ?? accent, on: theme)
    }

    /// Stores a picked colour. A value whose hex is a named fill is that accent.
    func setAccent(_ color: Color) {
        accentHex = color.hexString
    }

    /// Restores the default AO3-red accent.
    func resetAccent() {
        accentHex = Self.ao3Red
    }

    /// Black or white, whichever has the higher contrast on `fill` (WCAG: the
    /// two cross at relative luminance ~0.179). The old 0.45 cut left white on
    /// Dark's lifted pink accent at ~2.8:1.
    static func label(on fill: Color) -> Color {
        fill.relativeLuminance > 0.179 ? .black : .white
    }

    /// The theme the reader renders with — mirrors the app theme while linked, so
    /// changing one changes the other.
    var readerTheme: ReaderTheme {
        get { matchAppAndReader ? appTheme : readerThemeStored }
        set {
            // A preset replaces a paper chosen in the well. Assigning
            // `readerThemeStored` in `init` does not come through here, so a
            // stored paper is not wiped on launch.
            readerCustomPaperHex = nil
            if matchAppAndReader { appTheme = newValue } else { readerThemeStored = newValue }
        }
    }

    /// Page colour for both readers: the preset, or the well's paper.
    var readerPage: ReaderPageColors {
        ReaderPageColors.resolve(theme: readerTheme, paperHex: readerCustomPaperHex)
    }

    /// Chrome rules for the page that's actually showing. A custom paper is
    /// light or dark from its luminance; it is not Sepia and not OLED.
    var readerChromeTheme: ReaderTheme {
        let page = readerPage
        guard page.isCustom else { return readerTheme }
        return page.colorScheme == .dark ? .dark : .light
    }

    private func store(_ theme: ReaderTheme, forKey key: String) {
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }

    private func storePaperHex() {
        if let readerCustomPaperHex {
            UserDefaults.standard.set(readerCustomPaperHex, forKey: Self.paperKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.paperKey)
        }
    }
}
