import Foundation

/// A paragraph block together with UTF-16 ranges for inline italic and bold runs.
nonisolated struct PDFStyledBlock: Equatable, Sendable {
    var text: String
    var italicRanges: [NSRange]
    var boldRanges: [NSRange]

    init(text: String, italicRanges: [NSRange] = [], boldRanges: [NSRange] = []) {
        self.text = text
        self.italicRanges = italicRanges
        self.boldRanges = boldRanges
    }

    init(_ block: KudosPDFBlock) {
        self.text = block.text
        self.italicRanges = block.italicRanges.map(\.rangeValue)
        self.boldRanges = block.boldRanges.map(\.rangeValue)
    }

    /// Trims leading and trailing whitespace/newlines while keeping all style ranges
    /// aligned to the exact same characters.
    func trimmed() -> PDFStyledBlock {
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        while start < scalars.endIndex,
              CharacterSet.whitespacesAndNewlines.contains(scalars[start]) {
            start = scalars.index(after: start)
        }
        var end = scalars.endIndex
        while end > start {
            let prev = scalars.index(before: end)
            if CharacterSet.whitespacesAndNewlines.contains(scalars[prev]) {
                end = prev
            } else {
                break
            }
        }
        guard start < end else { return PDFStyledBlock(text: "") }

        let trimmedText = String(scalars[start..<end])
        let leadingUTF16 = text.utf16.distance(from: text.utf16.startIndex, to: start)
        let keptLength = trimmedText.utf16.count
        return PDFStyledBlock(
            text: trimmedText,
            italicRanges: Self.shiftedAndClamped(italicRanges, by: -leadingUTF16, limit: keptLength),
            boldRanges: Self.shiftedAndClamped(boldRanges, by: -leadingUTF16, limit: keptLength)
        )
    }

    /// Joins `self` and `other` with one space, shifting `other`'s ranges past the join
    /// and bridging adjacent runs separated only by that space.
    func joinedWithSpace(to other: PDFStyledBlock) -> PDFStyledBlock {
        let joinedText = text + " " + other.text
        let offset = text.utf16.count + 1
        let shiftedItalic = other.italicRanges.map {
            NSRange(location: $0.location + offset, length: $0.length)
        }
        let shiftedBold = other.boldRanges.map {
            NSRange(location: $0.location + offset, length: $0.length)
        }
        return PDFStyledBlock(
            text: joinedText,
            italicRanges: Self.mergedRanges(italicRanges + shiftedItalic, in: joinedText),
            boldRanges: Self.mergedRanges(boldRanges + shiftedBold, in: joinedText)
        )
    }

    /// Merges overlapping, adjacent, or single-space-separated UTF-16 ranges in `text`.
    static func mergedRanges(_ ranges: [NSRange], in text: String) -> [NSRange] {
        let units = Array(text.utf16)
        let limit = units.count
        guard limit > 0, !ranges.isEmpty else { return [] }

        let sorted = ranges
            .compactMap { range -> NSRange? in
                guard range.length > 0, range.location < limit else { return nil }
                let start = max(0, range.location)
                let end = min(limit, range.location + range.length)
                return end > start ? NSRange(location: start, length: end - start) : nil
            }
            .sorted { lhs, rhs in
                lhs.location != rhs.location ? lhs.location < rhs.location : lhs.length < rhs.length
            }

        var merged: [NSRange] = []
        for range in sorted {
            if let prev = merged.last {
                let prevEnd = prev.location + prev.length
                let adjacent = range.location <= prevEnd
                let singleSpace = !adjacent
                    && range.location == prevEnd + 1
                    && (units[prevEnd] == 0x0020 || units[prevEnd] == 0x00A0)
                if adjacent || singleSpace {
                    let newEnd = max(prevEnd, range.location + range.length)
                    merged[merged.count - 1] = NSRange(location: prev.location, length: newEnd - prev.location)
                    continue
                }
            }
            merged.append(range)
        }
        return merged
    }

    private static func shiftedAndClamped(_ ranges: [NSRange], by delta: Int, limit: Int) -> [NSRange] {
        guard limit > 0, !ranges.isEmpty else { return [] }
        return ranges.compactMap { range in
            guard range.length > 0 else { return nil }
            let start = max(0, range.location + delta)
            let end = min(limit, range.location + range.length + delta)
            return end > start ? NSRange(location: start, length: end - start) : nil
        }
    }
}

/// Cleans per-page PDF paragraph blocks before chapter assembly.
///
/// MuPDF extracts one array of paragraph blocks per page, so a paragraph that wraps
/// across a page break — or changes spacing or italics mid-paragraph — arrives split
/// into two blocks. Scene breaks that happen to land at a page edge were also caught
/// by the running-header filter and deleted across the whole document.
///
/// Every function here is pure and preserves page count so
/// `PDFWorkConverter.outlineChapters` can still slice by PDF page index.
nonisolated enum PDFParagraphRepair {
    /// Canonical rendering for every recognised scene break.
    static let normalizedSeparator = "* * *"

    /// Minimum length for a block ending in a lowercase letter to join into a
    /// capitalised next block (e.g. a proper noun: "…she said to / Harry"). Shorter
    /// lines before a capital stay separate so titles and headings survive.
    private static let longParagraphThreshold = 60

    private static let maxSeparatorLength = 30
    private static let maxPureOrnamentLength = 12

    /// Core symbols that mark a scene break on a short symbol-only line (or paired
    /// with an `o0o`/`xXx` ornament).
    private static let separatorSymbols: Set<Character> = Set("*~#•·=_-–—❦✦◆◇○●+§⁂")
    private static let ornamentCharacters: Set<Character> = Set("oO0xX")
    private static let ornamentLetters: Set<Character> = Set("oOxX")

    private static let closingDelimiters: Set<Character> = Set("\"”'’)]»›")
    private static let closingQuotes: Set<Character> = Set("\"”'’»›")
    private static let terminalPunctuation: Set<Character> = Set(".!?…")
    private static let openingQuotes: Set<Character> = Set("\"“'‘«‹")
    private static let hyphensAndDashes: Set<Character> = Set("-–—")

    /// Whole-line headings that `chapter` / `part` patterns miss. Matched as the
    /// entire block, or `epilogue: subtitle`, so "the epilogue" still joins.
    private static let standaloneHeadings: Set<String> = [
        "prologue", "epilogue", "interlude", "preface", "afterword"
    ]

    /// Runs the full cleanup pipeline: removes running headers, footers, and bare
    /// page numbers while sparing separators, then normalises separators and rejoins
    /// paragraphs split across page breaks. Page count stays the same so outline
    /// slices still line up with PDF page indexes.
    static func repair(_ pages: [[String]]) -> [[String]] {
        repair(pages.map { $0.map { PDFStyledBlock(text: $0) } }).map { $0.map(\.text) }
    }

    static func repair(_ pages: [[PDFStyledBlock]]) -> [[PDFStyledBlock]] {
        joinBrokenParagraphs(withoutRunningHeadersAndFooters(pages))
    }

    // MARK: - Running headers & footers

    /// Drops bare page numbers and lines that repeat at the top or bottom of pages.
    ///
    /// A repeated header or footer is removed only where it sits as the first or last
    /// non-empty block of a page, never mid-page, and scene-break separators are
    /// never removed regardless of how often they land on a page edge. A sentence
    /// that repeats there is a refrain, not a footer. The first copy of a repeated
    /// chapter heading stays; later copies are the running header.
    static func withoutRunningHeadersAndFooters(_ pages: [[String]]) -> [[String]] {
        withoutRunningHeadersAndFooters(pages.map { $0.map { PDFStyledBlock(text: $0) } })
            .map { $0.map(\.text) }
    }

    static func withoutRunningHeadersAndFooters(_ pages: [[PDFStyledBlock]]) -> [[PDFStyledBlock]] {
        guard pages.count >= 4 else { return pages }

        // Strip bare page numbers at the edges first so a running footer sitting
        // directly above a page number still sits at the page edge when frequencies
        // are counted. A year or list number in the body is not a page number.
        let withoutPageNumbers: [[PDFStyledBlock]] = pages.map { page in
            guard let edges = edgeIndices(of: page) else { return page }
            return page.enumerated().compactMap { index, block -> PDFStyledBlock? in
                guard index == edges.first || index == edges.last else { return block }
                let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return block }
                return isBarePageNumber(trimmed) ? nil : block
            }
        }

        // One pass per page: a line that is both the header and the footer counts once.
        var edgeCounts: [String: Int] = [:]
        for page in withoutPageNumbers {
            guard let edges = edgeIndices(of: page) else { continue }
            let firstText = page[edges.first].text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastText = page[edges.last].text.trimmingCharacters(in: .whitespacesAndNewlines)
            var candidates: Set<String> = []
            if isRepeatedEdgeCandidate(firstText) { candidates.insert(firstText) }
            if isRepeatedEdgeCandidate(lastText) { candidates.insert(lastText) }
            for candidate in candidates {
                edgeCounts[candidate, default: 0] += 1
            }
        }

        // Repeating on a third of the pages is a header or footer, not a coincidence.
        let threshold = max(3, pages.count / 3)
        let repeated = Set(edgeCounts.filter { $0.value >= threshold }.keys)
        guard !repeated.isEmpty else { return withoutPageNumbers }

        var keptHeading: Set<String> = []
        var cleaned: [[PDFStyledBlock]] = []
        cleaned.reserveCapacity(withoutPageNumbers.count)
        for page in withoutPageNumbers {
            guard let edges = edgeIndices(of: page) else {
                cleaned.append(page)
                continue
            }
            var kept: [PDFStyledBlock] = []
            kept.reserveCapacity(page.count)
            for (index, block) in page.enumerated() {
                if index == edges.first || index == edges.last {
                    let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, !isSeparator(trimmed), repeated.contains(trimmed) {
                        if isExplicitChapterHeading(trimmed), keptHeading.insert(trimmed).inserted {
                            kept.append(block)
                        }
                        continue
                    }
                }
                kept.append(block)
            }
            cleaned.append(kept)
        }
        return cleaned
    }

    // MARK: - Paragraph joining & separator normalisation

    /// Normalises scene-break blocks to `* * *` and joins a paragraph that a page break cut in two: only the first block
    /// of a page joins the block before it. Within a page MuPDF's separate blocks are real paragraph gaps; joining there
    /// merged the author's own unpunctuated paragraphs ("…against Elsa's" / "She smiled…", 8 in the owner's PDF) and
    /// fixed one split in 3,476 blocks. Preserves page count for outline slicing.
    static func joinBrokenParagraphs(_ pages: [[String]]) -> [[String]] {
        joinBrokenParagraphs(pages.map { $0.map { PDFStyledBlock(text: $0) } })
            .map { $0.map(\.text) }
    }

    static func joinBrokenParagraphs(_ pages: [[PDFStyledBlock]]) -> [[PDFStyledBlock]] {
        var result: [[PDFStyledBlock]] = Array(repeating: [], count: pages.count)
        var lastPageIndex: Int?

        for pageIndex in pages.indices {
            var placedOnThisPage = false
            for rawBlock in pages[pageIndex] {
                let block = rawBlock.trimmed()
                guard !block.text.isEmpty else { continue }

                defer { placedOnThisPage = true }
                if isSeparator(block.text) {
                    result[pageIndex].append(PDFStyledBlock(text: normalizedSeparator))
                    lastPageIndex = pageIndex
                    continue
                }

                if !placedOnThisPage,
                   let previousPage = lastPageIndex, previousPage < pageIndex,
                   let previousBlock = result[previousPage].last,
                   shouldJoin(previousBlock.text, with: block.text) {
                    // Join with one space; hyphens stay untouched (stutters and
                    // cut-off speech like `y- your` and `Wha- really`).
                    result[previousPage][result[previousPage].count - 1] =
                        previousBlock.joinedWithSpace(to: block)
                    continue
                }

                result[pageIndex].append(block)
                lastPageIndex = pageIndex
            }
        }
        return result
    }

    // MARK: - Classification

    /// Whether `text` is a scene-break divider (`* * *`, `~~~`, `o0o`, `❦`, `-x-x-x-`, …).
    static func isSeparator(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxSeparatorLength else { return false }
        return isSymbolSeparator(trimmed) || isOrnamentSeparator(trimmed)
    }

    /// Whether `second` continues the sentence/paragraph started in `first`.
    static func shouldJoin(_ first: String, with second: String) -> Bool {
        let lhs = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = second.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }

        if isSeparator(lhs) || isSeparator(rhs) { return false }
        if endsWithTerminalPunctuation(lhs) { return false }

        guard let nextFirst = rhs.first, let lastChar = lhs.last else { return false }
        // Case is the continuation signal. Han, kana, Arabic and Hebrew letters are
        // neither lowercase nor uppercase, so a page of those does not join the next.
        let nextStartsLowercase = nextFirst.isLowercase
        let nextStartsUppercase = nextFirst.isUppercase

        // "chapter 3" is a heading even though it starts lowercase. A heading cut
        // after its colon ("Chapter 1:" / "the return") is still one heading.
        if isExplicitChapterHeading(rhs) { return false }
        if isExplicitChapterHeading(lhs) {
            let titleContinues = nextStartsLowercase
                && (lastChar == ":" || hyphensAndDashes.contains(lastChar))
            if !titleContinues { return false }
        }

        // Comma or semicolon (including `,"` / `,”` before a dialogue tag) always
        // continues onto the next block, even before a capitalised name or quote.
        if endsWithClauseBreak(lhs) { return true }

        if nextStartsLowercase {
            return lastChar == ":"
                || openingQuotes.contains(lastChar)
                || hyphensAndDashes.contains(lastChar)
                || lastChar.isLetter
                || closingDelimiters.contains(lastChar)
        }

        // A long prose block ending in a lowercase letter continues into a capitalised
        // word (usually a proper noun like "…she said to / Harry").
        if nextStartsUppercase, lhs.count >= longParagraphThreshold, lastChar.isLowercase {
            return true
        }

        return false
    }

    // MARK: - Helpers

    private static func edgeIndices(of page: [PDFStyledBlock]) -> (first: Int, last: Int)? {
        let isNonEmpty: (PDFStyledBlock) -> Bool = {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let first = page.firstIndex(where: isNonEmpty),
              let last = page.lastIndex(where: isNonEmpty)
        else { return nil }
        return (first, last)
    }

    private static func isBarePageNumber(_ trimmed: String) -> Bool {
        trimmed.range(of: #"^[\-–—\s]*\d{1,4}[.\-–—\s]*$"#, options: .regularExpression) != nil
    }

    /// A repeated edge line is a header or footer. A sentence that happens to end
    /// the page is a refrain. Chapter headings are counted so the first copy can
    /// be kept and the running copies dropped.
    private static func isRepeatedEdgeCandidate(_ trimmed: String) -> Bool {
        if trimmed.isEmpty || isSeparator(trimmed) { return false }
        if endsWithTerminalPunctuation(trimmed), !isExplicitChapterHeading(trimmed) {
            return false
        }
        return true
    }

    private static func isSymbolSeparator(_ trimmed: String) -> Bool {
        var coreCount = 0
        var hyphenOnly = true
        for character in trimmed {
            if character.isWhitespace { continue }
            // A face (`:-)`, `^_^`) or any other prose made of symbols is not a break.
            guard separatorSymbols.contains(character) else { return false }
            if character != "-" { hyphenOnly = false }
            coreCount += 1
        }
        // A lone "-" is a bullet, a pause, or a stutter, not a scene break.
        if hyphenOnly, coreCount < 2 { return false }
        return coreCount > 0
    }

    private static func isOrnamentSeparator(_ trimmed: String) -> Bool {
        var ornamentChars: [Character] = []
        var letters = Set<Character>()
        var symbolCount = 0

        for character in trimmed {
            if character.isWhitespace { continue }
            if ornamentCharacters.contains(character) {
                ornamentChars.append(character)
                if ornamentLetters.contains(character) {
                    for lowered in character.lowercased() {
                        letters.insert(lowered)
                    }
                }
            } else if separatorSymbols.contains(character) {
                symbolCount += 1
            } else {
                return false
            }
        }

        // One letter only: `xXx` / `o0o` / `oOo` are breaks. `Xox`, `oxo` and `ox` are names.
        guard letters.count == 1 else { return false }
        let hasRepeatingOrnament = Set(ornamentChars.map { $0.lowercased() }).count < ornamentChars.count

        if symbolCount == 0 {
            return trimmed.count <= maxPureOrnamentLength
                && ornamentChars.count >= 3
                && hasRepeatingOrnament
        }

        // Combined ornament like `-x-x-x-` or `~o0o~`: require repeating ornament
        // characters (≥3, or ≥2 with ≥2 symbols) so stutters like `O-` stay prose.
        guard ornamentChars.count <= maxPureOrnamentLength, hasRepeatingOrnament else {
            return false
        }
        return ornamentChars.count >= 3 || (ornamentChars.count >= 2 && symbolCount >= 2)
    }

    private static func endsWithTerminalPunctuation(_ text: String) -> Bool {
        var slice = text[...]
        var strippedClosingQuote = false
        while let last = slice.last, closingDelimiters.contains(last) {
            if closingQuotes.contains(last) {
                strippedClosingQuote = true
            }
            slice = slice.dropLast()
        }
        guard let coreLast = slice.last else { return false }
        if terminalPunctuation.contains(coreLast) { return true }
        // Interrupted dialogue ending with a dash inside closing quotes (`—”`, `—"`).
        if strippedClosingQuote, coreLast == "—" || coreLast == "–" { return true }
        return false
    }

    private static func endsWithClauseBreak(_ text: String) -> Bool {
        var slice = text[...]
        while let last = slice.last, closingQuotes.contains(last) {
            slice = slice.dropLast()
        }
        guard let coreLast = slice.last else { return false }
        return coreLast == "," || coreLast == ";"
    }

    private static func isExplicitChapterHeading(_ text: String) -> Bool {
        if isStandaloneHeading(text) { return true }
        if PlainTextWorkConverter.isChapterHeading(text) { return true }
        let stripped = text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, stripped.count <= 100 else { return false }
        if isStandaloneHeading(stripped) || PlainTextWorkConverter.isChapterHeading(stripped) { return true }
        return stripped.range(
            of: #"^part\s+(one|two|three|four|five|six|seven|eight|nine|ten)\s*([:.\-–—]\s*.{0,80})?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isStandaloneHeading(_ text: String) -> Bool {
        guard text.count <= 100 else { return false }
        let lowered = text.lowercased()
        if standaloneHeadings.contains(lowered) { return true }
        guard let colon = lowered.firstIndex(of: ":") else { return false }
        let word = lowered[..<colon].trimmingCharacters(in: .whitespaces)
        return standaloneHeadings.contains(word)
    }
}
