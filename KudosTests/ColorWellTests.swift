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

    @Test func aPresetCancelsAPendingDragSoFlushReportsNothing() throws {
        let green = try #require(Color(hex: "#00FF00"))
        let blue = try #require(Color(hex: "#0000FF"))
        var machine = CustomColorWellMachine(committedHex: "#FF0000")
        machine.noteDrag(green)
        machine.adoptExternal(blue)
        #expect(machine.flush() == nil)
        #expect(machine.committedHex == "#0000FF")
        #expect(machine.pending == nil)
    }

    @Test func flushReportsThePendingColourOnce() throws {
        let green = try #require(Color(hex: "#00FF00"))
        var machine = CustomColorWellMachine(committedHex: "#FF0000")
        machine.noteDrag(green)
        #expect(machine.flush()?.hexString == "#00FF00")
        #expect(machine.committedHex == "#00FF00")
        #expect(machine.flush() == nil)
    }

    @Test func flushIgnoresADragThatMatchesTheCommittedColour() throws {
        let red = try #require(Color(hex: "#FF0000"))
        var machine = CustomColorWellMachine(committedHex: "#FF0000")
        machine.noteDrag(red)
        #expect(machine.flush() == nil)
    }

    @Test func discardDropsThePendingColourAndDisappearDoesNotFlush() throws {
        let green = try #require(Color(hex: "#00FF00"))
        var machine = CustomColorWellMachine(committedHex: "#FF0000")
        machine.noteDrag(green)
        machine.discard()
        #expect(machine.discarded)
        #expect(machine.pending == nil)
        #expect(machine.flush() == nil)
        #expect(machine.committedHex == "#FF0000")
    }

    @Test func discardThenANewDragIsIgnored() throws {
        let green = try #require(Color(hex: "#00FF00"))
        var machine = CustomColorWellMachine(committedHex: "#FF0000")
        machine.discard()
        machine.noteDrag(green)
        #expect(machine.flush() == nil)
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
