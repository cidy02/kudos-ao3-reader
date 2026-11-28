import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Kudos

/// Tests for T-579f PDF conversion fixes:
/// - leading front matter named `"Preface"` on the plain-text path,
/// - stacked edge chrome (browser print header + footer) stripped without touching story refrains,
/// - echoed chapter headings after decorative dividers not splitting stub chapters,
/// - unnumbered visually-styled chapter headings splitting on the plain-text path,
/// - multi-sentence prose subtitles rejected as chapter headings while titles with abbreviations stay valid,
/// - bottom-margin page numbers drawn before body text not stealing mid-page horizontal rules.
struct PDFConversionT579fTests {
    private enum PDFTestError: Error { case contextUnavailable }

    private struct DrawLine {
        let text: String
        let fontName: String
        let fontSize: CGFloat
        let centered: Bool
        let yPosition: CGFloat
    }

    private func makeCustomPDF(pages: [[DrawLine]], extraDraw: ((Int, CGContext) -> Void)? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-t579f-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [:] as CFDictionary) else {
            throw PDFTestError.contextUnavailable
        }
        for (pageIndex, lines) in pages.enumerated() {
            context.beginPage(mediaBox: &box)
            context.setFillColor(gray: 0, alpha: 1)
            context.setStrokeColor(gray: 0.4, alpha: 1)
            context.setLineWidth(1)
            extraDraw?(pageIndex, context)
            for item in lines {
                let font = CTFontCreateWithName(item.fontName as CFString, item.fontSize, nil)
                let attributed = NSAttributedString(
                    string: item.text,
                    attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                )
                let ctLine = CTLineCreateWithAttributedString(attributed)
                let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
                let xOrigin: CGFloat = item.centered ? (box.width - width) * 0.5 : 72
                context.textPosition = CGPoint(x: xOrigin, y: item.yPosition)
                CTLineDraw(ctLine, context)
            }
            context.endPage()
        }
        context.closePDF()
        return url
    }

    private func regular(_ text: String, y: CGFloat, centered: Bool = false) -> DrawLine {
        DrawLine(text: text, fontName: "Georgia", fontSize: 12, centered: centered, yPosition: y)
    }

    private func boldHeading(_ text: String, y: CGFloat, size: CGFloat = 14) -> DrawLine {
        DrawLine(text: text, fontName: "Georgia-Bold", fontSize: size, centered: true, yPosition: y)
    }

    private func titleLine(_ text: String, y: CGFloat) -> DrawLine {
        DrawLine(text: text, fontName: "Georgia", fontSize: 18, centered: true, yPosition: y)
    }

    // MARK: - Front matter & footers

    @Test func leadingFrontMatterOnPlainTextPathIsNamedPrefaceAndFormatsCalibreMetadata() throws {
        let url = try makeCustomPDF(pages: [
            [
                titleLine("The Red Bell", y: 720),
                regular("Story: The Red Bell", y: 688),
                regular("Storylink: https://example.org/works/1001", y: 668),
                regular("Category: Salt Orchard Ballads", y: 648),
                regular("Genre: Friendship/Horror", y: 628),
                regular("Author: R. Pell", y: 608),
                regular("Rating: T", y: 588),
                regular("Status: Complete", y: 568),
                regular("Words: 889", y: 548),
                regular("Summary: Sera returns to the Salt Orchard before the tide turns.", y: 528)
            ],
            [
                boldHeading("Part One", y: 720),
                regular("Sera, Lina, and Maren met at the orchard wall when the second bell rang across", y: 680),
                regular("the wet salt terrace and the harbor fog drifted past the white iron gate.", y: 664),
                regular("Nobody spoke until the lantern at the lower landing went out for the night.", y: 632)
            ]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Untitled")
        try #require(result.chapters.count == 2)
        #expect(result.chapters[0].title == "Preface")
        #expect(result.chapters[1].title == "Part One")
        #expect(result.chapters[0].bodyXHTML.contains("<dt>Rating:</dt>"))
        #expect(result.chapters[0].bodyXHTML.contains("Teen And Up Audiences"))
        #expect(result.chapters[1].bodyXHTML.contains("orchard wall"))
    }

    @Test func stackedRepeatedEdgeChromeIsRemovedWhileRepeatedStoryRefrainSurvives() {
        let browserHeader = "11/27/26, 8:19 PM\nCovering Our Tracks by Bells-n-Akira"
        let browserFooter = "file:///Users/reader/story.html"
        let refrain = "And the light remains."

        let pages = [
            ["Page one prose opens at dusk.", refrain, browserHeader, browserFooter, "1"],
            ["Page two prose follows the road.", refrain, browserHeader, browserFooter, "2"],
            ["Page three prose crosses the bridge.", refrain, browserHeader, browserFooter, "3"],
            ["Page four prose reaches the gate.", refrain, browserHeader, browserFooter, "4"]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired == [
            ["Page one prose opens at dusk.", refrain],
            ["Page two prose follows the road.", refrain],
            ["Page three prose crosses the bridge.", refrain],
            ["Page four prose reaches the gate.", refrain]
        ])
    }

    // MARK: - Chapter splits: echoed headings & unnumbered visual headings

    @Test func echoedChapterHeadingAfterDecorativeDividerDoesNotSplitAStubChapter() throws {
        let url = try makeCustomPDF(pages: [
            [
                boldHeading("Chapter 1: Salt on the Stairs", y: 720),
                regular("* * *", y: 684, centered: true),
                regular("Chapter 1: Salt on the Stairs", y: 648),
                regular("Harun, Pia, and Bram met at the ink road because the second bell was late and", y: 612),
                regular("nobody else had brought a spare lantern down from the clock loft that evening.", y: 596)
            ],
            [
                boldHeading("Chapter 2: The Third Door", y: 720),
                regular("* * *", y: 684, centered: true),
                regular("Chapter 2: The Third Door", y: 648),
                regular("Water found the crack under the door and kept going while a dog barked once,", y: 612),
                regular("far off across the harbor, until the tide reached the wooden stairs below.", y: 596)
            ]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Untitled")
        try #require(result.chapters.count == 2)
        #expect(result.chapters[0].title == "Chapter 1: Salt on the Stairs")
        #expect(result.chapters[1].title == "Chapter 2: The Third Door")
        #expect(result.chapters[0].bodyXHTML.contains("* * *"))
        #expect(result.chapters[0].bodyXHTML.contains("Harun, Pia, and Bram"))
        #expect(result.chapters[1].bodyXHTML.contains("* * *"))
        #expect(result.chapters[1].bodyXHTML.contains("Water found the crack"))
    }

    @Test func unnumberedBoldCenteredChapterHeadingsSplitIntoChaptersWithPreface() throws {
        let url = try makeCustomPDF(pages: [
            [
                titleLine("The Iron Bell", y: 720),
                regular("Story: The Iron Bell", y: 676),
                regular("Storylink: https://example.org/works/1022", y: 644),
                regular("Category: Salt Orchard Ballads", y: 612),
                regular("Rating: T", y: 580),
                regular("Status: Complete", y: 548),
                regular("Summary: Pia returns to the Salt Orchard after the last bell sticks.", y: 516)
            ],
            [
                boldHeading("No Safe Road", y: 720),
                regular("Pia, Ivo, and Sera met at the orchard wall after the fog rolled in from the sea.", y: 676),
                regular("do not sell the light", y: 640, centered: true),
                regular("Cold.", y: 604),
                regular("Nobody at the white gate had seen the red notebook since the storm cleared.", y: 568)
            ],
            [
                boldHeading("After the Rain", y: 720),
                regular("A warm dark settled over the terrace while the ladders knocked in the wind and", y: 676),
                regular("the brass latch on the drying shed clicked twice in the quiet yard below.", y: 660)
            ]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Untitled")
        try #require(result.chapters.count == 3)
        #expect(result.chapters.map(\.title) == ["Preface", "No Safe Road", "After the Rain"])
        #expect(result.chapters[1].bodyXHTML.contains("do not sell the light"))
        #expect(result.chapters[1].bodyXHTML.contains("Cold."))
        #expect(result.chapters[2].bodyXHTML.contains("drying shed"))
    }

    // MARK: - Prose that reads as a heading

    @Test func multiSentenceProseSubtitleDoesNotStartAChapterWhileTitlesWithAbbreviationsDo() throws {
        let notHeadings = [
            "Part one: get in. Part two: get out.",
            "Chapter five: she never came back. Nobody looked.",
            "Chapter 2: Who are you? Tell me.",
            "Chapter 3: Wait! Don't go.",
            "1. Get in. Get out.",
            "Chapter 1: \"Stop.\" She didn't.",
            "Epilogue: She left. Nobody followed."
        ]
        for line in notHeadings {
            #expect(!PlainTextWorkConverter.isChapterHeading(line), "expected prose, not heading: \(line)")
            #expect(!PDFParagraphRepair.isExplicitChapterHeading(line), "expected prose, not heading: \(line)")
        }

        let validHeadings = [
            "Chapter 3: Mr. Smith Goes to Town",
            "Part Two — The Return",
            "Chapter 4: Dr. Watson and Mrs. Hudson",
            "Chapter 5: J. R. R. Tolkien",
            "Chapter 6: S.H.I.E.L.D. Protocol",
            "Chapter 7: Pretty please?",
            "Chapter 8: Ten Years Later.",
            "1. Mr. Darcy's Letter"
        ]
        for line in validHeadings {
            #expect(PlainTextWorkConverter.isChapterHeading(line), "expected valid heading: \(line)")
            #expect(PDFParagraphRepair.isExplicitChapterHeading(line), "expected valid heading: \(line)")
        }
        #expect(PDFParagraphRepair.isExplicitChapterHeading("Epilogue: Ten Years Later"))
        #expect(PDFParagraphRepair.isExplicitChapterHeading("*Chapter 6*: Pretty please?"))

        let text = """
        Chapter 3: Mr. Smith Goes to Town

        Part one: get in. Part two: get out.

        Chapter five: she never came back. Nobody looked.

        Part Two — The Return

        The bells struck midnight over the empty harbor.
        """
        let converted = try PlainTextWorkConverter.convert(text: text, fallbackTitle: "Test")
        try #require(converted.chapters.count == 2)
        #expect(converted.chapters[0].title == "Chapter 3: Mr. Smith Goes to Town")
        #expect(converted.chapters[0].bodyXHTML.contains("Part one: get in. Part two: get out."))
        #expect(converted.chapters[0].bodyXHTML.contains("Chapter five: she never came back. Nobody looked."))
        #expect(converted.chapters[1].title == "Part Two — The Return")
    }

    // MARK: - Page-number stream drawn before body text

    @Test func bottomMarginPageNumberDrawnBeforeBodyDoesNotStealMidPageHorizontalRule() throws {
        // Mirrors calibre `--pdf-page-numbers`, which draws the bottom-margin page number
        // stream ahead of the page's body content stream.
        let url = try makeCustomPDF(
            pages: [
                [
                    regular("After the Rain", y: 710),
                    regular("The first scene closes at the harbor wall as the lanterns flicker in the rain.", y: 660),
                    regular("The second scene opens on the clear morning after the storm moved east.", y: 580)
                ],
                [
                    regular("Filler page. The rain had stopped by the time the carriage reached the bridge,", y: 700),
                    regular("and the river below ran high and brown with everything the storm carried down", y: 684),
                    regular("from the hills. Nobody spoke until the lamps of the town came into view.", y: 668)
                ]
            ],
            extraDraw: { pageIndex, context in
                let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
                let num = NSAttributedString(
                    string: "\(pageIndex + 1)",
                    attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                )
                context.textPosition = CGPoint(x: 302, y: 24)
                CTLineDraw(CTLineCreateWithAttributedString(num), context)
                if pageIndex == 0 {
                    context.move(to: CGPoint(x: 214, y: 620))
                    context.addLine(to: CGPoint(x: 398, y: 620))
                    context.strokePath()
                }
            }
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let pages = try #require(KudosMuPDF.paragraphsPerPage(forPDFAtPath: url.path))
        let page0 = try #require(pages.first)
        try #require(page0.count >= 4)
        #expect(page0[0] == "After the Rain")
        #expect(page0[1].contains("first scene closes"))
        #expect(page0[2] == "* * *")
        #expect(page0[3].contains("second scene opens"))
    }
}
