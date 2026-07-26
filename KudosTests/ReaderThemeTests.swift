import SwiftUI
import Testing
@testable import Kudos

struct ReaderThemeTests {
    @Test func allFourAppearancesArePresent() {
        #expect(ReaderTheme.allCases == [.light, .sepia, .dark, .oled])
    }

    @Test func oledIsTruePitchBlack() {
        #expect(ReaderTheme.oled.backgroundHex == "#000000")
        #expect(ReaderTheme.oled.backgroundColor == .black)
        #expect(ReaderTheme.oled.appBaseBackground == .black)
        #expect(ReaderTheme.oled.colorScheme == .dark)
    }

    /// The app shell's Dark background must be the exact same token as the reader's
    /// Dark background — not a separately hand-typed value that could drift.
    @Test func darkAppBackgroundReusesReaderBackgroundToken() {
        #expect(ReaderTheme.dark.appBaseBackground == ReaderTheme.dark.backgroundColor)
    }

    /// Dark's app background must no longer be the system's near-black default —
    /// it should be the reader's lighter background instead.
    @Test func darkAppBackgroundIsLighterThanOLEDBlack() {
        #expect(ReaderTheme.dark.appBaseBackground != .black)
        #expect(ReaderTheme.dark.backgroundHex == "#16161A")
    }

    /// Cards/rows must stay visually distinct from their backdrop in both dark
    /// appearances, so content never reads as an undifferentiated black rectangle.
    @Test func darkAndOLEDKeepElevatedSurfacesDistinctFromTheBase() {
        for theme in [ReaderTheme.dark, .oled] {
            #expect(theme.appElevatedBackground != nil)
            #expect(theme.appElevatedBackground != theme.appBaseBackground)
        }
    }

    @Test func lightHasNoCustomAppSurfaces() {
        #expect(ReaderTheme.light.appBaseBackground == nil)
        #expect(ReaderTheme.light.appElevatedBackground == nil)
    }

    // MARK: - Letter-spacing clamp (UI-9)

    /// Readium (iOS) only accepts non-negative letter-spacing
    /// (`ReadiumReaderStyleMapper.preferences` clamps with `max(0, ...)`), and
    /// `letterSpacingRange` is now non-negative too — so a negative value can only
    /// reach the CSS renderer from a legacy/hand-edited backup, which
    /// `KudosBackupSettings` restores without range validation. The renderer must
    /// still clamp it, or macOS would render what iOS structurally cannot.
    @Test func negativeLetterSpacingIsClampedOutOfRenderedCSS() {
        let style = ReaderTextStyle(customize: true, letterSpacing: -0.02)
        let css = ReaderStylesheet.css(theme: .light, font: ReaderFontOption.builtIns[0], style: style)
        #expect(!css.contains("letter-spacing"))
    }

    @Test func zeroLetterSpacingEmitsNoRule() {
        let style = ReaderTextStyle(customize: true, letterSpacing: 0)
        let css = ReaderStylesheet.css(theme: .light, font: ReaderFontOption.builtIns[0], style: style)
        #expect(!css.contains("letter-spacing"))
    }

    @Test func positiveLetterSpacingStillRenders() {
        let style = ReaderTextStyle(customize: true, letterSpacing: 0.04)
        let css = ReaderStylesheet.css(theme: .light, font: ReaderFontOption.builtIns[0], style: style)
        #expect(css.contains("letter-spacing: 0.04em !important;"))
    }

    /// The slider range must not advertise a half the renderers structurally
    /// discard — otherwise the control moves and nothing changes.
    @Test func letterSpacingRangeOffersOnlyValuesThatCanRender() {
        #expect(ReaderTextStyle.letterSpacingRange.lowerBound == 0)
    }
}
