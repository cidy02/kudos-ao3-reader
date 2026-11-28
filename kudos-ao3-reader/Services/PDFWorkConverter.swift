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
        let cleaned = PDFParagraphRepair.withoutRunningHeadersAndFooters(pages)
        let repaired = PDFParagraphRepair.joinBrokenParagraphs(cleaned)

        let chapters = (outlineChapters(of: document, pageBlocks: repaired)
            ?? textHeuristicChapters(pageBlocks: repaired, fallbackTitle: fallbackTitle))
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
            // The tag block is what `AO3EPUBMetadataScanner` reads on import to fill in
            // rating, fandom, status, words and chapters — fields that were empty on
            // every converted work, because only AO3's own markup ever populated them.
            // It has to be emitted whichever chapter strategy ran: a PDF with no
            // outline has no Preface to put it in, and a first draft of this only
            // handled the outline case, so a calibre export without an outline still
            // recovered nothing.
            let block = front.ao3StyleTagBlockXHTML()
            if let first = finalChapters.first, first.title == prefaceTitle {
                let prose = HTMLWorkSanitizer.paragraphs(from: front.prefaceBlocks())
                let body = [block, prose].filter { !$0.isEmpty }.joined(separator: "\n")
                if !body.isEmpty {
                    finalChapters[0] = .init(title: prefaceTitle, bodyXHTML: body)
                }
            } else if !block.isEmpty, let first = finalChapters.first {
                // No preface: the metadata page's text is already inside the first
                // chapter as prose, so only the block is prepended — re-adding the
                // prose would print it twice.
                finalChapters[0] = .init(
                    title: first.title,
                    bodyXHTML: block + "\n" + first.bodyXHTML
                )
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
    private static func pageBlocks(of document: PDFDocument, path: String) throws -> [[PDFStyledBlock]] {
        guard let extracted = KudosMuPDF.styledParagraphsPerPage(forPDFAtPath: path), !extracted.isEmpty else {
            // MuPDF could not open it at all. PDFKit already opened it (the caller
            // checked), so the document exists but has no text MuPDF can reach —
            // treat it as a scan and let OCR decide.
            Log.library.notice("MuPDF returned no pages; falling back to OCR")
            let recognized = try ocrPages(of: document)
            guard !recognized.isEmpty else {
                throw ImportedDocumentConverter.ConversionError.pdfHasNoExtractableText
            }
            return recognized.map { ocrParagraphs($0).map { PDFStyledBlock(text: $0) } }
        }

        let pages: [[PDFStyledBlock]] = extracted.map { page in
            page.map { PDFStyledBlock($0).trimmed() }
                .filter { !$0.text.isEmpty }
        }
        let totalCharacters = pages.reduce(0) { $0 + $1.reduce(0) { $0 + $1.text.count } }

        guard totalCharacters >= textLayerThreshold else {
            Log.library.info("PDF has no usable text layer (\(totalCharacters) chars); trying OCR")
            let recognized = try ocrPages(of: document)
            guard !recognized.isEmpty else {
                throw ImportedDocumentConverter.ConversionError.pdfHasNoExtractableText
            }
            return recognized.map { ocrParagraphs($0).map { PDFStyledBlock(text: $0) } }
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
        _ pages: [[PDFStyledBlock]],
        of document: PDFDocument
    ) -> [[PDFStyledBlock]] {
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
            filled[index] = ocrParagraphs(recognized).map { PDFStyledBlock(text: $0) }
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
              first.hasPrefix("<p>"), first.hasSuffix("</p>")
        else { return chapter }
        let inner = String(first.dropFirst(3).dropLast(4))
            .replacingOccurrences(of: "<em>", with: "")
            .replacingOccurrences(of: "</em>", with: "")
            .replacingOccurrences(of: "<strong>", with: "")
            .replacingOccurrences(of: "</strong>", with: "")
        guard inner == EPUBBuilder.escaped(chapter.title) else { return chapter }
        bodyLines.removeFirst()
        return EPUBBuilder.Chapter(title: chapter.title, bodyXHTML: bodyLines.joined(separator: "\n"))
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
    static func outlineChapters(
        of document: PDFDocument,
        pageBlocks: [[PDFStyledBlock]]
    ) -> [EPUBBuilder.Chapter]? {
        guard let root = document.outlineRoot, root.numberOfChildren > 1 else { return nil }

        var marks: [(rawLabel: String?, page: Int)] = []
        for index in 0..<root.numberOfChildren {
            guard let child = root.child(at: index),
                  let page = child.destination?.page ?? child.action.flatMap(destinationPage),
                  let pageIndex = document.index(for: page) as Int?
            else { continue }
            marks.append((child.label, pageIndex))
        }
        guard marks.count > 1 else { return nil }

        var chapters: [EPUBBuilder.Chapter] = []

        // Anything before the first outline entry is front matter — the title,
        // metadata and summary page that most fic PDFs open with. This loop used to
        // start at `marks[0].page` and drop those pages **silently**, losing a whole
        // page of the work with no error and nothing in the log. Named "Preface"
        // because that is what AO3's own EPUB export calls the same page.
        if let first = marks.first, first.page > 0 {
            let leading = pageBlocks[0..<min(first.page, pageBlocks.count)]
                .flatMap(\.self)
                .filter { !$0.text.isEmpty }
            let body = replacingInternalNewlinesWithBreaks(HTMLWorkSanitizer.styledParagraphs(from: leading))
            if !body.isEmpty {
                chapters.append(EPUBBuilder.Chapter(title: prefaceTitle, bodyXHTML: body))
            }
        }

        var chapterNumber = 0
        for (offset, mark) in marks.enumerated() {
            let end = offset + 1 < marks.count ? marks[offset + 1].page : pageBlocks.count
            guard mark.page < end, mark.page < pageBlocks.count else { continue }
            // Already paragraph blocks (see `pageBlocks`), so no further reflow.
            let blocks = pageBlocks[mark.page..<min(end, pageBlocks.count)]
                .flatMap(\.self)
                .filter { !$0.text.isEmpty }
            let body = replacingInternalNewlinesWithBreaks(HTMLWorkSanitizer.styledParagraphs(from: blocks))
            guard !body.isEmpty else { continue }
            chapterNumber += 1
            let title = resolvedOutlineTitle(
                rawLabel: mark.rawLabel,
                blocks: blocks,
                chapterNumber: chapterNumber
            )
            chapters.append(EPUBBuilder.Chapter(title: title, bodyXHTML: body))
        }
        return chapters.isEmpty ? nil : chapters
    }

    private static let maxOutlineTitleLength = 100

    /// Validates a PDF outline entry's label against the chapter's extracted blocks.
    ///
    /// Exporters like calibre copy up to 1,000 characters of the chapter's opening
    /// text into the outline when a chapter has no `<h1>`/`<h2>`. A label longer than
    /// 100 characters, empty, or matching the chapter's opening prose is replaced by
    /// the chapter's heading line, or `"Chapter N"` if none looks like a heading.
    static func resolvedOutlineTitle(
        rawLabel: String?,
        blocks: [PDFStyledBlock],
        chapterNumber: Int
    ) -> String {
        let label = normalizedSingleLine(rawLabel ?? "")
        if !label.isEmpty,
           label.count <= maxOutlineTitleLength,
           !isOutlineLabelOpeningProse(label, in: blocks) {
            return label
        }
        if let heading = chapterHeadingLine(in: blocks, outlineLabel: label) {
            return heading
        }
        return "Chapter \(chapterNumber)"
    }

    /// Converts literal newlines carried inside `<p>...</p>` blocks (verse/lyrics line
    /// breaks preserved by `KudosMuPDF`) into XHTML `<br/>` elements while leaving the
    /// top-level newlines between block elements intact.
    static func replacingInternalNewlinesWithBreaks(_ xhtml: String) -> String {
        guard xhtml.contains("\n") else { return xhtml }
        var output = ""
        output.reserveCapacity(xhtml.count)
        var cursor = xhtml.startIndex
        while let open = xhtml.range(of: "<p>", range: cursor..<xhtml.endIndex),
              let close = xhtml.range(of: "</p>", range: open.upperBound..<xhtml.endIndex) {
            output += xhtml[cursor..<open.upperBound]
            let inner = xhtml[open.upperBound..<close.lowerBound]
            output += inner.replacingOccurrences(of: "\n", with: "<br/>")
            output += "</p>"
            cursor = close.upperBound
        }
        output += xhtml[cursor..<xhtml.endIndex]
        return output
    }

    private static func normalizedSingleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func isOutlineLabelOpeningProse(_ label: String, in blocks: [PDFStyledBlock]) -> Bool {
        let opening = blocks.prefix(4).map { normalizedSingleLine($0.text) }.filter { !$0.isEmpty }
        guard let first = opening.first else { return false }

        // Multi-block concatenation (e.g. heading + scene break/note/opening prose).
        if opening.count >= 2, label.hasPrefix(first + " ") {
            let tail = String(label.dropFirst(first.count + 1))
            let second = opening[1]
            let secondMatches = second.hasPrefix(tail) || tail.hasPrefix(second)
            let thirdMatches = opening.count >= 3 && (opening[2].hasPrefix(tail) || tail.hasPrefix(opening[2]))
            if secondMatches || thirdMatches {
                let secondIsProseOrApparatus = PDFParagraphRepair.isSeparator(second)
                    || looksLikeProseParagraph(second)
                    || AuthorNoteDetector.noteIndices(in: [second]).contains(0)
                    || thirdMatches
                if secondIsProseOrApparatus {
                    return true
                }
            }
        }

        // Truncated excerpt of a long opening paragraph (`"The rain had stopped…"`).
        let strippedStem = label
            .replacingOccurrences(of: #"(?:\.\.\.|…)+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if first.count > maxOutlineTitleLength,
           strippedStem.count >= 12,
           first.hasPrefix(strippedStem) {
            return true
        }

        // Direct match (or long prefix) of an opening prose paragraph or author's note.
        // A short first block equal to the label is the chapter's own heading, even when it is quoted or ends in a full
        // stop (`"You Can't Go Home Again"`, `Ten Years Later.`): only a long one is opening prose (Sonnet's review).
        if !PDFParagraphRepair.isExplicitChapterHeading(first),
           label == first || (strippedStem.count >= 20 && first.hasPrefix(strippedStem)),
           first.count > 60 && looksLikeProseParagraph(first) || AuthorNoteDetector.noteIndices(in: [first]).contains(0) {
            return true
        }

        return false
    }

    private static func looksLikeProseParagraph(_ text: String) -> Bool {
        if text.count > maxOutlineTitleLength || text.contains("\n") { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let openingQuotes = CharacterSet(charactersIn: "\"“'‘«‹")
        let closingQuotes = CharacterSet(charactersIn: "\"”'’»›")
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        if let first = trimmed.unicodeScalars.first, openingQuotes.contains(first), words.count >= 3 {
            return true
        }
        if let last = trimmed.unicodeScalars.last, closingQuotes.contains(last), words.count >= 3 {
            return true
        }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("…") {
            return words.count >= 4
        }
        let endsExclamatory = trimmed.hasSuffix("!") || trimmed.hasSuffix("?")
        if endsExclamatory, words.count >= 8 {
            return true
        }
        return false
    }

    private static func chapterHeadingLine(in blocks: [PDFStyledBlock], outlineLabel: String) -> String? {
        guard let firstBlock = blocks.first else { return nil }
        let rawFirst = firstBlock.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawFirst.isEmpty,
              !rawFirst.contains("\n"),
              rawFirst.count <= maxOutlineTitleLength,
              !PDFParagraphRepair.isSeparator(rawFirst),
              !AuthorNoteDetector.noteIndices(in: [rawFirst]).contains(0)
        else { return nil }

        let candidate = normalizedSingleLine(rawFirst)
        if PDFParagraphRepair.isExplicitChapterHeading(candidate) {
            return candidate
        }
        if looksLikeProseParagraph(candidate) {
            return nil
        }
        // Reject sentence/salutation fragments like "Cold.", "Dear Maren,", "Someone wrote:".
        if let last = candidate.last, ".…,;:".contains(last) {
            return nil
        }
        let fullyBold = isFullyStyled(firstBlock.boldRanges, in: firstBlock.text)
        let outlineStartsWithHeading = !outlineLabel.isEmpty && outlineLabel.hasPrefix(candidate + " ")
        if fullyBold || outlineStartsWithHeading {
            return candidate
        }
        return nil
    }

    private static func isFullyStyled(_ ranges: [NSRange], in text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ranges.isEmpty else { return false }
        let covered = ranges.reduce(0) { $0 + $1.length }
        return covered >= trimmed.utf16.count
    }

    private static func destinationPage(_ action: PDFAction) -> PDFPage? {
        (action as? PDFActionGoTo)?.destination.page
    }

    /// Stands in for a scene break so the plain-text converter does not treat `* * *` as a chapter heading.
    /// Only a paragraph that is this character is restored: the character can occur in real PDF text, and replacing
    /// every occurrence would turn that text into `* * *` here while the outline path left it alone.
    /// `HTMLWorkSanitizer.paragraphs` keeps it (it escapes `& < > " '` only), so the paragraph still matches.
    private static let sceneBreakPlaceholder = "\u{E000}"

    /// No outline: flatten the whole document and reuse the plain-text converter's
    /// chapter heuristics, so PDFs and `.txt` files split on the same rules and
    /// there is only one place where "what looks like a chapter heading" is decided.
    private static func textHeuristicChapters(
        pageBlocks: [[PDFStyledBlock]],
        fallbackTitle: String
    ) -> [EPUBBuilder.Chapter] {
        // `PlainTextWorkConverter` treats a `* * *` line as a chapter divider (right for .txt imports), which would turn
        // every scene break in a PDF without an outline into a new untitled chapter; a placeholder carries each break
        // through and becomes `* * *` again in the chapter body.
        let separator = PDFParagraphRepair.normalizedSeparator
        let blocks = pageBlocks
            .flatMap(\.self)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.text == separator ? PDFStyledBlock(text: sceneBreakPlaceholder) : $0 }
        guard let result = try? PlainTextWorkConverter.convert(
            blocks: blocks,
            fallbackTitle: fallbackTitle
        ) else { return [] }
        let marker = "<p>\(sceneBreakPlaceholder)</p>"
        let restored = "<p>\(separator)</p>"
        return result.chapters.map {
            let body = replacingInternalNewlinesWithBreaks(
                $0.bodyXHTML.replacingOccurrences(of: marker, with: restored)
            )
            return .init(title: $0.title, bodyXHTML: body)
        }
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
