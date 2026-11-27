import Foundation
import SwiftSoup
#if os(iOS)
import UIKit
#endif

/// Builds a readable, offline-safe HTML document and (on iOS) renders it to PDF
/// via `UIMarkupTextPrintFormatter` + `UIPrintPageRenderer` for beta reading.
nonisolated enum BetaPDFExporter {
    /// Produces a standalone printable HTML document with remote images and scripts
    /// stripped so PDF rendering can never make network requests.
    static func printableHTML(
        workTitle: String,
        chapterNumber: Int?,
        chapterTitle: String,
        bodyHTML: String
    ) -> String {
        let cleanBody = sanitizeBodyHTML(bodyHTML)
        let escapedWork = BetaDOCXWriter.escapeXML(workTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        let trimmedChapter = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let headingLine: String
        if let chapterNumber, chapterNumber > 0 {
            headingLine = trimmedChapter.isEmpty
                ? "Chapter \(chapterNumber)"
                : "Chapter \(chapterNumber) · \(trimmedChapter)"
        } else {
            headingLine = trimmedChapter.isEmpty ? "Chapter" : trimmedChapter
        }
        let escapedHeading = BetaDOCXWriter.escapeXML(headingLine)
        let workHeader = escapedWork.isEmpty ? "" : "<p class=\"work-title\">\(escapedWork)</p>"

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <style>
          body {
            font-family: Georgia, "Iowan Old Style", "New York", serif;
            font-size: 12pt;
            line-height: 1.6;
            color: #1A1A1A;
            margin: 0;
          }
          .work-title {
            font-family: -apple-system, Helvetica, sans-serif;
            font-size: 10pt;
            color: #555555;
            margin: 0 0 4pt 0;
          }
          h1.chapter-heading {
            font-size: 18pt;
            line-height: 1.25;
            margin: 0 0 18pt 0;
            padding-bottom: 8pt;
            border-bottom: 0.5pt solid #CCCCCC;
          }
          p { margin: 0 0 10pt 0; }
          blockquote {
            margin: 12pt 24pt;
            padding-left: 12pt;
            border-left: 2pt solid #CCCCCC;
          }
          hr {
            border: none;
            text-align: center;
            margin: 16pt 0;
          }
          hr::after { content: "* * *"; color: #555555; }
          a { color: #1A1A1A; text-decoration: underline; }
        </style>
        </head>
        <body>
        \(workHeader)
        <h1 class="chapter-heading">\(escapedHeading)</h1>
        \(cleanBody)
        </body>
        </html>
        """
    }

    private static func sanitizeBodyHTML(_ rawHTML: String) -> String {
        guard !rawHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        do {
            let allowlist = try Whitelist.relaxed()
                .removeTags("img")
                .addTags("hr", "s", "strike", "del", "ins", "center", "details", "summary", "small", "tt", "kbd")
                .addAttributes("p", "align")
                .addAttributes("div", "align")
                .addAttributes("h1", "align")
                .addAttributes("h2", "align")
                .addAttributes("h3", "align")
                .addAttributes("h4", "align")
                .addAttributes("h5", "align")
                .addAttributes("h6", "align")
            let dirty = try SwiftSoup.parseBodyFragment(rawHTML)
            let clean = try Cleaner(headWhitelist: nil, bodyWhitelist: allowlist).clean(dirty)
            clean.outputSettings().syntax(syntax: .xml).escapeMode(.base).prettyPrint(pretty: false)
            return try clean.body()?.html() ?? ""
        } catch {
            return "<p>\(BetaDOCXWriter.escapeXML(rawHTML))</p>"
        }
    }

    #if os(iOS)
    @MainActor
    static func renderPDF(
        workTitle: String,
        chapterNumber: Int?,
        chapterTitle: String,
        bodyHTML: String
    ) -> Data {
        let html = printableHTML(
            workTitle: workTitle,
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            bodyHTML: bodyHTML
        )
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let printableRect = pageRect.insetBy(dx: 72, dy: 72)
        renderer.setValue(NSValue(cgRect: pageRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")

        let pageCount = max(1, renderer.numberOfPages)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pageCount))

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return pdfRenderer.pdfData { context in
            for pageIndex in 0 ..< pageCount {
                context.beginPage()
                renderer.drawPage(at: pageIndex, in: pageRect)
            }
        }
    }
    #endif
}
