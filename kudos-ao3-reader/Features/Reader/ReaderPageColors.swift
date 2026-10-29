import SwiftUI

/// The colour the reader actually paints the page with.
///
/// A custom paper colour (the well after the four theme swatches) is not a
/// `ReaderTheme` case. App chrome, the browser, and the backup's `readerTheme`
/// stay on the four presets. Body text, links, and the Readium theme (night
/// links / inverted gaiji) follow the paper's luminance, at the same 0.179
/// split `ThemeManager.label(on:)` uses — a light paper on Dark must not keep
/// the preset's night chrome.
struct ReaderPageColors: Equatable {
    var backgroundHex: String
    var textHex: String
    var background: Color
    var text: Color
    var colorScheme: ColorScheme
    var isCustom: Bool
    /// Preset whose Readium theme and link colour match this paper. A custom
    /// paper is `.light` or `.dark` from luminance; otherwise the chosen preset
    /// (including Sepia).
    var appearanceTheme: ReaderTheme

    var linkHex: String { appearanceTheme.linkHex }

    static let luminanceSplit = 0.179

    /// Readium theme and links for a page hex. The preset's own background
    /// (no well colour) keeps that preset, so Sepia is not flattened to Light.
    /// Any other hex is a custom paper and follows luminance.
    static func appearanceTheme(preset: ReaderTheme, backgroundHex: String?) -> ReaderTheme {
        guard let hex = backgroundHex,
              hex.compare(preset.backgroundHex, options: .caseInsensitive) != .orderedSame
        else { return preset }
        return resolve(theme: preset, paperHex: hex).appearanceTheme
    }

    static func resolve(theme: ReaderTheme, paperHex: String?) -> ReaderPageColors {
        if let hex = paperHex.flatMap(ReadingAnnotationColorStorage.customHex(fromRaw:)),
           let paper = Color(hex: hex) {
            let isLight = paper.relativeLuminance > luminanceSplit
            let textHex = isLight ? "#000000" : "#FFFFFF"
            let appearanceTheme: ReaderTheme = isLight ? .light : .dark
            return ReaderPageColors(
                backgroundHex: hex,
                textHex: textHex,
                background: paper,
                text: Color(hex: textHex) ?? .primary,
                colorScheme: isLight ? .light : .dark,
                isCustom: true,
                appearanceTheme: appearanceTheme
            )
        }
        return ReaderPageColors(
            backgroundHex: theme.backgroundHex,
            textHex: theme.textHex,
            background: theme.backgroundColor,
            text: theme.textColor,
            colorScheme: theme.colorScheme,
            isCustom: false,
            appearanceTheme: theme
        )
    }
}
