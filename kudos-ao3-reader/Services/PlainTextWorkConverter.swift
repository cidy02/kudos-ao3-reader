import Foundation

/// Turns a `.txt` / `.md` file into EPUB chapters.
///
/// Plain text is how a lot of rescued fanfic survives: someone selected all,
/// pasted into TextEdit, and posted the result. There is no structure to read,
/// so the only real decisions are where chapters break and where paragraphs do.
nonisolated enum PlainTextWorkConverter {
    /// Lines that look like a chapter break. Matched against the whole trimmed
    /// line, so prose that merely mentions "chapter 3" is never a split point.
    ///
    /// Anchored, case-insensitive, and deliberately narrow — a false split makes
    /// a mess of the table of contents, while a missed one merely leaves a longer
    /// chapter, so the bias is towards under-splitting.
    /// The trailing title is optional but, when present, must be introduced by a
    /// separator. Without that rule "chapter 5 implied." — a line of prose that
    /// merely begins with the word — reads as a heading and splits the work in the
    /// middle of a sentence.
    private static let titledHeadingPatterns = [
        #"^chapter\s+(?:\d+|[ivxlcdm]+|\#(spelledNumbers))(?:\s*[:.\-–—]\s*(.{0,80}))?$"#,
        #"^ch\.?\s*\d+(?:\s*[:.\-–—]\s*(.{0,80}))?$"#,
        #"^part\s+(?:\d+|[ivxlcdm]+|\#(spelledNumbers))(?:\s*[:.\-–—]\s*(.{0,80}))?$"#,
        #"^\d{1,3}\s*[.)]\s*(.{0,80})$"#
    ]

    private static let titledHeadingRegexes: [NSRegularExpression] = titledHeadingPatterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }

    private static let simpleHeadingPatterns = [
        #"^\*\s*\*\s*\*$"#,
        #"^#{1,3}\s+.{1,80}$"#              // Markdown headings
    ]

    /// Abbreviations whose trailing period is not a sentence stop inside a chapter subtitle
    /// (`Chapter 3: Mr. Smith Goes to Town`, `Chapter 4: Dr. Watson`, `Chapter 5: Oct. 31`).
    private static let titleAbbreviations: Set<String> = [
        "mr", "mrs", "ms", "miss", "mx", "dr", "prof", "st", "sr", "jr",
        "rev", "fr", "br", "hon", "pres", "gov", "sen", "rep",
        "gen", "col", "maj", "capt", "cpt", "lt", "sgt", "cpl", "pvt", "adm", "cmdr",
        "no", "nos", "vol", "vols", "ch", "pt", "sec", "fig", "ed", "vs", "v",
        "etc", "al", "dept", "mt", "ft", "ave", "blvd", "rd", "ln", "ct", "pl", "sq",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun"
    ]

    /// Word-numbered chapters ("Chapter One") are common enough in fanfic that
    /// skipping them would leave whole works as a single chapter.
    private static let spelledNumbers = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
        "eighteen", "nineteen", "twenty"
    ].joined(separator: "|")

    static func convert(text: String, fallbackTitle: String) throws -> HTMLWorkConverter.Result {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            // Some exports use a form feed as the page/chapter break.
            .replacingOccurrences(of: "\u{0C}", with: "\n")

        let chapters = chapters(in: normalized, fallbackTitle: fallbackTitle)
        guard !chapters.isEmpty else { throw EPUBBuilder.BuildError.noChapters }

        return HTMLWorkConverter.Result(
            metadata: .init(title: fallbackTitle),
            chapters: chapters
        )
    }

    /// Splits already-repaired styled paragraph blocks into chapters using the same
    /// heading rules as `convert(text:fallbackTitle:)`. Headings become plain chapter
    /// titles (no inline styling); body blocks keep their italic and bold runs.
    ///
    /// When `leadingTitle` is given and front-matter blocks precede the first detected
    /// heading, that leading chapter takes `leadingTitle` (e.g. `"Preface"`) instead of
    /// `fallbackTitle`, matching the PDF outline path.
    static func convert(
        blocks: [PDFStyledBlock],
        fallbackTitle: String,
        leadingTitle: String? = nil,
        sceneBreakPlaceholder: String? = nil
    ) throws -> HTMLWorkConverter.Result {
        var chapters: [EPUBBuilder.Chapter] = []
        var currentTitle = ""
        var currentBlocks: [PDFStyledBlock] = []
        var firstChapterHadNoHeading = false

        func flush() {
            let body = HTMLWorkSanitizer.styledParagraphs(from: currentBlocks)
            guard !body.isEmpty else {
                currentBlocks = []
                return
            }
            let index = chapters.count + 1
            if chapters.isEmpty, currentTitle.isEmpty {
                firstChapterHadNoHeading = true
            }
            let title = currentTitle.isEmpty
                ? (chapters.isEmpty ? fallbackTitle : "Chapter \(index)")
                : currentTitle
            chapters.append(EPUBBuilder.Chapter(title: title, bodyXHTML: body))
            currentBlocks = []
        }

        func isOnlySeparators(_ items: [PDFStyledBlock]) -> Bool {
            items.allSatisfy { item in
                item.text == sceneBreakPlaceholder || PDFParagraphRepair.isSeparator(item.text)
            }
        }

        for block in blocks {
            let trimmed = block.trimmed()
            guard !trimmed.text.isEmpty else { continue }
            if isChapterHeading(trimmed.text) {
                let nextTitle = headingTitle(trimmed.text)
                // A heading echoed right after a decorative divider (`Chapter 1` / `***` / `Chapter 1`)
                // belongs to the chapter just opened, not a second stub chapter of only `* * *`.
                if !currentTitle.isEmpty,
                   !currentBlocks.isEmpty,
                   normalizedHeadingKey(nextTitle) == normalizedHeadingKey(currentTitle),
                   isOnlySeparators(currentBlocks) {
                    currentBlocks.append(trimmed)
                    continue
                }
                flush()
                currentTitle = nextTitle
            } else {
                currentBlocks.append(trimmed)
            }
        }
        flush()

        if firstChapterHadNoHeading,
           chapters.count > 1,
           let leadingTitle,
           !leadingTitle.isEmpty {
            chapters[0] = EPUBBuilder.Chapter(title: leadingTitle, bodyXHTML: chapters[0].bodyXHTML)
        }

        guard !chapters.isEmpty else { throw EPUBBuilder.BuildError.noChapters }
        return HTMLWorkConverter.Result(
            metadata: EPUBBuilder.Metadata(title: fallbackTitle),
            chapters: chapters
        )
    }

    // MARK: - Splitting

    private static func chapters(in text: String, fallbackTitle: String) -> [EPUBBuilder.Chapter] {
        var chapters: [EPUBBuilder.Chapter] = []
        var currentTitle = ""
        var currentLines: [String] = []

        func flush() {
            let body = HTMLWorkSanitizer.paragraphs(from: paragraphs(of: currentLines))
            guard !body.isEmpty else {
                currentLines = []
                return
            }
            let index = chapters.count + 1
            let title = currentTitle.isEmpty
                ? (chapters.isEmpty ? fallbackTitle : "Chapter \(index)")
                : currentTitle
            chapters.append(.init(title: title, bodyXHTML: body))
            currentLines = []
        }

        for line in text.components(separatedBy: "\n") {
            if isChapterHeading(line) {
                flush()
                currentTitle = headingTitle(line)
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return chapters
    }

    /// Internal so `PDFWorkConverter` can reuse it: a PDF gives no blank lines, so
    /// recognizing a heading is the only way to stop one being glued to the
    /// paragraph that follows it. One definition of "looks like a chapter heading",
    /// shared by both converters.
    static func isChapterHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 100, !trimmed.contains("\n") else { return false }
        if simpleHeadingPatterns.contains(where: {
            trimmed.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return true
        }
        let nsText = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        for regex in titledHeadingRegexes {
            guard let match = regex.firstMatch(in: trimmed, options: [], range: fullRange) else {
                continue
            }
            let subtitleRange = match.range(at: 1)
            guard subtitleRange.location != NSNotFound, subtitleRange.length > 0 else {
                return true
            }
            let subtitle = nsText.substring(with: subtitleRange)
            return !hasMultipleSentences(subtitle)
        }
        return false
    }

    /// True when `text` contains an internal sentence boundary (`.`, `!`, or `?` followed
    /// by whitespace and more words), so prose like `Part one: get in. Part two: get out.`
    /// is rejected as a heading while titles with abbreviations (`Mr. Smith`) stay valid.
    static func hasMultipleSentences(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let chars = Array(trimmed)
        let count = chars.count
        let closingChars: Set<Character> = Set("\"”'’)]»›")

        var idx = 0
        while idx < count {
            let ch = chars[idx]
            guard ch == "." || ch == "!" || ch == "?" else {
                idx += 1
                continue
            }
            // Consecutive dots (`...`) are an ellipsis, not a finished sentence stop.
            if ch == ".", (idx > 0 && chars[idx - 1] == ".") || (idx + 1 < count && chars[idx + 1] == ".") {
                idx += 1
                continue
            }
            var after = idx + 1
            while after < count && closingChars.contains(chars[after]) {
                after += 1
            }
            guard after < count, chars[after].isWhitespace else {
                idx += 1
                continue
            }
            var nextWord = after
            while nextWord < count && chars[nextWord].isWhitespace {
                nextWord += 1
            }
            guard chars[nextWord...].contains(where: { $0.isLetter || $0.isNumber }) else {
                return false
            }
            if ch == "!" || ch == "?" || !isAbbreviationBeforePeriod(in: chars, periodIndex: idx) {
                return true
            }
            idx = after
        }
        return false
    }

    private static func isAbbreviationBeforePeriod(in chars: [Character], periodIndex: Int) -> Bool {
        var start = periodIndex
        while start > 0 && !chars[start - 1].isWhitespace {
            start -= 1
        }
        let openingPunct: Set<Character> = Set("\"“'‘([«‹")
        let token = String(chars[start..<periodIndex].drop { openingPunct.contains($0) })
        guard !token.isEmpty else { return false }
        if token.contains(".") { return true }
        if token.count == 1, token.first?.isLetter == true { return true }
        return titleAbbreviations.contains(token.lowercased())
    }

    private static func normalizedHeadingKey(_ title: String) -> String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// A `***` scene break carries no title, and Markdown `#` marks are noise in
    /// a table of contents.
    private static func headingTitle(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.allSatisfy({ $0 == "*" || $0 == " " }) { return "" }
        return trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Blank-line-separated blocks become paragraphs. Single newlines inside a
    /// block are joined with a space, because hard-wrapped exports would otherwise
    /// produce one paragraph per display line and read terribly when reflowed.
    ///
    /// Internal rather than private because `PDFWorkConverter` needs exactly this
    /// behavior: extracted PDF text is hard-wrapped per display line too.
    static func paragraphs(of lines: [String]) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []

        func flush() {
            let joined = current
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { paragraphs.append(joined) }
            current = []
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flush()
            } else {
                current.append(line)
            }
        }
        flush()
        return paragraphs
    }
}
