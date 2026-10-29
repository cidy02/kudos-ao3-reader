import SwiftUI

/// The colour the reader actually paints the page with.
///
/// A custom paper colour (the well after the four theme swatches) is not a
/// `ReaderTheme` case. App chrome, the browser, and the backup's `readerTheme`
/// stay on the four presets. Body text is black or white from the paper's
/// luminance, at the same 0.179 split `ThemeManager.label(on:)` uses.
struct ReaderPageColors: Equatable {
    var backgroundHex: String
    var textHex: String
    var background: Color
    var text: Color
    var colorScheme: ColorScheme
    var isCustom: Bool

    static let luminanceSplit = 0.179

    static func resolve(theme: ReaderTheme, paperHex: String?) -> ReaderPageColors {
        if let hex = paperHex.flatMap(ReadingAnnotationColorStorage.customHex(fromRaw:)),
           let paper = Color(hex: hex) {
            let textHex = paper.relativeLuminance > luminanceSplit ? "#000000" : "#FFFFFF"
            return ReaderPageColors(
                backgroundHex: hex,
                textHex: textHex,
                background: paper,
                text: Color(hex: textHex) ?? .primary,
                colorScheme: paper.relativeLuminance > luminanceSplit ? .light : .dark,
                isCustom: true
            )
        }
        return ReaderPageColors(
            backgroundHex: theme.backgroundHex,
            textHex: theme.textHex,
            background: theme.backgroundColor,
            text: theme.textColor,
            colorScheme: theme.colorScheme,
            isCustom: false
        )
    }
}
