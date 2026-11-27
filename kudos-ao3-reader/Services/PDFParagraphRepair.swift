import Foundation

/// Cleans per-page PDF paragraph blocks before chapter assembly.
///
/// MuPDF extracts one array of paragraph blocks per page, so a paragraph that wraps
/// across a page break — or changes spacing or italics mid-paragraph — arrives split
/// into two blocks. Scene breaks that happen to land at a page edge were also caught
/// by the running-header filter and deleted across the whole document.
///
/// Every function here is pure (`[[String]]` → `[[String]]`) and preserves page
/// count so `PDFWorkConverter.outlineChapters` can still slice by PDF page index.
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

    /// Punctuation that belongs to prose rather than decorative dividers, so cut-off
    /// dialogue like `“—”` is never mistaken for a scene break.
    private static let proseOnlyPunctuation: Set<Character> = Set("\"'“”‘’«»‹›,;?!")

    private static let closingDelimiters: Set<Character> = Set("\"”'’)]»›")
    private static let closingQuotes: Set<Character> = Set("\"”'’»›")
    private static let terminalPunctuation: Set<Character> = Set(".!?…")
    private static let openingQuotes: Set<Character> = Set("\"“'‘«‹")
    private static let hyphensAndDashes: Set<Character> = Set("-–—")

    /// Runs the full cleanup pipeline: removes running headers, footers, and bare
    /// page numbers while sparing separators, then normalises separators and rejoins
    /// paragraphs split within a page or across page breaks.
    static func repair(_ pages: [[String]]) -> [[String]] {
        joinBrokenParagraphs(withoutRunningHeadersAndFooters(pages))
    }

    // MARK: - Running headers & footers

    /// Drops bare page numbers and lines that repeat at the top or bottom of pages.
    ///
    /// A repeated header or footer is removed only where it sits as the first or last
    /// non-empty block of a page, never mid-page, and scene-break separators are
    /// never removed regardless of how often they land on a page edge.
    static func withoutRunningHeadersAndFooters(_ pages: [[String]]) -> [[String]] {
        guard pages.count >= 4 else { return pages }

        // Strip bare page numbers first so a running footer sitting directly above a
        // page number still sits at the page edge when frequencies are counted.
        let withoutPageNumbers: [[String]] = pages.map { page in
            page.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return true }
                return !isBarePageNumber(trimmed)
            }
        }

        var edgeCounts: [String: Int] = [:]
        for page in withoutPageNumbers {
            guard let edges = edgeIndices(of: page) else { continue }
            let firstText = page[edges.first].trimmingCharacters(in: .whitespacesAndNewlines)
            let lastText = page[edges.last].trimmingCharacters(in: .whitespacesAndNewlines)
            var candidates: Set<String> = []
            if !isSeparator(firstText) { candidates.insert(firstText) }
            if !isSeparator(lastText) { candidates.insert(lastText) }
            for candidate in candidates {
                edgeCounts[candidate, default: 0] += 1
            }
        }

        // Repeating on a third of the pages is a header or footer, not a coincidence.
        let threshold = max(3, pages.count / 3)
        let repeated = Set(edgeCounts.filter { $0.value >= threshold }.keys)
        guard !repeated.isEmpty else { return withoutPageNumbers }

        return withoutPageNumbers.map { page in
            guard let edges = edgeIndices(of: page) else { return page }
            return page.enumerated().compactMap { index, line -> String? in
                guard index == edges.first || index == edges.last else { return line }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !isSeparator(trimmed), repeated.contains(trimmed) {
                    return nil
                }
                return line
            }
        }
    }

    // MARK: - Paragraph joining & separator normalisation

    /// Normalises scene-break blocks to `* * *` and joins a paragraph that a page break cut in two: only the first block
    /// of a page joins the block before it. Within a page MuPDF's separate blocks are real paragraph gaps; joining there
    /// merged the author's own unpunctuated paragraphs ("…against Elsa's" / "She smiled…", 8 in the owner's PDF) and
    /// fixed one split in 3,476 blocks. Preserves page count for outline slicing.
    static func joinBrokenParagraphs(_ pages: [[String]]) -> [[String]] {
        var result: [[String]] = Array(repeating: [], count: pages.count)
        var lastPageIndex: Int?

        for pageIndex in pages.indices {
            var placedOnThisPage = false
            for rawBlock in pages[pageIndex] {
                let block = rawBlock.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !block.isEmpty else { continue }

                defer { placedOnThisPage = true }
                if isSeparator(block) {
                    result[pageIndex].append(normalizedSeparator)
                    lastPageIndex = pageIndex
                    continue
                }

                if !placedOnThisPage,
                   let previousPage = lastPageIndex, previousPage < pageIndex,
                   let previousBlock = result[previousPage].last,
                   shouldJoin(previousBlock, with: block) {
                    // Join with one space; hyphens stay untouched (stutters and
                    // cut-off speech like `y- your` and `Wha- really`).
                    result[previousPage][result[previousPage].count - 1] = previousBlock + " " + block
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
        let nextStartsLowercase = nextFirst.isLowercase
        let nextStartsUppercase = nextFirst.isUppercase

        if !nextStartsLowercase, isExplicitChapterHeading(lhs) || isExplicitChapterHeading(rhs) {
            return false
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

    private static func edgeIndices(of page: [String]) -> (first: Int, last: Int)? {
        guard let first = page.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              let last = page.lastIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }
        return (first, last)
    }

    private static func isBarePageNumber(_ trimmed: String) -> Bool {
        trimmed.range(of: #"^[\-–—\s]*\d{1,4}[.\-–—\s]*$"#, options: .regularExpression) != nil
    }

    private static func isSymbolSeparator(_ trimmed: String) -> Bool {
        var hasCoreSymbol = false
        for character in trimmed {
            if character.isWhitespace { continue }
            if separatorSymbols.contains(character) {
                hasCoreSymbol = true
                continue
            }
            if proseOnlyPunctuation.contains(character) { return false }
            guard character.isSymbol || character.isPunctuation else { return false }
        }
        return hasCoreSymbol
    }

    private static func isOrnamentSeparator(_ trimmed: String) -> Bool {
        var ornamentChars: [Character] = []
        var hasOrnamentLetter = false
        var symbolCount = 0

        for character in trimmed {
            if character.isWhitespace { continue }
            if ornamentCharacters.contains(character) {
                ornamentChars.append(character)
                if ornamentLetters.contains(character) {
                    hasOrnamentLetter = true
                }
            } else if separatorSymbols.contains(character) {
                symbolCount += 1
            } else {
                return false
            }
        }

        guard hasOrnamentLetter else { return false }
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
        if PlainTextWorkConverter.isChapterHeading(text) { return true }
        let stripped = text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, stripped.count <= 100 else { return false }
        if PlainTextWorkConverter.isChapterHeading(stripped) { return true }
        return stripped.range(
            of: #"^part\s+(one|two|three|four|five|six|seven|eight|nine|ten)\s*([:.\-–—]\s*.{0,80})?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
