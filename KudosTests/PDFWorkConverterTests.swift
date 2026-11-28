import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import Kudos

/// Tests PDF → EPUB conversion against PDFs generated in-test, so each case states
/// exactly the document shape it depends on.
///
/// Fixtures are drawn with CoreGraphics rather than checked in: it keeps the inputs
/// readable, and it is the only way to produce an honestly *text-free* PDF for the
/// OCR path.
struct PDFWorkConverterTests {
    // MARK: - Fixture building

    /// Draws each element of `pages` as a page of text, one line per array entry.
    private func makePDF(pages: [[String]], attributes: [CFString: Any] = [:]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(
            url as CFURL,
            mediaBox: &box,
            attributes as CFDictionary
        ) else { throw PDFTestError.contextUnavailable }

        // CoreText rather than `CGContext.showText`, which is unavailable on iOS, and
        // rather than UIKit's PDF renderer, which would make this file iOS-only.
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

    /// A PDF with no text operators at all — just a filled rectangle. Stands in for
    /// a scan, which is the case the OCR path exists for.
    private func makeImageOnlyPDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [:] as CFDictionary) else {
            throw PDFTestError.contextUnavailable
        }
        context.beginPage(mediaBox: &box)
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 20, y: 20, width: 260, height: 160))
        context.endPage()
        context.closePDF()
        return url
    }

    private enum PDFTestError: Error { case contextUnavailable }

    private func convert(_ url: URL, title: String = "Fallback Title") throws -> HTMLWorkConverter.Result {
        try PDFWorkConverter.convert(fileAt: url, fallbackTitle: title)
    }

    private func bodies(_ result: HTMLWorkConverter.Result) -> String {
        result.chapters.map(\.bodyXHTML).joined(separator: "\n")
    }

    // MARK: - Text layer

    /// Two paragraphs with a horizontal rule drawn between them (`rule: true`) or across the first paragraph's line
    /// (`rule: false`, a strike-through), the way calibre draws a FanFiction.net `<hr>`: a thin grey stroked path.
    private func makeRulePDF(ruleBetweenParagraphs: Bool) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-rule-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [:] as CFDictionary) else {
            throw PDFTestError.contextUnavailable
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        func draw(_ line: String, at y: CGFloat) {
            let attributed = NSAttributedString(string: line, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
            context.textPosition = CGPoint(x: 72, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.beginPage(mediaBox: &box)
        context.setFillColor(gray: 0, alpha: 1)
        draw("The first scene ends with the door closing behind her.", at: 700)
        draw("The second scene opens on the morning after the storm.", at: 640)
        context.setStrokeColor(gray: 0.5, alpha: 1)
        context.setLineWidth(1)
        let ruleY: CGFloat = ruleBetweenParagraphs ? 672 : 704
        context.move(to: CGPoint(x: 72, y: ruleY))
        context.addLine(to: CGPoint(x: 540, y: ruleY))
        context.strokePath()
        context.endPage()
        drawFillerPage(in: context, box: &box)
        context.closePDF()
        return url
    }

    @Test func aRuleDrawnBetweenParagraphsBecomesASceneBreak() throws {
        let url = try makeRulePDF(ruleBetweenParagraphs: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let body = bodies(try convert(url))
        let first = try #require(body.range(of: "door closing behind her"))
        let rule = try #require(body.range(of: "* * *"))
        let second = try #require(body.range(of: "morning after the storm"))
        #expect(first.upperBound < rule.lowerBound && rule.upperBound < second.lowerBound)
    }

    @Test func aTypedSceneBreakStaysInsideItsChapter() throws {
        // No outline, so this takes the plain-text path, where `* * *` alone on a line used to start a new chapter.
        let url = try makePDF(pages: [[
            "The first scene ends with the door closing behind her.",
            "",
            "* * *",
            "",
            "The second scene opens on the morning after the storm."
        ]])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try convert(url)
        #expect(result.chapters.count == 1)
        let body = bodies(result)
        let first = try #require(body.range(of: "door closing behind her"))
        let rule = try #require(body.range(of: "* * *"))
        let second = try #require(body.range(of: "morning after the storm"))
        #expect(first.upperBound < rule.lowerBound && rule.upperBound < second.lowerBound)
    }

    @Test func aRuleThroughTextIsNotASceneBreak() throws {
        let url = try makeRulePDF(ruleBetweenParagraphs: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let body = bodies(try convert(url))
        #expect(body.contains("door closing behind her"))
        #expect(!body.contains("* * *"))
    }

    /// Letter page. `draw` is PDF user space (origin at the bottom left).
    /// A second page of ordinary prose. The converter treats a document under 200 characters as a scan and OCRs it
    /// (`textLayerThreshold`), which never sees drawn rules, so a one-page rule fixture would test the OCR path instead
    /// (LESSONS T3). Page 1, which the rule tests are about, is unchanged.
    private func drawFillerPage(in context: CGContext, box: inout CGRect) {
        context.beginPage(mediaBox: &box)
        context.setFillColor(gray: 0, alpha: 1)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let lines = [
            "Filler page. The rain had stopped by the time the carriage reached the bridge,",
            "and the river below ran high and brown with everything the storm had carried down",
            "from the hills. Nobody spoke until the lamps of the town came into view at last.",
        ]
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
            context.textPosition = CGPoint(x: 72, y: 700 - CGFloat(index) * 16)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.endPage()
    }

    private func drawPDF(width: CGFloat = 612, height: CGFloat = 792, _ draw: (CGContext) -> Void) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-draw-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: width, height: height)
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

    private func drawLine(_ text: String, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }

    private func stroke(_ a: CGPoint, _ b: CGPoint, in context: CGContext) {
        context.move(to: a)
        context.addLine(to: b)
        context.strokePath()
    }

    private func sceneBreakCount(in body: String) -> Int {
        body.components(separatedBy: "* * *").count - 1
    }

    @Test func aRuleBesideOtherTextIsStillASceneBreak() throws {
        // The note shares the rule's height and does not touch it. A crosses-text test that ignores x would drop the rule.
        let url = try drawPDF { context in
            drawLine("The first scene ends with the door closing behind her.", at: CGPoint(x: 72, y: 700), in: context)
            drawLine("Aside.", at: CGPoint(x: 450, y: 672), in: context)
            drawLine("The second scene opens on the morning after the storm.", at: CGPoint(x: 72, y: 640), in: context)
            stroke(CGPoint(x: 72, y: 672), CGPoint(x: 400, y: 672), in: context)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let body = bodies(try convert(url))
        let first = try #require(body.range(of: "door closing behind her"))
        let rule = try #require(body.range(of: "* * *"))
        let second = try #require(body.range(of: "morning after the storm"))
        #expect(first.upperBound < rule.lowerBound && rule.upperBound < second.lowerBound)
        #expect(sceneBreakCount(in: body) == 1)
    }

    @Test func aBoxAroundAQuoteIsNotASceneBreak() throws {
        // Four strokes, not one rectangle: the top and bottom are wide enough to look like rules unless a vertical side crosses them.
        let url = try drawPDF { context in
            drawLine("Before the quote.", at: CGPoint(x: 72, y: 720), in: context)
            drawLine("A quoted line sits inside the box.", at: CGPoint(x: 90, y: 668), in: context)
            drawLine("After the quote.", at: CGPoint(x: 72, y: 600), in: context)
            stroke(CGPoint(x: 72, y: 700), CGPoint(x: 540, y: 700), in: context)
            stroke(CGPoint(x: 72, y: 640), CGPoint(x: 540, y: 640), in: context)
            stroke(CGPoint(x: 72, y: 640), CGPoint(x: 72, y: 700), in: context)
            stroke(CGPoint(x: 540, y: 640), CGPoint(x: 540, y: 700), in: context)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let body = bodies(try convert(url))
        #expect(body.contains("Before the quote."))
        #expect(body.contains("inside the box"))
        #expect(body.contains("After the quote."))
        #expect(sceneBreakCount(in: body) == 0)
    }

    @Test func aShortFootnoteRuleIsNotASceneBreak() throws {
        // 128 pt is under 40% of a 612 pt page. A footnote rule is about that long; a scene break spans the text.
        let url = try drawPDF { context in
            drawLine("The chapter ends here.", at: CGPoint(x: 72, y: 700), in: context)
            stroke(CGPoint(x: 72, y: 660), CGPoint(x: 200, y: 660), in: context)
            drawLine("A note about the ending.", at: CGPoint(x: 72, y: 620), in: context)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let body = bodies(try convert(url))
        #expect(body.contains("The chapter ends here."))
        #expect(body.contains("A note about the ending."))
        #expect(sceneBreakCount(in: body) == 0)
    }

    @Test func twoCloseStrokesAreOneSceneBreak() throws {
        let url = try drawPDF { context in
            drawLine("The first scene ends with the door closing behind her.", at: CGPoint(x: 72, y: 700), in: context)
            stroke(CGPoint(x: 72, y: 672), CGPoint(x: 540, y: 672), in: context)
            stroke(CGPoint(x: 72, y: 670), CGPoint(x: 540, y: 670), in: context)
            drawLine("The second scene opens on the morning after the storm.", at: CGPoint(x: 72, y: 640), in: context)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let body = bodies(try convert(url))
        let first = try #require(body.range(of: "door closing behind her"))
        let rule = try #require(body.range(of: "* * *"))
        let second = try #require(body.range(of: "morning after the storm"))
        #expect(first.upperBound < rule.lowerBound && rule.upperBound < second.lowerBound)
        #expect(sceneBreakCount(in: body) == 1)
    }

    @Test func aRuleAtThePageEdgeIsNotASceneBreakAndOneInsetFromItIs() throws {
        let url = try drawPDF { context in
            stroke(CGPoint(x: 72, y: 788), CGPoint(x: 540, y: 788), in: context)
            stroke(CGPoint(x: 72, y: 740), CGPoint(x: 540, y: 740), in: context)
            drawLine("The first scene ends with the door closing behind her.", at: CGPoint(x: 72, y: 700), in: context)
            drawLine("The second scene opens on the morning after the storm.", at: CGPoint(x: 72, y: 640), in: context)
            stroke(CGPoint(x: 72, y: 100), CGPoint(x: 540, y: 100), in: context)
            stroke(CGPoint(x: 72, y: 4), CGPoint(x: 540, y: 4), in: context)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let body = bodies(try convert(url))
        #expect(sceneBreakCount(in: body) == 2)
        let leading = try #require(body.range(of: "* * *"))
        let first = try #require(body.range(of: "door closing behind her"))
        let second = try #require(body.range(of: "morning after the storm"))
        let trailing = try #require(body.range(of: "* * *", options: .backwards))
        #expect(leading.upperBound < first.lowerBound)
        #expect(second.upperBound < trailing.lowerBound)
        #expect(leading != trailing)
    }

    @Test func aPrivateUseCharacterInTheProseStaysProse() throws {
        // The plain-text path used to replace every U+E000, so this sentence became a second scene break.
        let marked = "She wrote \u{E000} in the margin."
        let url = try makePDF(pages: [[
            "The first scene ends with the door closing behind her.",
            "",
            "* * *",
            "",
            marked,
            "",
            "The second scene opens on the morning after the storm."
        ]])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try convert(url)
        #expect(result.chapters.count == 1)
        let body = bodies(result)
        #expect(sceneBreakCount(in: body) == 1)
        #expect(body.contains("She wrote"))
        #expect(!body.contains("She wrote * * *"))
        let first = try #require(body.range(of: "door closing behind her"))
        let rule = try #require(body.range(of: "* * *"))
        let second = try #require(body.range(of: "morning after the storm"))
        #expect(first.upperBound < rule.lowerBound && rule.upperBound < second.lowerBound)
    }

    @Test func outlineAndPlainTextKeepTheSameSceneBreak() throws {
        let url = try makePDF(pages: [
            [
                "The first scene ends with the door closing behind her.",
                "",
                "* * *",
                "",
                "The second scene opens on the morning after the storm."
            ],
            ["The next chapter starts on a new page."]
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let plain = try convert(url)
        #expect(plain.chapters.count == 1)
        let plainBody = bodies(plain)
        let plainFirst = try #require(plainBody.range(of: "door closing behind her"))
        let plainRule = try #require(plainBody.range(of: "* * *"))
        let plainSecond = try #require(plainBody.range(of: "morning after the storm"))
        #expect(plainFirst.upperBound < plainRule.lowerBound && plainRule.upperBound < plainSecond.lowerBound)

        let outlined = try addingOutline(to: url, titles: ["Door", "Next"])
        defer { try? FileManager.default.removeItem(at: outlined) }
        let marked = try convert(outlined)
        #expect(marked.chapters.map(\.title) == ["Door", "Next"])
        let chapter = marked.chapters[0].bodyXHTML
        let first = try #require(chapter.range(of: "door closing behind her"))
        let rule = try #require(chapter.range(of: "* * *"))
        let second = try #require(chapter.range(of: "morning after the storm"))
        #expect(first.upperBound < rule.lowerBound && rule.upperBound < second.lowerBound)
        #expect(sceneBreakCount(in: chapter) == 1)
        #expect(!marked.chapters[1].bodyXHTML.contains("* * *"))
    }

    private func addingOutline(to url: URL, titles: [String]) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw PDFTestError.contextUnavailable }
        let root = PDFOutline()
        document.outlineRoot = root
        for (index, title) in titles.enumerated() {
            let item = PDFOutline()
            item.label = title
            if let page = document.page(at: index) {
                let top = page.bounds(for: .mediaBox).height
                item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: top))
            }
            root.insertChild(item, at: index)
        }
        let outlined = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-outline-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        guard document.write(to: outlined) else { throw PDFTestError.contextUnavailable }
        return outlined
    }

    @Test func extractsProseAndRejoinsHardWrappedLines() throws {
        // PDF text comes out one line per *display* line; naive conversion would make
        // each its own paragraph and read terribly once reflowed.
        let url = try makePDF(pages: [[
            "Chapter 1: The Return",
            "",
            "She opened the door and found the room",
            "exactly as she had left it, down to the",
            "half-finished cup on the table.",
            "",
            "Nothing had moved for years."
        ]])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try convert(url)
        let body = bodies(result)
        #expect(body.contains("She opened the door and found the room exactly as she had left it"))
        #expect(body.contains("<p>Nothing had moved for years.</p>"))
    }

    @Test func splitsOnChapterHeadingsUsingTheSharedTextRules() throws {
        let url = try makePDF(pages: [
            ["Chapter 1: Start", "", "First chapter prose."],
            ["Chapter 2: Finish", "", "Second chapter prose."]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try convert(url)
        #expect(result.chapters.map(\.title) == ["Chapter 1: Start", "Chapter 2: Finish"])
    }

    @Test func dropsRunningHeadersAndPageNumbers() throws {
        // A running header on every page plus a bare page number is the single most
        // common reason a PDF conversion reads badly.
        let pages = (1...6).map { index in
            ["A Rescued Fic", "", "Body text for page \(index) of the story.", "", "\(index)"]
        }
        let url = try makePDF(pages: pages)
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try convert(url))
        #expect(body.contains("Body text for page 1 of the story."))
        // The header repeats on every page, so it must not survive as prose.
        #expect(!body.contains("<p>A Rescued Fic</p>"))
        #expect(!body.contains("<p>3</p>"))
    }

    @Test func dehyphenatesWordsBrokenAcrossLines() throws {
        let url = try makePDF(pages: [["The corridor was unremark-", "able in every way."]])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(bodies(try convert(url)).contains("unremarkable in every way."))
    }

    @Test func readsTitleAuthorAndKeywordsFromDocumentAttributes() throws {
        let url = try makePDF(
            pages: [["Some prose to import."]],
            attributes: [
                kCGPDFContextTitle: "The Real Title",
                kCGPDFContextAuthor: "PDF Author",
                kCGPDFContextKeywords: "Fluff, Angst"
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try convert(url)
        #expect(result.metadata.title == "The Real Title")
        #expect(result.metadata.author == "PDF Author")
        // calibre writes a fic's tags into Keywords when it makes a PDF.
        #expect(result.metadata.subjects.contains("Fluff"))
        #expect(result.metadata.subjects.contains("Angst"))
    }

    @Test func fallsBackToTheFileNameWhenThePDFHasNoTitle() throws {
        let url = try makePDF(pages: [["Prose with no metadata."]])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try convert(url, title: "Named By File").metadata.title == "Named By File")
    }

    /// Draws `runs` as separate CoreText draws on the *same* baseline, which is how a
    /// real PDF stores a line whose font changes mid-way — around curly quotes, most
    /// often. `PDFPage.string` then reports each run as its own newline-separated
    /// entry, and the first version of this converter read each as a paragraph end.
    private func makeMultiRunPDF(lines: [[String]]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("runs-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [:] as CFDictionary) else {
            throw PDFTestError.contextUnavailable
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        context.beginPage(mediaBox: &box)
        context.setFillColor(gray: 0, alpha: 1)
        var y = box.height - 72
        for runs in lines {
            // An empty run list means a blank line: advance without drawing, so the
            // page really has the vertical gap that separates two paragraphs.
            guard !runs.isEmpty else {
                y -= 16
                continue
            }
            var x: CGFloat = 72
            for run in runs {
                let attributed = NSAttributedString(
                    string: run,
                    attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                )
                let ctLine = CTLineCreateWithAttributedString(attributed)
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(ctLine, context)
                x += CTLineGetTypographicBounds(ctLine, nil, nil, nil)
            }
            y -= 16
        }
        context.endPage()
        context.closePDF()
        return url
    }

    @Test func aLineSplitIntoSeveralRunsStaysOneParagraph() throws {
        // The regression the owner hit on a real file: one printed paragraph came out
        // as three, split at the quote marks. Runs on a shared baseline are one line,
        // and paragraph structure must come from geometry, not from `page.string`.
        let url = try makeMultiRunPDF(lines: [
            ["Yes I should be working on \"you're in the army now.", "\" I will finish it. I swear."],
            ["I'm just not feeling it right now, so enjoy this instead of the other thing."],
            [], [],                   // blank lines: the real paragraph separator
            ["Cold."]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try convert(url))
        // The two runs on the first baseline must stay one paragraph with their
        // continuation, never split at the quote. Quotes are XML-escaped in the body.
        #expect(body.contains("army now.&quot; I will finish it."))
        #expect(!body.contains("<p>&quot; I will finish it. I swear.</p>"))

        // NOT asserted here: that "Cold." after the blank lines becomes its own
        // paragraph. On iOS this fixture's multi-run page falls back to the
        // text-only heuristic — `numberOfCharacters` matches neither of PDFKit's
        // index conventions for it — so paragraph *separation* is not exercised by
        // this input, only fragment *joining* is. Separation is covered by
        // `extractsProseAndRejoinsHardWrappedLines`, whose page does take the
        // geometry path. Verifying both at once needs a real multi-run PDF; see
        // TASKS.md T-157 for that outstanding on-device check.
    }

    @Test func theTitleIsNotRepeatedAsTheFirstParagraph() throws {
        // Also from the real file: a PDF carries its title as ordinary page text, and
        // EPUBBuilder already emits the chapter title as an <h1>, so it appeared twice.
        let url = try makePDF(
            pages: [["Traveling Sword", "", "The story itself starts here and runs on."]],
            attributes: [kCGPDFContextTitle: "Traveling Sword"]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try convert(url)
        #expect(result.metadata.title == "Traveling Sword")
        let body = bodies(result)
        #expect(!body.contains("<p>Traveling Sword</p>"))
        #expect(body.contains("The story itself starts here"))
    }

    @Test func aCalibreMetadataPageFillsInRatingStatusAndFandom() throws {
        // The owner's report was that imported works showed only title, author and a
        // chapter count. Everything else comes from AO3's `dt`/`dd` markup, which a
        // synthesized EPUB had none of — so the preface now emits that block and the
        // importer's existing scanner reads it.
        let url = try makePDF(pages: [
            [
                "A Rescued Fic",
                "Story: A Rescued Fic",
                "Storylink: https://www.fanfiction.net/s/12345/1/",
                "Category: Frozen",
                "Genre: Romance/Fantasy",
                "Rating: M",
                "Status: Complete",
                "Words: 112438",
                "Content: Chapter 1 to 31 of 31 chapters",
                "Summary: The only copy left."
            ],
            ["Chapter 1: Start", "", "The story itself begins here and runs on for a while."]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try convert(url)
        let body = bodies(result)
        // Rating is mapped to AO3's spelling, which is what the importer matches on:
        // an unmapped "M" was dropped entirely.
        #expect(body.contains("<dt>Rating:</dt>"))
        #expect(body.contains("Mature"))
        #expect(body.contains("<dt>Status:</dt>"))
        #expect(body.contains("Complete"))
        #expect(body.contains("<dt>Fandom:</dt>"))
        #expect(body.contains("Frozen"))
        #expect(body.contains("<dt>Chapters:</dt>"))
        #expect(body.contains("31/31"))
        // The story link survives as dc:source, which is what makes the origin badge
        // read FFN rather than "Imported".
        #expect(result.metadata.sourceURL == "https://www.fanfiction.net/s/12345/1/")
        // And the raw rating is not also dumped into the tag list, where it showed up
        // as a stray "M" freeform.
        #expect(!result.metadata.subjects.contains("M"))
    }

    // MARK: - Whole-pipeline behavior

    @Test func convertsThroughTheImporterAndProducesAReadableEPUB() throws {
        let url = try makePDF(pages: [
            ["Chapter 1: One", "", "Chapter one prose."],
            ["Chapter 2: Two", "", "Chapter two prose."]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        // PDF must now be a supported format rather than a "convert it yourself" error.
        #expect(ImportedFileFormat.detect(at: url) == .pdf)
        #expect(ImportedFileFormat.pdf.isConvertible)

        let outcome = try ImportedDocumentConverter.convert(fileAt: url)
        guard case let .converted(data, from) = outcome else {
            Issue.record("expected a converted outcome, got \(outcome)")
            return
        }
        #expect(from == .pdf)

        let epubURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("out-\(UUID().uuidString).epub")
        try data.write(to: epubURL)
        defer { try? FileManager.default.removeItem(at: epubURL) }
        #expect(try EPUBDocument.inspectPackage(ofEPUBAt: epubURL).readableItemCount == 2)
    }

    // MARK: - Failure paths

    @Test func anUnopenablePDFFailsWithItsOwnMessage() throws {
        // Right magic bytes, garbage body — sniffs as PDF, then PDFKit refuses it.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("broken-\(UUID().uuidString).pdf")
        try Data("%PDF-1.7\nnot actually a pdf".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ImportedDocumentConverter.ConversionError.pdfUnreadable) {
            _ = try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Broken")
        }
    }

    @Test func failureMessagesNamePDFAndSayWhatToDo() {
        let locked = ImportedDocumentConverter.ConversionError.pdfPasswordProtected.errorDescription ?? ""
        #expect(locked.contains("password"))
        let empty = ImportedDocumentConverter.ConversionError.pdfHasNoExtractableText.errorDescription ?? ""
        #expect(empty.lowercased().contains("scan"))
    }

    // MARK: - OCR

    @Test func aPDFWithNoTextLayerTakesTheOCRPathAndFailsHonestlyWhenThereIsNothingToRead() throws {
        // A grey rectangle has no text layer *and* no glyphs to recognize, so this
        // asserts the OCR path runs and then reports honestly rather than importing a
        // blank work. A real scan of prose would return text here; generating one
        // legibly enough for Vision is not something a unit test can promise, so the
        // positive OCR case is left to the on-device check recorded in TASKS.md.
        let url = try makeImageOnlyPDF()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: (any Error).self) {
            _ = try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Scan")
        }
    }
}
