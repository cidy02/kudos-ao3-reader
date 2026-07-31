import Foundation

/// Parses the metadata page calibre and FanFicFare put at the front of a fic they
/// export.
///
/// It looks like this, and it is the single most useful page in the file:
///
/// ```
/// In the Service of the Queen
/// Story: In the Service of the Queen
/// Storylink: https://www.fanfiction.net/s/10251701/1/
/// Category: Frozen
/// Genre: Romance/Fantasy
/// Author: Malthazar Lord of Shadows
/// Rating: M
/// Status: Complete
/// Source: FanFiction.net
/// Summary: Anna lives a rugged life, such is the way of a traveling swords-woman…
/// ```
///
/// Recovering `Storylink` is what lets a converted PDF know it came from
/// fanfiction.net — which drives the Library's origin badge, and stops the app
/// implying it can refresh tags or give kudos on a work AO3 has never heard of. The
/// summary, fandom, genre and rating come free in the same block.
///
/// Kudos would otherwise throw all of this away: a fic exported by calibre carries no
/// PDF keywords, so `documentAttributes` yields only the title and author.
///
/// ## Adding a label
///
/// Extend `Field.all`. Labels are matched case-insensitively at the start of a line,
/// longest first, so `Storylink:` cannot be swallowed by `Story:`. Other exporters use
/// other words for the same things — add them as extra spellings on the same field
/// rather than as new fields.
nonisolated struct CalibreMetadataPage {
    var title = ""
    var author = ""
    var summary = ""
    var storyURL = ""
    var authorURL = ""
    var rating = ""
    /// Fandom, from `Category`.
    var fandoms: [String] = []
    /// From `Genre`, which exporters write slash-separated ("Romance/Fantasy").
    var genres: [String] = []
    var isComplete: Bool?
    var wordCount: Int?

    private enum Field: CaseIterable {
        case story, storyLink, category, genre, author, authorLink, rating, status, words, summary, source

        /// Every spelling that maps to this field. Longest label wins at match time.
        var labels: [String] {
            switch self {
            case .story: ["story", "title"]
            case .storyLink: ["storylink", "story link", "story url"]
            case .category: ["category", "categories", "fandom"]
            case .genre: ["genre", "genres"]
            case .author: ["author", "authors"]
            case .authorLink: ["authorlink", "author link", "author url"]
            case .rating: ["rating", "rated"]
            case .status: ["status", "completed"]
            case .words: ["words", "wordcount", "word count"]
            case .summary: ["summary", "description"]
            case .source: ["source", "site"]
            }
        }

        static var all: [(label: String, field: Field)] {
            allCases
                .flatMap { field in field.labels.map { (label: $0, field: field) } }
                // Longest first: otherwise "story" claims a "storylink:" line.
                .sorted { $0.label.count > $1.label.count }
        }
    }

    /// How many distinct labels a page must carry to count as a metadata page. Three
    /// keeps a chapter that merely opens with "Summary:" from being mistaken for one.
    private static let minimumFieldsToRecognise = 3

    /// Parses `lines` if they look like an exporter's metadata page, else nil.
    static func parse(lines: [String]) -> Self? {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        var page = Self()
        var matched: Set<String> = []
        // The summary runs on across wrapped lines until the next labelled line, so the
        // parser remembers which field it is still filling.
        var openField: Field?

        for line in cleaned {
            if let (field, value) = labelled(line) {
                matched.insert(String(describing: field))
                page.apply(field, value: value)
                openField = field == .summary ? .summary : nil
            } else if openField == .summary {
                page.summary += page.summary.isEmpty ? line : " " + line
            } else if page.title.isEmpty {
                // The bare first line is the work's title, before any labels start.
                page.title = line
            }
        }

        guard matched.count >= minimumFieldsToRecognise else { return nil }
        return page
    }

    private static func labelled(_ line: String) -> (Field, String)? {
        let lowered = line.lowercased()
        for candidate in Field.all where lowered.hasPrefix(candidate.label + ":") {
            let value = String(line.dropFirst(candidate.label.count + 1))
                .trimmingCharacters(in: .whitespaces)
            return (candidate.field, value)
        }
        return nil
    }

    private mutating func apply(_ field: Field, value: String) {
        guard !value.isEmpty else { return }
        switch field {
        case .story:
            if title.isEmpty || title == value { title = value }
        case .storyLink:
            storyURL = value
        case .authorLink:
            authorURL = value
        case .category:
            fandoms = value.components(separatedBy: CharacterSet(charactersIn: ",/"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        case .genre:
            genres = value.components(separatedBy: CharacterSet(charactersIn: ",/"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        case .author:
            author = value
        case .rating:
            rating = value
        case .status:
            // "Complete" / "Completed" / "In-Progress" / "WIP".
            let lowered = value.lowercased()
            isComplete = lowered.contains("complete") && !lowered.contains("incomplete")
        case .words:
            wordCount = Int(value.filter(\.isNumber))
        case .summary:
            summary = value
        case .source:
            // Only useful when there is no story link to be more specific with.
            if storyURL.isEmpty { storyURL = inferredURL(forSiteNamed: value) }
        }
    }

    /// Last resort when a page names its site but gives no link. Deliberately returns
    /// a bare host, never a fabricated story path — a wrong URL is worse than none,
    /// because the importer would try to resolve it.
    private func inferredURL(forSiteNamed site: String) -> String {
        switch site.lowercased() {
        case let name where name.contains("fanfiction"): "https://www.fanfiction.net"
        case let name where name.contains("archive of our own"), let name where name.contains("ao3"):
            "https://archiveofourown.org"
        case let name where name.contains("wattpad"): "https://www.wattpad.com"
        default: ""
        }
    }

    /// The page rewritten as something worth reading.
    ///
    /// The source page is a list of `Label: value` lines, which reads badly as prose
    /// and — now that every value is real metadata on the work — would just repeat
    /// what the Library already shows. This keeps the parts a reader wants (title,
    /// byline, summary, and the link back to the original) and drops the labels.
    ///
    /// Nothing is lost by rewriting it: the original PDF is archived beside the EPUB.
    func prefaceBlocks() -> [String] {
        var blocks: [String] = []
        if !title.isEmpty { blocks.append(title) }

        var byline: [String] = []
        if !author.isEmpty { byline.append("by \(author)") }
        if !fandoms.isEmpty { byline.append(fandoms.joined(separator: ", ")) }
        if !genres.isEmpty { byline.append(genres.joined(separator: ", ")) }
        if !rating.isEmpty { byline.append("Rated \(rating)") }
        if let isComplete { byline.append(isComplete ? "Complete" : "In progress") }
        if let wordCount { byline.append("\(wordCount.formatted()) words") }
        if !byline.isEmpty { blocks.append(byline.joined(separator: " · ")) }

        if !summary.isEmpty { blocks.append(summary) }
        // Kept verbatim so the reader can get back to the original posting, which for a
        // work that has since been deleted is often the only citation that exists.
        if !storyURL.isEmpty { blocks.append(storyURL) }
        return blocks
    }

    /// Everything worth carrying into the EPUB, folded onto whatever the PDF's own
    /// attributes already provided. Existing values win, since `documentAttributes`
    /// is structured data and this page is scraped text.
    func merged(into metadata: EPUBBuilder.Metadata) -> EPUBBuilder.Metadata {
        var result = metadata
        if result.author.isEmpty { result.author = author }
        if result.summary.isEmpty { result.summary = summary }
        if result.sourceURL.isEmpty { result.sourceURL = storyURL }
        if result.title.isEmpty { result.title = title }
        var subjects = result.subjects
        for tag in fandoms + genres + (rating.isEmpty ? [] : [rating]) where !subjects.contains(tag) {
            subjects.append(tag)
        }
        result.subjects = subjects
        return result
    }
}
