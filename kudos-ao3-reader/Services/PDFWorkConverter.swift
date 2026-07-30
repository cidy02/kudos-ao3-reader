import CoreGraphics
import Foundation
import OSLog
import PDFKit
import Vision

/// Converts a PDF into EPUB chapters.
///
/// Deliberately *not* a fixed-layout conversion. A PDF is a page-shaped artifact
/// and Kudos is a reflowable reader, so the goal here is to recover the prose and
/// let the reader lay it out — the same trade every "PDF to EPUB" tool makes,
/// except this one is honest that it is lossy. That lossiness is acceptable only
/// because `UserDocumentImport` archives the original PDF alongside the EPUB, so
/// nothing is destroyed.
///
/// Researched and rejected as unembeddable on iOS: calibre's `ebook-convert`
/// (Python), poppler's `pdftohtml` (desktop C++ with fontconfig/freetype), and
/// `pdf2htmlEX` — which emits *fixed*-layout EPUB and so defeats the point.
/// PDFKit and Vision are on-device, free, and already on both platforms.
nonisolated enum PDFWorkConverter {
    /// Hard cap on OCR'd pages. OCR is ~0.1-1s per page, so a 600-page scan would
    /// otherwise hang the import for minutes with no way to tell it to stop. Pages
    /// past the cap are dropped and the drop is logged — never silently truncated.
    private static let maxOCRPages = 60

    /// Below this many characters across the whole document, the text layer is
    /// treated as absent (a scan, or a PDF whose fonts carry no usable encoding)
    /// and OCR takes over.
    private static let textLayerThreshold = 200

    static func convert(fileAt url: URL, fallbackTitle: String) throws -> HTMLWorkConverter.Result {
        guard let document = PDFDocument(url: url) else {
            throw ImportedDocumentConverter.ConversionError.pdfUnreadable
        }
        // An encrypted PDF that never unlocked yields empty pages rather than an
        // error, which would otherwise import as a blank work.
        if document.isEncrypted, document.isLocked {
            throw ImportedDocumentConverter.ConversionError.pdfPasswordProtected
        }

        let pages = try pageTexts(of: document)
        let cleaned = withoutRunningHeadersAndFooters(pages)

        let chapters = outlineChapters(of: document, pageLines: cleaned)
            ?? textHeuristicChapters(pageLines: cleaned, fallbackTitle: fallbackTitle)
        guard !chapters.isEmpty else { throw ImportedDocumentConverter.ConversionError.noReadableText }

        return HTMLWorkConverter.Result(
            metadata: metadata(of: document, fallbackTitle: fallbackTitle),
            chapters: chapters
        )
    }

    // MARK: - Text extraction

    /// One entry per page, each already split into lines. Falls back to OCR for the
    /// whole document when its text layer is missing or unusably thin.
    private static func pageTexts(of document: PDFDocument) throws -> [[String]] {
        var pages: [[String]] = []
        var totalCharacters = 0
        for index in 0..<document.pageCount {
            let text = document.page(at: index)?.string ?? ""
            totalCharacters += text.count
            pages.append(lines(of: text))
        }

        guard totalCharacters < textLayerThreshold else { return pages }

        Log.library.info("PDF has no usable text layer (\(totalCharacters) chars); trying OCR")
        let recognized = try ocrPages(of: document)
        guard !recognized.isEmpty else {
            throw ImportedDocumentConverter.ConversionError.pdfHasNoExtractableText
        }
        return recognized
    }

    private static func lines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    // MARK: - OCR

    /// Recognizes text on each page image with Vision. Synchronous by design: the
    /// caller already runs off the main actor inside a detached task.
    private static func ocrPages(of document: PDFDocument) throws -> [[String]] {
        let pageCount = min(document.pageCount, maxOCRPages)
        if document.pageCount > maxOCRPages {
            Log.library.notice(
                "OCR capped at \(maxOCRPages) of \(document.pageCount) pages; the rest were dropped"
            )
        }

        var pages: [[String]] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index), let image = render(page) else {
                pages.append([])
                continue
            }
            pages.append(recognizeText(in: image))
        }
        return pages
    }

    /// Rasterizes a page through CoreGraphics rather than `PDFPage.thumbnail`,
    /// which returns `UIImage` on iOS and `NSImage` on macOS — this keeps one code
    /// path for both platforms and hands Vision a `CGImage` directly.
    private static func render(_ page: PDFPage, scale: CGFloat = 2) -> CGImage? {
        guard let pageRef = page.pageRef else { return nil }
        let box = page.bounds(for: .mediaBox)
        let width = Int(box.width * scale)
        let height = Int(box.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return nil }

        // White background: OCR on a transparent-black canvas recognizes nothing.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.origin.x, y: -box.origin.y)
        context.drawPDFPage(pageRef)
        return context.makeImage()
    }

    private static func recognizeText(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Fanfic is prose, so the language model helps more than it costs.
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.library.error("OCR failed for a page: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }

    // MARK: - Cleanup

    /// Drops page numbers and running headers/footers.
    ///
    /// These are the difference between a readable conversion and one with a stray
    /// title line every few paragraphs. A line is dropped when it appears at the
    /// top or bottom of many pages, or is bare digits — frequency is the signal,
    /// because a running header repeats by definition and prose does not.
    private static func withoutRunningHeadersAndFooters(_ pages: [[String]]) -> [[String]] {
        guard pages.count >= 4 else { return pages }

        var edgeCounts: [String: Int] = [:]
        for page in pages {
            let meaningful = page.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !meaningful.isEmpty else { continue }
            for candidate in Set([meaningful.first, meaningful.last].compactMap(\.self)) {
                edgeCounts[candidate, default: 0] += 1
            }
        }

        // Repeating on a third of the pages is a header, not a coincidence.
        let threshold = max(3, pages.count / 3)
        let repeated = Set(edgeCounts.filter { $0.value >= threshold }.keys)

        return pages.map { page in
            page.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return true }
                if repeated.contains(trimmed) { return false }
                // Bare page numbers, with or without decoration ("- 12 -", "12.").
                return trimmed.range(of: #"^[\-–—\s]*\d{1,4}[.\-–—\s]*$"#, options: .regularExpression) == nil
            }
        }
    }

    /// Rebuilds paragraph boundaries, which a PDF does not record.
    ///
    /// This is the crux of PDF conversion quality. `PDFPage.string` yields one entry
    /// per *display* line and — crucially — no blank lines, because a PDF separates
    /// paragraphs with vertical space rather than with any character. Treating each
    /// line as a paragraph produces unreadable output; joining everything produces
    /// one giant wall.
    ///
    /// The signal used is the ragged right edge: body lines run to the full measure,
    /// so a line **noticeably shorter than the page's typical line** is the end of
    /// its paragraph (or a heading). Length in characters stands in for typeset
    /// width, which is close enough for prose in one font and needs no glyph metrics.
    ///
    /// Chosen over the obvious alternative — "a line ending in `.`/`!`/`?` ends a
    /// paragraph" — because fanfic is dialogue-heavy, and that rule turns every
    /// sentence into its own paragraph.
    private static func reflowed(_ lines: [String]) -> [String] {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        let widths = trimmed.filter { !$0.isEmpty }.map(\.count).sorted()
        guard !widths.isEmpty else { return [] }

        // The "measure" is the 90th-percentile line width, not the median: body lines
        // fill the measure and paragraph-final lines are short, so a median is
        // dragged down by the very lines we are trying to detect. The 90th percentile
        // rather than the maximum so one freak long line (a bare URL) cannot inflate
        // it. A line below 85% of the measure is ragged, i.e. ends its paragraph.
        let measure = widths[Int(0.9 * Double(widths.count - 1))]
        let raggedWidth = Int(Double(measure) * 0.85)

        var result: [String] = []
        var current = ""

        func flush() {
            let paragraph = current.trimmingCharacters(in: .whitespaces)
            if !paragraph.isEmpty {
                result.append(paragraph)
                result.append("")
            }
            current = ""
        }

        for line in trimmed {
            guard !line.isEmpty else {
                flush()
                continue
            }
            // A heading always stands alone. Without this, "Chapter 2" followed
            // immediately by prose merges into one block and the chapter split later
            // mistakes the whole first sentence for the chapter's title.
            let isHeading = PlainTextWorkConverter.isChapterHeading(line)
            if isHeading { flush() }

            // A trailing hyphen means a word was split across lines: rejoin it with
            // neither the hyphen nor a space.
            if current.hasSuffix("-") {
                current = String(current.dropLast()) + line
            } else if current.isEmpty {
                current = line
            } else {
                current += " " + line
            }
            if isHeading || line.count < raggedWidth { flush() }
        }
        flush()
        return result
    }

    // MARK: - Chapters

    /// Uses the PDF's own outline when it has one — the only structural signal a
    /// PDF ever offers, and far better than guessing from the prose. calibre and
    /// Word both write outlines, so this is the common case for a converted fic.
    private static func outlineChapters(
        of document: PDFDocument,
        pageLines: [[String]]
    ) -> [EPUBBuilder.Chapter]? {
        guard let root = document.outlineRoot, root.numberOfChildren > 1 else { return nil }

        var marks: [(title: String, page: Int)] = []
        for index in 0..<root.numberOfChildren {
            guard let child = root.child(at: index),
                  let page = child.destination?.page ?? child.action.flatMap(destinationPage),
                  let pageIndex = document.index(for: page) as Int?
            else { continue }
            let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            marks.append((title.isEmpty ? "Chapter \(marks.count + 1)" : title, pageIndex))
        }
        guard marks.count > 1 else { return nil }

        var chapters: [EPUBBuilder.Chapter] = []
        for (offset, mark) in marks.enumerated() {
            let end = offset + 1 < marks.count ? marks[offset + 1].page : pageLines.count
            guard mark.page < end, mark.page < pageLines.count else { continue }
            let slice = pageLines[mark.page..<min(end, pageLines.count)].flatMap { $0 + [""] }
            let blocks = PlainTextWorkConverter.paragraphs(of: reflowed(slice))
            let body = HTMLWorkSanitizer.paragraphs(from: blocks)
            guard !body.isEmpty else { continue }
            chapters.append(.init(title: mark.title, bodyXHTML: body))
        }
        return chapters.isEmpty ? nil : chapters
    }

    private static func destinationPage(_ action: PDFAction) -> PDFPage? {
        (action as? PDFActionGoTo)?.destination.page
    }

    /// No outline: flatten the whole document and reuse the plain-text converter's
    /// chapter heuristics, so PDFs and `.txt` files split on the same rules and
    /// there is only one place where "what looks like a chapter heading" is decided.
    private static func textHeuristicChapters(
        pageLines: [[String]],
        fallbackTitle: String
    ) -> [EPUBBuilder.Chapter] {
        let flattened = reflowed(pageLines.flatMap { $0 + [""] })
        guard let result = try? PlainTextWorkConverter.convert(
            text: flattened.joined(separator: "\n"),
            fallbackTitle: fallbackTitle
        ) else { return [] }
        return result.chapters
    }

    // MARK: - Metadata

    private static func metadata(of document: PDFDocument, fallbackTitle: String) -> EPUBBuilder.Metadata {
        let attributes = document.documentAttributes ?? [:]

        func string(_ key: PDFDocumentAttribute) -> String {
            (attributes[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let title = string(.titleAttribute)
        // Keywords land as `dc:subject`, which is where the importer already looks
        // for tags — calibre writes a fic's AO3 tags there when it makes the PDF.
        var subjects: [String] = []
        // Spelled out because `documentAttributes` is `[AnyHashable: Any]`, so the
        // attribute enum cannot be inferred from the subscript alone.
        if let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            subjects = keywords
        } else {
            // PDF writers disagree on whether Keywords is an array or one delimited
            // string; calibre writes the string form.
            let raw = string(.keywordsAttribute)
            if !raw.isEmpty {
                subjects = raw.components(separatedBy: CharacterSet(charactersIn: ",;"))
            }
        }

        return EPUBBuilder.Metadata(
            title: title.isEmpty ? fallbackTitle : title,
            author: string(.authorAttribute),
            summary: string(.subjectAttribute),
            sourceURL: EPUBMetadata.canonicalAO3WorkURL(in: string(.subjectAttribute)) ?? "",
            subjects: subjects
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}
