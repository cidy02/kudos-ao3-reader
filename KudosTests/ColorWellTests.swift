import SwiftUI
import Testing
@testable import Kudos

struct ColorWellTests {
    @Test func presetNamesAreNotCustomColours() {
        for color in ReadingAnnotationColor.allCases {
            #expect(ReadingAnnotationColorStorage.customHex(fromRaw: color.rawValue) == nil)
            #expect(ReadingAnnotationColorStorage.normalizedRaw(color.rawValue) == color.rawValue)
        }
    }

    @Test func customHexFoldsCaseAndRejectsShortOrJunkValues() {
        #expect(ReadingAnnotationColorStorage.customHex(fromRaw: "#abc") == nil)
        #expect(ReadingAnnotationColorStorage.customHex(fromRaw: "#aabbcc") == "#AABBCC")
        #expect(ReadingAnnotationColorStorage.customHex(fromRaw: "  #aabbcc ") == "#AABBCC")
        #expect(ReadingAnnotationColorStorage.customHex(fromRaw: "#AABBCC") == "#AABBCC")
        #expect(ReadingAnnotationColorStorage.customHex(fromRaw: "aabbcc") == nil)
        #expect(ReadingAnnotationColorStorage.customHex(fromRaw: "#12") == nil)
        #expect(ReadingAnnotationColorStorage.customHex(fromRaw: "nope") == nil)
    }

    @Test func unrecognizedRawFallsBackToYellow() {
        #expect(ReadingAnnotationColorStorage.normalizedRaw("#abc") == ReadingAnnotationColor.yellow.rawValue)
        #expect(ReadingAnnotationColorStorage.normalizedRaw("nope") == ReadingAnnotationColor.yellow.rawValue)
        #expect(ReadingAnnotationColorStorage.normalizedRaw("#aabbcc") == "#AABBCC")
    }

    @Test func lightPaperGetsBlackText() {
        let page = ReaderPageColors.resolve(theme: .dark, paperHex: "#FFFFFF")
        #expect(page.isCustom)
        #expect(page.backgroundHex == "#FFFFFF")
        #expect(page.textHex == "#000000")
        #expect(page.colorScheme == .light)
    }

    @Test func darkPaperGetsWhiteText() {
        let page = ReaderPageColors.resolve(theme: .light, paperHex: "#000000")
        #expect(page.isCustom)
        #expect(page.textHex == "#FFFFFF")
        #expect(page.colorScheme == .dark)
    }

    @Test func garbagePaperHexKeepsThePreset() {
        let page = ReaderPageColors.resolve(theme: .sepia, paperHex: "nope")
        #expect(!page.isCustom)
        #expect(page.backgroundHex == ReaderTheme.sepia.backgroundHex)
        #expect(page.textHex == ReaderTheme.sepia.textHex)
        #expect(page.colorScheme == .light)
    }

    @Test func stylesheetUsesPaperAndKeepsThePresetLinkColour() {
        let css = ReaderStylesheet.css(
            theme: .light,
            font: ReaderFontOption.builtIns[0],
            pageBackgroundHex: "#112233",
            pageTextHex: "#FFFFFF"
        )
        #expect(css.contains("background-color: #112233"))
        #expect(css.contains("color: #FFFFFF"))
        #expect(css.contains(ReaderTheme.light.linkHex))
        #expect(!css.contains("background-color: \(ReaderTheme.light.backgroundHex)"))
    }
}
