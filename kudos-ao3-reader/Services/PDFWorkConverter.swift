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

    /// Title for the front-matter chapter. "Preface" because that is what AO3's own
    /// EPUB export calls the same page.
    private static let prefaceTitle = "Preface"

    static func convert(fileAt url: URL, fallbackTitle: String) throws -> HTMLWorkConverter.Result {
        guard let document = PDFDocument(url: url) else {
            throw ImportedDocumentConverter.ConversionError.pdfUnreadable
        }
        // An encrypted PDF that never unlocked yields empty pages rather than an
        // error, which would otherwise import as a blank work.
        if document.isEncrypted, document.isLocked {
            throw ImportedDocumentConverter.ConversionError.pdfPasswordProtected
        }

        let pages = try pageBlocks(of: document, path: url.path)
        let cleaned = withoutRunningHeadersAndFooters(pages)

        let chapters = (outlineChapters(of: document, pageLines: cleaned)
            ?? textHeuristicChapters(pageLines: cleaned, fallbackTitle: fallbackTitle))
            .map(withoutEchoedTitle)
        guard !chapters.isEmpty else { throw ImportedDocumentConverter.ConversionError.noReadableText }

        var work = metadata(of: document, fallbackTitle: fallbackTitle)
        var finalChapters = chapters

        // calibre and FanFicFare open an exported fic with a metadata page, and it is
        // the only place a converted PDF can learn it came from fanfiction.net — which
        // is what the Library's origin badge reads.
        //
        // Parsed from the page's **raw** lines, not from `cleaned`. Those have been
        // through paragraph reflow, which merges this page's short ragged label lines
        // into one blob — and the parser then read `Storylink:` as part of `Story:`'s
        // value and produced junk like a rating of "MStatus: Complete".
        let rawFirstPage = KudosMuPDF.linesPerPage(forPDFAtPath: url.path)?.first
            ?? lines(of: document.page(at: 0)?.string ?? "")
        if let front = CalibreMetadataPage.parse(lines: rawFirstPage) {
            work = front.merged(into: work)
            // Re-render the preface from the parsed fields: the raw block is a label
            // list that reads badly as prose, and every value in it is now metadata.
            if let first = finalChapters.first, first.title == prefaceTitle {
                let body = HTMLWorkSanitizer.paragraphs(from: front.prefaceBlocks())
                if !body.isEmpty {
                    finalChapters[0] = .init(title: prefaceTitle, bodyXHTML: body)
                }
            }
        }

        return HTMLWorkConverter.Result(metadata: work, chapters: finalChapters)
    }

    // MARK: - Text extraction

    /// Paragraph blocks per page, ready to become `<p>` elements.
    ///
    /// Geometry first, `page.string` only as a fallback. That order is the whole
    /// lesson of the first attempt at this: **`page.string` inserts newlines at text
    /// *run* boundaries, not just at line ends.** A curly quote in a different font
    /// starts a new run, so one printed line arrives as several fragments — and any
    /// width-based paragraph test then reads each fragment as a paragraph end,
    /// shattering prose mid-sentence. Character geometry has no such ambiguity: a
    /// printed line is whatever shares a baseline.
    /// Paragraph blocks per page, ready to become `<p>` elements.
    ///
    /// MuPDF's structured text does the layout analysis: one *block* is one paragraph,
    /// and its lines are wrapped display lines. This replaced ~250 lines of geometry
    /// heuristics built on `PDFPage.string` + `characterBounds`, which is a text API
    /// rather than a layout one — it guarantees no reading order and returns
    /// unusable glyph boxes often enough to have produced five separate defects,
    /// the last of which silently moved prose into the wrong paragraph.
    ///
    /// Verified on a 171-page reference PDF: 493,826 non-whitespace characters,
    /// matching PDFKit's count for every single character (4,395 commas either way),
    /// but correctly ordered and grouped. See docs/PDF_ENGINE_MUPDF.md.
    ///
    /// PDFKit is still used for two things it is good at: document attributes, and
    /// rasterizing pages for the OCR fallback.
    private static func pageBlocks(of document: PDFDocument, path: String) throws -> [[String]] {
        guard let extracted = KudosMuPDF.paragraphsPerPage(forPDFAtPath: path), !extracted.isEmpty else {
            // MuPDF could not open it at all. PDFKit already opened it (the caller
            // checked), so the document exists but has no text MuPDF can reach —
            // treat it as a scan and let OCR decide.
            Log.library.notice("MuPDF returned no pages; falling back to OCR")
            let recognized = try ocrPages(of: document)
            guard !recognized.isEmpty else {
                throw ImportedDocumentConverter.ConversionError.pdfHasNoExtractableText
            }
            return recognized.map { ocrParagraphs($0) }
        }

        let pages = extracted.map { page in
            page.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let totalCharacters = pages.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }

        guard totalCharacters >= textLayerThreshold else {
            Log.library.info("PDF has no usable text layer (\(totalCharacters) chars); trying OCR")
            let recognized = try ocrPages(of: document)
            guard !recognized.isEmpty else {
                throw ImportedDocumentConverter.ConversionError.pdfHasNoExtractableText
            }
            return recognized.map { ocrParagraphs($0) }
        }

        // A document can carry text on most pages and an image on one — a scanned
        // title page, or a cover exported as a picture. Those pages are OCR'd
        // individually; without this they import as nothing at all, silently.
        return withOCRForEmptyPages(pages, of: document)
    }

    /// Fills in pages that yielded no text of their own by OCR'ing just those pages.
    ///
    /// Bounded by the same page budget as a full-document OCR, and the drop is logged
    /// rather than passed off as a complete conversion.
    private static func withOCRForEmptyPages(
        _ pages: [[String]],
        of document: PDFDocument
    ) -> [[String]] {
        let emptyPages = pages.indices.filter { pages[$0].isEmpty }
        guard !emptyPages.isEmpty else { return pages }

        var filled = pages
        let budgeted = emptyPages.prefix(maxOCRPages)
        if budgeted.count < emptyPages.count {
            Log.library.notice(
                "\(emptyPages.count) pages had no text layer; OCR ran on the first \(maxOCRPages)"
            )
        }
        for index in budgeted {
            guard let page = document.page(at: index), let image = render(page) else { continue }
            let recognized = recognizeText(in: image)
            guard !recognized.isEmpty else { continue }
            Log.library.info("Recovered page \(index + 1) of the PDF by OCR")
            filled[index] = ocrParagraphs(recognized)
        }
        return filled
    }

    private static func lines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// Drops a chapter's opening paragraph when it only repeats the chapter title.
    ///
    /// A PDF carries its title as ordinary page text, and `EPUBBuilder` already emits
    /// the chapter title as an `<h1>`, so without this the reader shows it twice —
    /// which it did, on the first real file this was tried against.
    private static func withoutEchoedTitle(_ chapter: EPUBBuilder.Chapter) -> EPUBBuilder.Chapter {
        var bodyLines = chapter.bodyXHTML.components(separatedBy: "\n")
        guard let first = bodyLines.first?.trimmingCharacters(in: .whitespaces),
              first == "<p>\(EPUBBuilder.escaped(chapter.title))</p>"
        else { return chapter }
        bodyLines.removeFirst()
        return .init(title: chapter.title, bodyXHTML: bodyLines.joined(separator: "\n"))
    }

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

    /// Joins OCR'd lines into paragraphs.
    ///
    /// Only the OCR path needs this now. MuPDF hands over real paragraph blocks, but
    /// Vision returns bare lines with no block structure, so a width heuristic is
    /// still the best available signal *there*: recognized body lines fill the
    /// measure, and a noticeably shorter line ends its paragraph.
    ///
    /// This is deliberately the *only* surviving piece of the old heuristic stack.
    /// The geometry-based version of it is gone — see `pageBlocks`.
    ///
    /// The signal used is the ragged right edge: body lines run to the full measure,
    /// so a line **noticeably shorter than the page's typical line** is the end of
    /// its paragraph (or a heading). Length in characters stands in for typeset
    /// width, which is close enough for prose in one font and needs no glyph metrics.
    ///
    /// Chosen over the obvious alternative — "a line ending in `.`/`!`/`?` ends a
    /// paragraph" — because fanfic is dialogue-heavy, and that rule turns every
    /// sentence into its own paragraph.
    private static func ocrParagraphs(_ lines: [String]) -> [String] {
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

        // Anything before the first outline entry is front matter — the title,
        // metadata and summary page that most fic PDFs open with. This loop used to
        // start at `marks[0].page` and drop those pages **silently**, losing a whole
        // page of the work with no error and nothing in the log. Named "Preface"
        // because that is what AO3's own EPUB export calls the same page.
        if let first = marks.first, first.page > 0 {
            let leading = pageLines[0..<min(first.page, pageLines.count)]
                .flatMap(\.self)
                .filter { !$0.isEmpty }
            let body = HTMLWorkSanitizer.paragraphs(from: leading)
            if !body.isEmpty {
                chapters.append(.init(title: prefaceTitle, bodyXHTML: body))
            }
        }

        for (offset, mark) in marks.enumerated() {
            let end = offset + 1 < marks.count ? marks[offset + 1].page : pageLines.count
            guard mark.page < end, mark.page < pageLines.count else { continue }
            // Already paragraph blocks (see `pageBlocks`), so no further reflow.
            let blocks = pageLines[mark.page..<min(end, pageLines.count)]
                .flatMap(\.self)
                .filter { !$0.isEmpty }
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
        // Blocks already carry a blank line between paragraphs, which is exactly the
        // shape the plain-text converter expects, so joining them is enough.
        let text = pageLines.flatMap { $0 + [""] }.joined(separator: "\n")
        guard let result = try? PlainTextWorkConverter.convert(
            text: text,
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
