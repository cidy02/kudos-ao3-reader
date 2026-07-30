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
    private static let chapterHeadingPatterns = [
        #"^chapter\s+(\d+|[ivxlcdm]+|\#(spelledNumbers))\s*([:.\-–—]\s*.{0,80})?$"#,
        #"^ch\.?\s*\d+\s*([:.\-–—]\s*.{0,80})?$"#,
        #"^part\s+(\d+|[ivxlcdm]+)\s*([:.\-–—]\s*.{0,80})?$"#,
        #"^\d{1,3}\s*[.)]\s*.{0,80}$"#,
        #"^\*\s*\*\s*\*$"#,
        #"^#{1,3}\s+.{1,80}$"#              // Markdown headings
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
        guard !trimmed.isEmpty, trimmed.count <= 100 else { return false }
        return chapterHeadingPatterns.contains { pattern in
            trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
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
