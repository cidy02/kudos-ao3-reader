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
        twoPageSpread: Bool,
        backgroundHex: String? = nil,
        textHex: String? = nil,
        pageTurn: ReaderPageTurnStyle = .slide,
        bookPose: Bool = false,
        tabletopPose: Bool = false
    ) -> EPUBPreferences {
        EPUBPreferences(
            backgroundColor: ReadiumNavigator.Color(hex: backgroundHex ?? theme.backgroundHex),
            // Only set a column count in paged mode. Forcing `.one` in scroll mode makes
            // Readium lay the text out in screen-height columns (page breaks mid-text +
            // dead space top/bottom) instead of one continuous flow.
            // Book pose forces `.two` so the columns clear the hinge. `.auto` would
            // drop to one column at a large size and draw straight across the fold.
            // The stored two-page setting is an input here; this function never writes it.
            columnCount: columnCount(
                readingMode: readingMode,
                twoPageSpread: twoPageSpread,
                bookPose: bookPose,
                tabletopPose: tabletopPose
            ),
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
            // Raw values match `PageTransition`. An unknown string cannot
            // appear here; the fallback keeps a turn on the historical slide.
            pageTransition: PageTransition(rawValue: pageTurn.rawValue) ?? .slide,
            // The legacy reader always overrides the EPUB's base typography.
            // Advanced Readium settings require publisher styles to be off.
            publisherStyles: false,
            scroll: readingMode == .scroll,
            textAlign: style.justify ? .justify : nil,
            textColor: ReadiumNavigator.Color(hex: textHex ?? theme.textHex),
            theme: ReaderPageColors.appearanceTheme(
                preset: theme, backgroundHex: backgroundHex
            ).readiumTheme,
            wordSpacing: max(0, style.wordSpacing)
        )
    }

    /// Book pose forces two columns. Tabletop forces one, even when the stored
    /// two-page setting is on. Flat and cover follow that setting, and only
    /// when the layout is already wide (`twoPageSpread`). Scroll never sets a count.
    static func columnCount(
        readingMode: ReadingMode,
        twoPageSpread: Bool,
        bookPose: Bool,
        tabletopPose: Bool
    ) -> ColumnCount? {
        guard readingMode != .scroll else { return nil }
        if bookPose { return .two }
        if tabletopPose { return .one }
        return twoPageSpread ? .auto : .one
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
