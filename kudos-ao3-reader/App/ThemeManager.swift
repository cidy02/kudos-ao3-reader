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

    /// AO3's signature dark red — the fixed app accent.
    static let ao3Red = "#990000"
    private static let matchKey = "matchAppReaderTheme"
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
    }

    /// The exact control fill for the whole app: Sepia keeps its cohesive warm
    /// brown; Light/Dark/OLED use AO3 red.
    var effectiveTint: Color {
        Self.appTint(for: appTheme)
    }

    /// Text, glyphs and text-button labels; filled controls keep `effectiveTint`.
    var accentInk: Color { appTheme.accentInk(for: effectiveTint) }

    /// The palette every *scope*-level surface in the redesign draws from — the
    /// Account hub, the pushed Home and Library sections, the inbox, Writing.
    ///
    /// Scope-level screens use AO3 red (or Sepia's warm brown) for both identity
    /// and wash. Work-, fandom-, collection-, and queue-scoped screens still use
    /// their subject colour for identity and wash, but not for app controls.
    var scopePalette: SubjectPalette {
        SubjectPalette(color: effectiveTint, theme: appTheme)
    }

    /// A foreground guaranteed to stay readable on top of `effectiveTint` — the
    /// color controls actually render with (Sepia's fixed warm brown, or AO3 red).
    var onEffectiveTint: Color {
        Self.label(on: effectiveTint)
    }

    /// The one app-control tint for a theme. Subject palettes call this too so a
    /// screen's identity colour never leaks into buttons, toggles, pills or chrome.
    static func appTint(for theme: ReaderTheme) -> Color {
        SubjectPalette.controlColor(
            theme.appTint ?? Color(hex: ao3Red)!,
            on: theme
        )
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
