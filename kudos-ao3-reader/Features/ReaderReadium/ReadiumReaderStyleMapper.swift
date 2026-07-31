import Foundation
#if os(iOS)
import ReadiumNavigator
import ReadiumShared

/// Converts the app's point/em-based reader settings into Readium's percentage
/// and factor-based preferences. Keeping the calibration here makes the mapping
/// testable and prevents the SwiftUI view from accumulating magic numbers.
enum ReadiumReaderStyleMapper {
    /// Readium CSS starts from the browser's 16 px root size.
    private static let readiumBaseFontSize = 16.0

    static func preferences(
        style: ReaderTextStyle,
        theme: ReaderTheme,
        fontFamily: FontFamily?,
        readingMode: ReadingMode,
        columnCount: ColumnCount?
    ) -> EPUBPreferences {
        EPUBPreferences(
            backgroundColor: ReadiumNavigator.Color(hex: theme.backgroundHex),
            // Only set a column count in paged mode. Forcing `.one` in scroll mode makes
            // Readium lay the text out in screen-height columns (page breaks mid-text +
            // dead space top/bottom) instead of one continuous flow.
            columnCount: readingMode == .scroll ? nil : columnCount,
            fontFamily: fontFamily,
            // Legacy CSS emits the selected point size as px. Readium expects a
            // percentage of its 16 px root, so 18 pt becomes 112.5%.
            fontSize: max(0.1, style.fontSizePt / readiumBaseFontSize),
            // Legacy bold is 600. Readium multiplies this value by its 400
            // normal weight, so 1.5 produces the same result.
            fontWeight: style.bold ? 1.5 : nil,
            // Readium CSS divides this preference by two before emitting rem.
            // Compensate so the positive half of the app's em slider is exact.
            letterSpacing: max(0, style.letterSpacing * 2),
            lineHeight: style.lineHeight,
            // The navigator configuration uses a 1 px base gutter, turning
            // Readium's factor into the app's absolute point/px margin.
            pageMargins: max(0, style.margin),
            // The legacy reader always overrides the EPUB's base typography.
            // Advanced Readium settings require publisher styles to be off.
            publisherStyles: false,
            scroll: readingMode == .scroll,
            textAlign: style.justify ? .justify : nil,
            textColor: ReadiumNavigator.Color(hex: theme.textHex),
            theme: theme.readiumTheme,
            wordSpacing: max(0, style.wordSpacing)
        )
    }

    static var readingSystemProperties: CSSRSProperties {
        CSSRSProperties(pageGutter: CSSPxLength(1))
    }

    static func fontFamily(for option: ReaderFontOption) -> FontFamily? {
        if option.isCustom {
            // The selection id contains ":" and ".". Prefix it with a space-
            // containing family name so Readium quotes it in the CSS custom
            // property instead of emitting an invalid bare CSS identifier.
            return FontFamily(rawValue: "Kudos User Font \(option.id)")
        }
        return fontStack(in: option.cssFamily).first
    }

    /// Declares both imported files and the fallback stacks for the built-in
    /// choices. Readium otherwise emits only the first family name, losing the
    /// legacy reader's carefully chosen fallbacks.
    static func fontFamilyDeclarations(
        options: [ReaderFontOption]
    ) -> [AnyHTMLFontFamilyDeclaration] {
        options.compactMap { option in
            guard let family = fontFamily(for: option) else { return nil }
            let stack = fontStack(in: option.cssFamily)
            let alternates = stack.filter { $0 != family }
            let faces: [CSSFontFace] = if let file = option.customFileURL?.fileURL {
                // Readium serves imported files through a separate custom-scheme
                // host. Preloading that URL trips WebKit's cross-origin check;
                // allowing the @font-face rule to request it normally works.
                [CSSFontFace(file: file)]
            } else {
                []
            }
            return CSSFontFamilyDeclaration(
                fontFamily: family,
                alternates: alternates,
                fontFaces: faces
            ).eraseToAnyHTMLFontFamilyDeclaration()
        }
    }

    private static func fontStack(in cssFamily: String) -> [FontFamily] {
        cssFamily
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            }
            .filter { !$0.isEmpty }
            .map(FontFamily.init(rawValue:))
    }
}
#endif
