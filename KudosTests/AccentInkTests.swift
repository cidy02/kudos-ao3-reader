import SwiftUI
import Testing
@testable import Kudos

@Suite(.serialized)
struct AccentInkTests {
    @Test func ao3RedReadsOnBothDarkPages() throws {
        let red = try #require(Color(hex: "#990000"))
        for theme in [ReaderTheme.dark, .oled] {
            let page = theme.cardBackdrop
            #expect(red.contrastRatio(on: page) < 4.5)
            #expect(theme.accentInk(for: red).contrastRatio(on: page) >= 4.5)
            #expect(SubjectPalette.controlColor(red, on: theme) == red)
        }
    }

    @Test func anAlreadyReadableColourIsReturnedUnchanged() {
        let readable = Color.white
        for theme in [ReaderTheme.dark, .oled] {
            #expect(readable.readable(on: theme.cardBackdrop) == readable)
            #expect(theme.accentInk(for: readable) == readable)
        }
    }

    @Test func lightAndSepiaKeepTheTintItself() throws {
        let tint = try #require(Color(hex: "#990000"))
        for theme in [ReaderTheme.light, .sepia] {
            #expect(theme.accentInk(for: tint) == tint)
        }
    }

    @Test func ao3RedMatchesAndroidsByteRoundedWhiteMix() throws {
        let red = try #require(Color(hex: "#990000"))
        // Android readableOn: original RGB + (1 - original RGB) * step / 20f,
        // rounded to sRGB bytes by Compose Color. Dark stops at step 8; OLED at 7.
        #expect(ReaderTheme.dark.cardBackdrop.hexString == "#0B0B0D")
        #expect(ReaderTheme.dark.accentInk(for: red).hexString == "#C26666")
        #expect(ReaderTheme.oled.accentInk(for: red).hexString == "#BD5959")
        let previousDarkStep = try #require(Color(hex: "#BD5959"))
        #expect(previousDarkStep.contrastRatio(on: ReaderTheme.dark.cardBackdrop) < 4.5)
    }

    @MainActor @Test func themeManagerSeparatesInkFromTheExactFill() throws {
        let defaults = UserDefaults.standard
        let keys = ["appTheme", "accentColorHex"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
        }
        let manager = ThemeManager()
        manager.accentHex = "#990000"
        for theme in ReaderTheme.allCases {
            manager.appTheme = theme
            #expect(manager.accentInk == theme.accentInk(for: manager.effectiveTint))
            if theme == .dark || theme == .oled {
                #expect(manager.effectiveTint.hexString == "#990000")
                #expect(manager.accentInk.contrastRatio(on: theme.cardBackdrop) >= 4.5)
            } else {
                #expect(manager.accentInk == manager.effectiveTint)
            }
        }
    }
}
