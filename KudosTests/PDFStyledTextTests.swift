import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Kudos

/// Tests end-to-end preservation of italic and bold runs from MuPDF extraction through
/// `PDFParagraphRepair`, `PlainTextWorkConverter`, and `HTMLWorkSanitizer`.
struct PDFStyledTextTests {
    private enum FontStyle {
        case regular
        case italic
        case bold
        case boldItalic
    }

    private struct StyledRun {
        let text: String
        let style: FontStyle
    }

    private enum PDFTestError: Error {
        case contextUnavailable
    }

    private func regular(_ text: String) -> StyledRun { StyledRun(text: text, style: .regular) }
    private func italic(_ text: String) -> StyledRun { StyledRun(text: text, style: .italic) }
    private func bold(_ text: String) -> StyledRun { StyledRun(text: text, style: .bold) }
    private func boldItalic(_ text: String) -> StyledRun { StyledRun(text: text, style: .boldItalic) }

    private func ctFont(for style: FontStyle) -> CTFont {
        let name: String = switch style {
        case .regular: "Georgia"
        case .italic: "Georgia-Italic"
        case .bold: "Georgia-Bold"
        case .boldItalic: "Georgia-BoldItalic"
        }
        return CTFontCreateWithName(name as CFString, 12, nil)
    }

    /// Builds a PDF with CoreText using Georgia regular/italic/bold/bold-italic runs.
    /// An empty run list leaves a vertical paragraph gap between blocks.
    private func makeStyledPDF(
        pages: [[[StyledRun]]],
        attributes: [CFString: Any] = [:]
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-styled-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(
            url as CFURL,
            mediaBox: &box,
            attributes as CFDictionary
        ) else { throw PDFTestError.contextUnavailable }

        for lines in pages {
            context.beginPage(mediaBox: &box)
            context.setFillColor(gray: 0, alpha: 1)
            var y = box.height - 72
            for runs in lines {
                guard !runs.isEmpty else {
                    y -= 24
                    continue
                }
                let attributed = NSMutableAttributedString()
                for run in runs {
                    attributed.append(NSAttributedString(
                        string: run.text,
                        attributes: [kCTFontAttributeName as NSAttributedString.Key: ctFont(for: run.style)]
                    ))
                }
                context.textPosition = CGPoint(x: 72, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
                y -= 16
            }
            context.endPage()
        }
        context.closePDF()
        return url
    }

    private func makeStyledRulePDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-styled-rule-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [:] as CFDictionary) else {
            throw PDFTestError.contextUnavailable
        }

        func draw(_ runs: [StyledRun], at y: CGFloat) {
            let attributed = NSMutableAttributedString()
            for run in runs {
                attributed.append(NSAttributedString(
                    string: run.text,
                    attributes: [kCTFontAttributeName as NSAttributedString.Key: ctFont(for: run.style)]
                ))
            }
            context.textPosition = CGPoint(x: 72, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }

        context.beginPage(mediaBox: &box)
        context.setFillColor(gray: 0, alpha: 1)
        draw([
            regular("Before "), italic("whispered"), regular(" and "),
            bold("shouted"), regular(" and "), boldItalic("both"), regular(".")
        ], at: 700)
        draw([regular("After the break the storm settled down.")], at: 640)
        context.setStrokeColor(gray: 0.5, alpha: 1)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: 72, y: 672))
        context.addLine(to: CGPoint(x: 540, y: 672))
        context.strokePath()
        context.endPage()
        context.closePDF()
        return url
    }

    private func bodies(_ result: HTMLWorkConverter.Result) -> String {
        result.chapters.map(\.bodyXHTML).joined(separator: "\n")
    }

    private func isWellFormedXHTMLFragment(_ fragment: String) -> Bool {
        let wrapped = "<root xmlns:epub=\"http://www.idpf.org/2007/ops\">\(fragment)</root>"
        return XMLParser(data: Data(wrapped.utf8)).parse()
    }

    // MARK: - End-to-end PDF conversion

    @Test func midSentenceItalicBoldAndNestedBoldItalicSurviveConversion() throws {
        let url = try makeStyledPDF(pages: [[
            [regular("She stood in the hall and thought, "), italic("this cannot be real"), regular(" now.")],
            [regular("Then she turned back to face the "), bold("locked iron"), regular(" doorway.")],
            [],
            [regular("He whispered "), boldItalic("never again"), regular(" while snow drifted past the narrow")],
            [regular("windows and settled quietly along the cold stone wall.")]
        ]])
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Test"))
        #expect(body.contains("She stood in the hall and thought, <em>this cannot be real</em> now."))
        #expect(body.contains("Then she turned back to face the <strong>locked iron</strong> doorway."))
        #expect(body.contains("He whispered <strong><em>never again</em></strong> while snow drifted past"))
        #expect(!body.contains("<em> ") && !body.contains(" </em>"))
        #expect(!body.contains("<strong> ") && !body.contains(" </strong>"))
        #expect(isWellFormedXHTMLFragment(body))
    }

    @Test func italicAndBoldSpanningLineWrapsAndSingleSpacesMergeIntoOneRun() throws {
        let url = try makeStyledPDF(pages: [[
            [regular("The lantern flickered while she wondered "), italic("what if he")],
            [italic("never"), regular(" "), italic("comes back"), regular(" before the winter roads freeze over?")],
            [],
            [regular("Above the arch the carved stone still read "), bold("hold the")],
            [bold("northern gate"), regular(" in letters worn smooth by years of wind and rain.")]
        ]])
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Test"))
        #expect(body.contains(
            "<p>The lantern flickered while she wondered <em>what if he never comes back</em> "
                + "before the winter roads freeze over?</p>"
        ))
        #expect(body.contains(
            "<p>Above the arch the carved stone still read <strong>hold the northern gate</strong> "
                + "in letters worn smooth by years of wind and rain.</p>"
        ))
    }

    @Test func paragraphJoinedAcrossPageBreakKeepsBothHalvesStyling() throws {
        let url = try makeStyledPDF(pages: [
            [
                // Prose lines fill the measure, as they do in real PDFs: since T-579e a short line followed by another is
                // a deliberate (verse) line break, so a hand-broken short line here would test the verse rule instead.
                [regular("The evening watch had already changed twice since dusk, and the long courtyard below the")],
                [regular("old walls lay silent beneath a thin crust of fresh snow that nobody had yet disturbed.")],
                [],
                [regular("She hurried down the corridor past the shuttered windows thinking "), italic("only of escape")],
                [regular("while the distant alarm bells somewhere far below the outer walls of the old citadel")]
            ],
            [
                [regular("began to ring "), bold("louder and louder"), regular(" as the wind carried their sound up through")],
                [regular("the narrow passes and across the dark valley below the citadel.")],
                [],
                [regular("Nobody spoke again until the heavy gates finally groaned open.")]
            ]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Test"))
        #expect(body.contains(
            "<p>She hurried down the corridor past the shuttered windows thinking <em>only of escape</em> while the "
                + "distant alarm bells somewhere far below the outer walls of the old citadel began to ring "
                + "<strong>louder and louder</strong> as the wind carried their sound up through the narrow passes and "
                + "across the dark valley below the citadel.</p>"
        ))
        #expect(body.contains("<p>Nobody spoke again until the heavy gates finally groaned open.</p>"))
    }

    @Test func italicPhraseSplitAcrossPageBreakMergesAcrossJoinSpace() throws {
        let url = try makeStyledPDF(pages: [
            [
                [regular("The corridor stretched ahead in near darkness, lit only by a")],
                [regular("faint silver reflection of moonlight on the frozen window.")],
                [],
                [regular("Her thoughts raced in the quiet: "), italic("I cannot let them find")]
            ],
            [
                [italic("the hidden letter"), regular(" before sunrise reaches the eastern towers.")],
                [],
                [regular("She kept moving without looking back.")]
            ]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Test"))
        #expect(body.contains(
            "<p>Her thoughts raced in the quiet: <em>I cannot let them find the hidden letter</em> "
                + "before sunrise reaches the eastern towers.</p>"
        ))
    }

    @Test func styledTextEscapesXMLCharactersBeforeWrappingTags() throws {
        let url = try makeStyledPDF(pages: [[
            [regular("She read "), italic("Tom & Jerry <1940>"), regular(" aloud while checking")],
            [bold("a < b & c > d"), regular(" in the margin of the notebook beside her.")],
            [],
            [regular("Then she underlined "), boldItalic("\"safe & sound\""), regular(" twice before closing the")],
            [regular("worn leather cover and resting her elbows on the table.")]
        ]])
        defer { try? FileManager.default.removeItem(at: url) }

        let body = bodies(try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Test"))
        #expect(body.contains("<em>Tom &amp; Jerry &lt;1940&gt;</em>"))
        #expect(body.contains("<strong>a &lt; b &amp; c &gt; d</strong>"))
        #expect(body.contains("<strong><em>&quot;safe &amp; sound&quot;</em></strong>"))
        #expect(isWellFormedXHTMLFragment(body))
    }

    @Test func headingsAndSeparatorsCarryNoInlineStyling() throws {
        let url = try makeStyledPDF(pages: [
            [
                [bold("Chapter 1: The Arrival")],
                [],
                [regular("The ship docked before dawn with "), italic("frost clinging"), regular(" to every rope")],
                [regular("and spar along the stone quay while the crew stood watch.")]
            ],
            [
                [italic("Chapter 2: The Departure")],
                [],
                [regular("By noon the tide had turned and "), bold("every lantern"), regular(" along the pier")],
                [regular("was extinguished as thick fog rolled back over the bay.")]
            ]
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try PDFWorkConverter.convert(fileAt: url, fallbackTitle: "Test")
        #expect(result.chapters.map(\.title) == ["Chapter 1: The Arrival", "Chapter 2: The Departure"])
        #expect(result.chapters[0].bodyXHTML.contains("<em>frost clinging</em>"))
        #expect(result.chapters[1].bodyXHTML.contains("<strong>every lantern</strong>"))
        let allBodies = bodies(result)
        #expect(!allBodies.contains("<strong>Chapter"))
        #expect(!allBodies.contains("<em>Chapter"))

        // Headings and separators routed straight through HTMLWorkSanitizer also stay plain.
        let direct = HTMLWorkSanitizer.styledParagraphs(from: [
            PDFStyledBlock(
                text: "Chapter 3: Shadows",
                italicRanges: [NSRange(location: 0, length: 18)],
                boldRanges: [NSRange(location: 0, length: 18)]
            ),
            PDFStyledBlock(
                text: "* * *",
                italicRanges: [NSRange(location: 0, length: 5)],
                boldRanges: [NSRange(location: 0, length: 5)]
            )
        ])
        #expect(direct.contains("<p>Chapter 3: Shadows</p>"))
        #expect(direct.contains("<p>* * *</p>"))
        #expect(!direct.contains("<em>") && !direct.contains("<strong>"))
    }

    // MARK: - Bridge contract

    @Test func bridgeReturnsAccurateUTF16RangesAndPlainRuleBlocks() throws {
        let url = try makeStyledRulePDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let styledPages = try #require(KudosMuPDF.styledParagraphsPerPage(forPDFAtPath: url.path))
        let plainPages = try #require(KudosMuPDF.paragraphsPerPage(forPDFAtPath: url.path))
        #expect(styledPages.count == 1)
        #expect(styledPages[0].map(\.text) == plainPages[0])

        let blocks = styledPages[0]
        #expect(blocks.count == 3)

        let firstText = blocks[0].text as NSString
        let italics = blocks[0].italicRanges.map { firstText.substring(with: $0.rangeValue) }
        let bolds = blocks[0].boldRanges.map { firstText.substring(with: $0.rangeValue) }
        #expect(italics == ["whispered", "both"])
        #expect(bolds == ["shouted", "both"])

        #expect(blocks[1].text == "* * *")
        #expect(blocks[1].italicRanges.isEmpty)
        #expect(blocks[1].boldRanges.isEmpty)

        #expect(blocks[2].text.contains("After the break"))
        #expect(blocks[2].italicRanges.isEmpty)
        #expect(blocks[2].boldRanges.isEmpty)
    }

    // MARK: - Repair & inline XHTML unit tests

    @Test func paragraphRepairPreservesRangesThroughHeadersTrimmingSeparatorsAndMultiPageJoin() {
        let header = PDFStyledBlock(
            text: "The Weight of Water",
            italicRanges: [NSRange(location: 0, length: 19)]
        )
        let separator = PDFStyledBlock(
            text: "~~~",
            italicRanges: [NSRange(location: 0, length: 3)],
            boldRanges: [NSRange(location: 0, length: 3)]
        )

        let pages: [[PDFStyledBlock]] = [
            [
                header,
                PDFStyledBlock(
                    text: "  She followed the narrow trail  ",
                    italicRanges: [NSRange(location: 6, length: 8)] // "followed"
                ),
                PDFStyledBlock(text: "1")
            ],
            [
                header,
                PDFStyledBlock(
                    text: "through the dark pines",
                    boldRanges: [NSRange(location: 12, length: 4)] // "dark"
                ),
                PDFStyledBlock(text: "2")
            ],
            [
                header,
                PDFStyledBlock(
                    text: "until the lanterns shone.",
                    italicRanges: [NSRange(location: 10, length: 8)] // "lanterns"
                ),
                separator,
                PDFStyledBlock(text: "3")
            ],
            [
                header,
                PDFStyledBlock(
                    text: "Final page prose.",
                    boldRanges: [NSRange(location: 0, length: 5)] // "Final"
                ),
                PDFStyledBlock(text: "4")
            ]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired.count == 4)
        #expect(repaired[0].count == 1)
        #expect(repaired[1].isEmpty)
        #expect(repaired[2] == [PDFStyledBlock(text: "* * *")])
        #expect(repaired[3].count == 1)

        let joinedHTML = HTMLWorkSanitizer.inlineXHTML(for: repaired[0][0])
        #expect(joinedHTML == "She <em>followed</em> the narrow trail through the <strong>dark</strong> pines "
            + "until the <em>lanterns</em> shone.")
        #expect(HTMLWorkSanitizer.inlineXHTML(for: repaired[3][0]) == "<strong>Final</strong> page prose.")
    }

    @Test func inlineXHTMLHandlesOverlappingStylesAstralUnicodeAndAuthorNotes() {
        let crossing = PDFStyledBlock(
            text: "aaa bbb ccc",
            italicRanges: [NSRange(location: 4, length: 7)], // "bbb ccc"
            boldRanges: [NSRange(location: 0, length: 7)]    // "aaa bbb"
        )
        let crossingHTML = HTMLWorkSanitizer.inlineXHTML(for: crossing)
        #expect(crossingHTML == "<strong>aaa <em>bbb</em></strong><em> ccc</em>")
        #expect(isWellFormedXHTMLFragment("<p>\(crossingHTML)</p>"))

        let nested = PDFStyledBlock(
            text: "I never asked.",
            italicRanges: [NSRange(location: 0, length: 14)],
            boldRanges: [NSRange(location: 2, length: 5)] // "never"
        )
        let nestedHTML = HTMLWorkSanitizer.inlineXHTML(for: nested)
        #expect(nestedHTML == "<em>I </em><strong><em>never</em></strong><em> asked.</em>")
        #expect(isWellFormedXHTMLFragment("<p>\(nestedHTML)</p>"))

        // 🌟 is 2 UTF-16 code units; "bright" starts at UTF-16 offset 3.
        let astral = PDFStyledBlock(
            text: "🌟 bright",
            italicRanges: [NSRange(location: 3, length: 6)]
        )
        #expect(HTMLWorkSanitizer.inlineXHTML(for: astral) == "🌟 <em>bright</em>")

        let noteBody = HTMLWorkSanitizer.styledParagraphs(from: [
            PDFStyledBlock(
                text: "A/N: Please read carefully.",
                boldRanges: [NSRange(location: 17, length: 9)] // "carefully"
            ),
            PDFStyledBlock(text: "The story begins on a quiet morning.")
        ])
        #expect(noteBody.contains("<aside epub:type=\"note\" class=\"author-note\">"))
        #expect(noteBody.contains("<p>A/N: Please read <strong>carefully</strong>.</p>"))
        #expect(isWellFormedXHTMLFragment(noteBody))
    }
}
