import Foundation
import Testing
@testable import Kudos

struct BrowserThemeTests {
    @Test func stylesOnlyOfficialAO3Hosts() {
        #expect(BrowserThemeStyle.isAO3URL(URL(string: "https://archiveofourown.org/works")))
        #expect(BrowserThemeStyle.isAO3URL(URL(string: "https://download.archiveofourown.org/file")))
        #expect(!BrowserThemeStyle.isAO3URL(URL(string: "https://archiveofourown.org.example.com")))
        #expect(!BrowserThemeStyle.isAO3URL(URL(string: "https://example.com")))
    }

    @Test func lightUsesNativeSkinWhileSepiaAndDarkInjectPalettes() {
        #expect(BrowserThemeStyle.css(for: .light) == nil)
        #expect(BrowserThemeStyle.css(for: .sepia)?.contains("#FBF0D9") == true)
        #expect(BrowserThemeStyle.css(for: .sepia)?.contains("color-scheme: light") == true)
        #expect(BrowserThemeStyle.css(for: .dark)?.contains("#16161A") == true)
        #expect(BrowserThemeStyle.css(for: .dark)?.contains("color-scheme: dark") == true)
    }

    @Test func oledInjectsATrueBlackPalette() {
        let css = BrowserThemeStyle.css(for: .oled)
        #expect(css?.contains("#000000") == true)
        #expect(css?.contains("color-scheme: dark") == true)
        // Distinct from Dark's palette background, even though both are "dark".
        #expect(css != BrowserThemeStyle.css(for: .dark))
    }
}
