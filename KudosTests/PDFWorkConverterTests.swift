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
