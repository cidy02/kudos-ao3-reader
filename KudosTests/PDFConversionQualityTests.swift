import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import Kudos

/// End-to-end and unit tests for T-579e PDF conversion quality improvements:
/// verse line breaks, short-document chrome removal, centered/blank scene breaks,
/// and outline-title validation.
struct PDFConversionQualityTests {
    private enum PDFTestError: Error { case contextUnavailable }

    private func makePDF(pages: [[String]]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-quality-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [:] as CFDictionary) else {
            throw PDFTestError.contextUnavailable
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for lines in pages {
            context.beginPage(mediaBox: &box)
            context.setFillColor(gray: 0, alpha: 1)
            var y = box.height - 72
            for line in lines {
                let attributed = NSAttributedString(
                    string: line,
                    attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                )
                context.textPosition = CGPoint(x: 72, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
                y -= 16
            }
            context.endPage()
        }
        context.closePDF()
        return url
    }

    private func drawPDF(_ draw: (CGContext) -> Void) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-quality-draw-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [:] as CFDictionary) else {
            throw PDFTestError.contextUnavailable
        }
        context.beginPage(mediaBox: &box)
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0.5, alpha: 1)
        context.setLineWidth(1)
        draw(context)
        context.endPage()
        drawFillerPage(in: context, box: &box)
        context.closePDF()
        return url
    }

    /// Ensures synthetic fixtures exceed `PDFWorkConverter`'s 200-character text-layer threshold
    /// so tests exercise MuPDF rather than the Vision OCR fallback (LESSONS T3).
    private func drawFillerPage(in context: CGContext, box: inout CGRect) {
        context.beginPage(mediaBox: &box)
        context.setFillColor(gray: 0, alpha: 1)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let lines = [
            "Filler page. The rain had stopped by the time the carriage reached the bridge,",
            "and the river below ran high and brown with everything the storm had carried down",
            "from the hills. Nobody spoke until the lamps of the town came into view at last."
        ]
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(
                string: line,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
            context.textPosition = CGPoint(x: 72, y: 700 - CGFloat(index) * 16)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.endPage()
    }

    private func drawLine(_ text: String, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }

    private func stroke(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    private func bodies(_ result: HTMLWorkConverter.Result) -> String {
        result.chapters.map(\.bodyXHTML).joined(separator: "\n")
    }

    private func sceneBreakCount(in body: String) -> Int {
        body.components(separatedBy: "* * *").count - 1
    }

    // MARK: - Verse & lyrics

    @Test func verseLinesKeepBreaksWhileWrappedProseAndShortDialogueEndingsStayOneParagraph() throws {
        let regularFont = CTFontCreateWithName("Georgia" as CFString, 12, nil)
        let italicFont = CTFontCreateWithName("Georgia-Italic" as CFString, 12, nil)

        func drawRuns(_ runs: [(String, CTFont)], at point: CGPoint, in context: CGContext) {
            let attributed = NSMutableAttributedString()
            for (text, font) in runs {
                attributed.append(NSAttributedString(
                    string: text,
                    attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                ))
            }
            context.textPosition = point
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }

        let proseOpening = "The lantern flickered along the wet stone dock while she waited by the iron gate."
        let proseClosing = "Nobody answered from the tower stairs, and the fog drifted back across the pier."
        let url = try drawPDF { context in
            // Full-width prose with a short final dialogue line must remain one `<p>` with no `<br/>`.
            drawRuns([(proseOpening, regularFont)], at: CGPoint(x: 72, y: 710), in: context)
            drawRuns([("\"Are you coming?\" she asked.", regularFont)], at: CGPoint(x: 72, y: 694), in: context)

            // Short verse lines (~140 pt wide) with an italic word on line 2 to verify range alignment.
            drawRuns([("Salt on the lintel", regularFont)], at: CGPoint(x: 240, y: 650), in: context)
            drawRuns(
                [("salt on the ", regularFont), ("tongue", italicFont)],
                at: CGPoint(x: 240, y: 634),
                in: context
            )
            drawRuns([("the orchard takes its fee", regularFont)], at: CGPoint(x: 240, y: 618), in: context)
            drawRuns([("in names, not in coin.", regularFont)], at: CGPoint(x: 240, y: 602), in: context)

            // Full-width prose below.
            drawRuns([(proseClosing, regularFont)], at: CGPoint(x: 72, y: 558), in: context)
            drawRuns(
                [("She pocketed the spare key and turned toward the lower road.", regularFont)],
                at: CGPoint(x: 72, y: 542),
                in: context
            )
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Verse"))
        #expect(body.contains("<p>\(proseOpening) &quot;Are you coming?&quot; she asked.</p>"))
        #expect(body.contains("Salt on the lintel<br/>salt on the <em>tongue</em>"))
        #expect(body.contains("<br/>the orchard takes its fee<br/>in names, not in coin."))
        #expect(body.contains("across the pier. She pocketed the spare key and turned toward the lower road.</p>"))

        let wrapped = "<root xmlns:epub=\"http://www.idpf.org/2007/ops\">\(body)</root>"
        #expect(XMLParser(data: Data(wrapped.utf8)).parse())
    }

    // MARK: - Short-document chrome

    @Test func threePagePDFDropsRunningHeaderAndPageNumbers() throws {
        let pages = [
            [
                "The Night Notebook",
                "",
                "Chapter 1: Paper Water",
                "",
                "The harbor bell struck twice before dawn while fog settled low over the stairs.",
                "",
                "1"
            ],
            [
                "The Night Notebook",
                "",
                "She checked the brass latch again, found the red notebook still dry, and waited.",
                "",
                "2"
            ],
            [
                "The Night Notebook",
                "",
                "By sunrise the tide had cleared the lower road and the iron gate stood unlocked.",
                "",
                "3"
            ]
        ]
        let url = try makePDF(pages: pages)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Short"))
        #expect(body.contains("The harbor bell struck twice"))
        #expect(body.contains("found the red notebook still dry"))
        #expect(body.contains("the iron gate stood unlocked"))
        #expect(!body.contains("The Night Notebook"))
        #expect(!body.contains("<p>1</p>"))
        #expect(!body.contains("<p>2</p>"))
        #expect(!body.contains("<p>3</p>"))
    }

    // MARK: - Scene breaks

    @Test func centeredMediumHorizontalRuleBecomesASceneBreak() throws {
        // 184 pt centered on a 612 pt page (~30% of page width, matching CSS `hr { width: 40%; margin: auto }`).
        let url = try drawPDF { context in
            drawLine("The first scene ends with the door closing quietly.", at: CGPoint(x: 72, y: 700), in: context)
            stroke(from: CGPoint(x: 214, y: 672), to: CGPoint(x: 398, y: 672), in: context)
            drawLine("The second scene opens on the clear morning after.", at: CGPoint(x: 72, y: 640), in: context)
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "CenteredHR"))
        let first = try #require(body.range(of: "door closing quietly"))
        let rule = try #require(body.range(of: "* * *"))
        let second = try #require(body.range(of: "clear morning after"))
        #expect(first.upperBound < rule.lowerBound && rule.upperBound < second.lowerBound)
        #expect(sceneBreakCount(in: body) == 1)
    }

    @Test func largeBlankVerticalGapBecomesASceneBreakWithoutInventingOnNormalGaps() throws {
        // Normal paragraph baseline spacing is 32 pt (~18 pt gap); the break leaves an 80 pt jump (~66 pt empty gap).
        let url = try drawPDF { context in
            drawLine("First paragraph opens beside the harbor dock in fog.", at: CGPoint(x: 72, y: 700), in: context)
            drawLine("Second paragraph continues with normal block spacing.", at: CGPoint(x: 72, y: 668), in: context)
            drawLine("Third paragraph finishes the first scene before gap.", at: CGPoint(x: 72, y: 636), in: context)
            drawLine("Fourth paragraph begins the new scene after a break.", at: CGPoint(x: 72, y: 556), in: context)
            drawLine("Fifth paragraph follows normally after the new scene.", at: CGPoint(x: 72, y: 524), in: context)
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "BlankGap"))
        let third = try #require(body.range(of: "finishes the first scene"))
        let brk = try #require(body.range(of: "* * *"))
        let fourth = try #require(body.range(of: "begins the new scene"))
        #expect(third.upperBound < brk.lowerBound && brk.upperBound < fourth.lowerBound)
        #expect(sceneBreakCount(in: body) == 1)
    }

    @Test func lineBreakMarkerBecomesNormalizedSceneBreak() throws {
        let url = try drawPDF { context in
            drawLine("The first scene ends with the lantern burning low.", at: CGPoint(x: 72, y: 700), in: context)
            drawLine("Line Break", at: CGPoint(x: 276, y: 668), in: context)
            drawLine("The second scene begins when the bells strike six.", at: CGPoint(x: 72, y: 636), in: context)
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "LineBreak"))
        let first = try #require(body.range(of: "lantern burning low"))
        let brk = try #require(body.range(of: "* * *"))
        let second = try #require(body.range(of: "bells strike six"))
        #expect(first.upperBound < brk.lowerBound && brk.upperBound < second.lowerBound)
        #expect(!body.contains("Line Break"))
    }

    // MARK: - Outline titles

    @Test func outlineTitleValidationReplacesRunawayOrProseLabelsWithHeadingOrChapterNumber() throws {
        // Real short titles stay untouched (including punctuation like "?" or "!").
        let shortChapter = [
            PDFStyledBlock(text: "*Chapter 6*: Pretty please?"),
            PDFStyledBlock(text: "Anna stared back at the frozen window without moving.")
        ]
        #expect(
            PDFWorkConverter.resolvedOutlineTitle(
                rawLabel: "*Chapter 6*: Pretty please?",
                blocks: shortChapter,
                chapterNumber: 6
            ) == "*Chapter 6*: Pretty please?"
        )
        #expect(
            PDFWorkConverter.resolvedOutlineTitle(
                rawLabel: "Pretty please?",
                blocks: [PDFStyledBlock(text: "Pretty please?"), PDFStyledBlock(text: "She waited.")],
                chapterNumber: 6
            ) == "Pretty please?"
        )

        // Over-100-character calibre outline dump uses the chapter's heading line.
        let longCalibreLabel = "Chapter 1: Salt on the Stairs ~*~ I don't own the harbor or the weather. "
            + "Maren, Harun, and Jory met at the orchard wall because the second bell was late."
        let numberedBlocks = [
            PDFStyledBlock(text: "Chapter 1: Salt on the Stairs"),
            PDFStyledBlock(text: "* * *"),
            PDFStyledBlock(text: "Maren, Harun, and Jory met at the orchard wall.")
        ]
        #expect(
            PDFWorkConverter.resolvedOutlineTitle(
                rawLabel: longCalibreLabel,
                blocks: numberedBlocks,
                chapterNumber: 1
            ) == "Chapter 1: Salt on the Stairs"
        )

        // Bold unnumbered heading is recovered when the outline label is runaway text.
        let boldHeading = PDFStyledBlock(
            text: "After the Rain",
            boldRanges: [NSRange(location: 0, length: 14)]
        )
        let longBoldLabel = "After the Rain ❦ A/N: mind the stairs. Sera, Nessa, and Maren met at the ink road "
            + "and waited for the tide to turn before midnight."
        #expect(
            PDFWorkConverter.resolvedOutlineTitle(
                rawLabel: longBoldLabel,
                blocks: [boldHeading, PDFStyledBlock(text: "* * *"), PDFStyledBlock(text: "Sera waited.")],
                chapterNumber: 2
            ) == "After the Rain"
        )

        // Prose-only opening (even under 100 chars) falls back to "Chapter N".
        let proseSentence = "The rain had stopped before the carriage reached the bridge and lamps appeared."
        #expect(
            PDFWorkConverter.resolvedOutlineTitle(
                rawLabel: proseSentence,
                blocks: [PDFStyledBlock(text: proseSentence)],
                chapterNumber: 3
            ) == "Chapter 3"
        )

        // Truncated excerpt of a long opening paragraph also falls back to "Chapter N".
        let longOpening = "The rain had stopped before the carriage reached the bridge, and the river below "
            + "ran high and brown with everything the storm had carried down from the hills."
        #expect(
            PDFWorkConverter.resolvedOutlineTitle(
                rawLabel: "The rain had stopped before the carriage reached the bridge...",
                blocks: [PDFStyledBlock(text: longOpening)],
                chapterNumber: 4
            ) == "Chapter 4"
        )

        // In-memory `PDFDocument` + `PDFOutline` exercises `outlineChapters` directly.
        let pdfURL = try makePDF(pages: [
            ["Part One", "", "Bram, Ivo, and Pia met at the lantern stall after the second bell rang."],
            ["The wind rose over the harbor and carried salt across every window on the pier."]
        ])
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let doc = try #require(PDFDocument(url: pdfURL))
        let page0 = try #require(doc.page(at: 0))
        let page1 = try #require(doc.page(at: 1))

        let root = PDFOutline()
        let child0 = PDFOutline()
        child0.label = "Part One Bram, Ivo, and Pia met at the lantern stall after the second bell "
            + "had already rung twice in the fog."
        child0.destination = PDFDestination(page: page0, at: .zero)
        let child1 = PDFOutline()
        child1.label = "The wind rose over the harbor and carried salt across every window on the pier."
        child1.destination = PDFDestination(page: page1, at: .zero)
        root.insertChild(child0, at: 0)
        root.insertChild(child1, at: 1)
        doc.outlineRoot = root

        let pageBlocks: [[PDFStyledBlock]] = [
            [
                PDFStyledBlock(text: "Part One"),
                PDFStyledBlock(text: "Bram, Ivo, and Pia met at the lantern stall after the second bell.")
            ],
            [
                PDFStyledBlock(text: "The wind rose over the harbor and carried salt across every window on the pier.")
            ]
        ]
        let chapters = try #require(PDFWorkConverter.outlineChapters(of: doc, pageBlocks: pageBlocks))
        try #require(chapters.count == 2)
        #expect(chapters[0].title == "Part One")
        #expect(chapters[1].title == "Chapter 2")
    }
}

/// T-579e round 2: a page number printed on its own line right under the last line of a paragraph at the bottom of a
/// page (14 pt below it, same left edge, inside the bottom margin band) lands in that paragraph's MuPDF block. It is page
/// chrome, not a verse line kept inside the paragraph (Sonnet's review: the first version drew the number far below
/// the paragraph, in a block of its own, so it never tested this).
struct PDFPageNumberLineTests {
    @Test func aPageNumberUnderTheLastLineIsNotKeptAsAVerseLine() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-pagenum-\(UUID().uuidString)").appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, [:] as CFDictionary))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        func draw(_ text: String, y: CGFloat) {
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]))
            context.textPosition = CGPoint(x: 72, y: y)
            CTLineDraw(line, context)
        }
        for page in 1...2 {
            context.beginPage(mediaBox: &box)
            draw("The lamps along the river road were lit one by one as the carriage passed beneath", y: 96)
            draw("them, and the driver counted each of them aloud as if the number might matter later", y: 82)
            draw("to someone who had asked him to keep track of every light between the mill and the", y: 68)
            draw("bridge, and nobody spoke until the bridge.", y: 54)
            draw("\(page)", y: 40)   // the page number, 14 pt under the last line, in the bottom margin band
            context.endPage()
        }
        context.closePDF()

        let pages = try #require(KudosMuPDF.paragraphsPerPage(forPDFAtPath: url.path))
        let text = pages.flatMap { $0 }.joined(separator: "\n")
        #expect(text.contains("nobody spoke until the bridge."))
        #expect(!text.contains("bridge.\n1") && !text.contains("bridge.\n2"))
        #expect(!text.contains("bridge. 1") && !text.contains("bridge. 2"))
    }
}
