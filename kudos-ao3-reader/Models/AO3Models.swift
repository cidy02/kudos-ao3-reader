import Foundation

// The value types describing AO3 search results and the inputs to a search.
// These are pure data (no networking) — `AO3Client` (in Services) fetches and
// populates them. The faceted-filter ids/values are taken from AO3's own search
// form; see `AO3Client` for the porting/verification notes.

/// A work as summarized on an AO3 search/listing page ("blurb").
struct AO3WorkSummary: Identifiable, Hashable, Sendable {
    let id: Int
    var title: String
    var authors: [String]
    var fandoms: [String]
    var rating: String
    var warnings: [String]
    var categories: [String]
    var relationships: [String] = []
    var characters: [String] = []
    /// nil when AO3 doesn't say (rare); otherwise whether the work is finished.
    var isComplete: Bool?
    var dateUpdated: String
    /// Freeform / "Additional Tags" (the blurb's `li.freeforms` tags).
    var tags: [String]
    var summary: String
    var language: String
    var words: Int?
    /// Raw "posted/total" string from AO3, e.g. "3/?" or "12/12".
    var chapters: String
    var comments: Int?
    var kudos: Int?
    var hits: Int?
    /// Series info when the work is part of one (first series only, for v1).
    var seriesTitle: String?
    var seriesURL: String?
    var seriesPosition: Int?

    var workURL: URL { URL(string: "https://archiveofourown.org/works/\(id)")! }
    var authorText: String { authors.isEmpty ? "Anonymous" : authors.joined(separator: ", ") }

    /// A sparse summary for a *work subscription*. AO3's subscriptions page lists only
    /// each work's title, id, and author — no stats, fandoms, or rating — so those
    /// fields stay empty here; opening the work loads its full detail page.
    static func subscription(id: Int, title: String, authors: [String]) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id, title: title, authors: authors, fandoms: [], rating: "",
            warnings: [], categories: [], isComplete: nil, dateUpdated: "",
            tags: [], summary: "", language: "", words: nil, chapters: "",
            comments: nil, kudos: nil, hits: nil,
            seriesTitle: nil, seriesURL: nil, seriesPosition: nil
        )
    }
}

/// One page of search results, with the current page and total page count
/// (parsed from AO3's pagination control) so the UI can show page navigation.
struct AO3SearchPage: Sendable {
    var works: [AO3WorkSummary]
    var currentPage: Int
    var totalPages: Int
}

/// A bounded look at a series page. Used before automatic series preservation so
/// Kudos can avoid crawling an unknown large series merely to decide whether to ask.
struct AO3SeriesPreview: Equatable, Sendable {
    var works: [AO3WorkSummary]
    var currentPage: Int
    var totalPages: Int

    var isComplete: Bool {
        totalPages <= currentPage
    }
}

/// The inputs to an AO3 works search. Maps directly to AO3's `work_search[...]`
/// query parameters; the ids/values are taken from AO3's own search form. Covers
/// the same filters as AO3's faceted sidebar, minus the live per-fandom counts
/// (those come from a different browse endpoint — here you type tag names).
struct AO3SearchFilters: Equatable, Sendable, Codable {
    var query: String = ""
    // Tag fields (comma-separated names).
    var fandom: String = ""
    var characters: String = ""
    var relationships: String = ""
    var additionalTags: String = ""
    var excludedFandoms: String = ""
    var excludedCharacters: String = ""
    var excludedRelationships: String = ""
    var excludedAdditionalTags: String = ""
    // Faceted filters.
    var rating: Rating = .any
    var ratingMatch: RatingMatch = .exact
    var includeNotRated: Bool = true
    var warnings: Set<Warning> = []
    var excludedWarnings: Set<Warning> = []
    var categories: Set<Category> = []
    var excludedCategories: Set<Category> = []
    var crossover: Crossover = .any
    var completion: Completion = .any
    var wordsFrom: String = ""
    var wordsTo: String = ""
    var updated: Updated = .any
    var language: Language = .any
    var sort: Sort = .relevance

    /// True when any filter beyond the plain query is set (drives the filter
    /// button's "active" icon and the Reset action).
    var hasActiveFilters: Bool {
        !fandom.isBlank || !characters.isBlank || !relationships.isBlank
            || !additionalTags.isBlank || !excludedFandoms.isBlank
            || !excludedCharacters.isBlank || !excludedRelationships.isBlank
            || !excludedAdditionalTags.isBlank
            || rating != .any || !includeNotRated
            || !warnings.isEmpty || !excludedWarnings.isEmpty
            || !categories.isEmpty || !excludedCategories.isEmpty
            || crossover != .any || completion != .any
            || !wordsFrom.isBlank || !wordsTo.isBlank
            || updated != .any || language != .any || sort != .relevance
    }

    /// True when there's enough to run a search (free text or any filter).
    var isSearchable: Bool { !query.isBlank || hasActiveFilters }

    /// The free-text query AO3 receives, augmented with exclusions and any
    /// multi-rating expression that the single-value rating field can't express.
    nonisolated var searchQuery: String {
        var clauses: [String] = []
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty { clauses.append(trimmedQuery) }
        clauses += excludedTags.map { "-\"\($0)\"" }
        clauses += Warning.allCases
            .filter(excludedWarnings.contains)
            .map { "-archive_warning_ids:\($0.ao3ID)" }
        clauses += Category.allCases
            .filter(excludedCategories.contains)
            .map { "-category_ids:\($0.ao3ID)" }
        if let ratingSearchClause { clauses.append(ratingSearchClause) }
        return clauses.joined(separator: " ")
    }

    /// AO3's structured rating field can express exactly one rating. Rating+/-
    /// and optional Not Rated combinations are added to `searchQuery` instead.
    nonisolated var structuredRatingID: String? {
        let ratings = selectedRatings
        return ratings.count == 1 ? ratings[0].ao3ID : nil
    }

    nonisolated private var excludedTags: [String] {
        [excludedFandoms, excludedCharacters, excludedRelationships, excludedAdditionalTags]
            .flatMap(Self.commaSeparatedValues)
            .reduce(into: [String]()) { result, tag in
                if !result.contains(tag) { result.append(tag) }
            }
    }

    nonisolated private var ratingSearchClause: String? {
        if rating == .any {
            return includeNotRated ? nil : "-rating_ids:9"
        }
        let ratings = selectedRatings
        guard ratings.count > 1 else { return nil }
        return "(\(ratings.map(\.ratingQueryToken).joined(separator: " OR ")))"
    }

    nonisolated private var selectedRatings: [Rating] {
        guard rating != .any else { return [] }
        if rating == .notRated { return [.notRated] }

        let ranked: [Rating] = [.general, .teen, .mature, .explicit]
        guard let index = ranked.firstIndex(of: rating) else { return [] }
        var result: [Rating]
        switch ratingMatch {
        case .exact: result = [rating]
        case .orHigher: result = Array(ranked[index...])
        case .orLower: result = Array(ranked[...index])
        }
        if includeNotRated { result.append(.notRated) }
        return result
    }

    nonisolated private static func commaSeparatedValues(_ field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    nonisolated enum Rating: String, CaseIterable, Identifiable, Sendable, Codable {
        case any, general, teen, mature, explicit, notRated
        var id: String { rawValue }
        static let searchCases: [Self] = [.any, .general, .teen, .mature, .explicit]
        var title: String {
            switch self {
            case .any: "Any rating"
            case .general: "General Audiences"
            case .teen: "Teen And Up"
            case .mature: "Mature"
            case .explicit: "Explicit"
            case .notRated: "Not Rated"
            }
        }
        /// AO3's `rating_ids` value, or nil to leave rating unfiltered.
        var ao3ID: String? {
            switch self {
            case .any: nil
            case .notRated: "9"
            case .general: "10"
            case .teen: "11"
            case .mature: "12"
            case .explicit: "13"
            }
        }
        var ratingQueryToken: String {
            guard let ao3ID else { return "" }
            return "rating_ids:\(ao3ID)"
        }
    }

    nonisolated enum RatingMatch: String, CaseIterable, Identifiable, Sendable, Codable {
        case exact, orHigher, orLower
        var id: String { rawValue }
        var title: String {
            switch self {
            case .exact: "Exact"
            case .orHigher: "Rating+"
            case .orLower: "Rating−"
            }
        }
    }

    /// Archive warnings (AO3 `archive_warning_ids`). Raw value is the AO3 id.
    nonisolated enum Warning: String, CaseIterable, Identifiable, Sendable, Codable {
        case noWarnings = "16"
        case chooseNotTo = "14"
        case violence = "17"
        case death = "18"
        case nonCon = "19"
        case underage = "20"
        var id: String { rawValue }
        var ao3ID: String { rawValue }
        var title: String {
            switch self {
            case .noWarnings: "No Archive Warnings Apply"
            case .chooseNotTo: "Creator Chose Not To Use Archive Warnings"
            case .violence: "Graphic Depictions Of Violence"
            case .death: "Major Character Death"
            case .nonCon: "Rape/Non-Con"
            case .underage: "Underage Sex"
            }
        }
    }

    /// Categories (AO3 `category_ids`). Raw value is the AO3 id.
    nonisolated enum Category: String, CaseIterable, Identifiable, Sendable, Codable {
        case ff = "116", fm = "22", gen = "21", mm = "23", multi = "2246", other = "24"
        var id: String { rawValue }
        var ao3ID: String { rawValue }
        var title: String {
            switch self {
            case .ff: "F/F"
            case .fm: "F/M"
            case .gen: "Gen"
            case .mm: "M/M"
            case .multi: "Multi"
            case .other: "Other"
            }
        }
    }

    nonisolated enum Crossover: String, CaseIterable, Identifiable, Sendable, Codable {
        case any, exclude, only
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: "Include"
            case .exclude: "Exclude"
            case .only: "Only crossovers"
            }
        }
        /// AO3's `crossover` value (blank = include all).
        var value: String? {
            switch self {
            case .any: nil
            case .exclude: "F"
            case .only: "T"
            }
        }
    }

    nonisolated enum Completion: String, CaseIterable, Identifiable, Sendable, Codable {
        case any, complete, inProgress
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: "All"
            case .complete: "Complete"
            case .inProgress: "In Progress"
            }
        }
        /// AO3's `complete` value, or nil for all works.
        var value: String? {
            switch self {
            case .any: nil
            case .complete: "T"
            case .inProgress: "F"
            }
        }
    }

    /// "Updated within" — maps to AO3's `revised_at` (age-based: "< 1 week ago"
    /// means updated in the last week, verified against live AO3).
    nonisolated enum Updated: String, CaseIterable, Identifiable, Sendable, Codable {
        case any, week, month, sixMonths, year
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: "Any time"
            case .week: "Past week"
            case .month: "Past month"
            case .sixMonths: "Past 6 months"
            case .year: "Past year"
            }
        }
        var value: String? {
            switch self {
            case .any: nil
            case .week: "< 1 week ago"
            case .month: "< 1 month ago"
            case .sixMonths: "< 6 months ago"
            case .year: "< 1 year ago"
            }
        }
    }

    /// A curated set of common AO3 languages (codes are AO3 `language_id` values).
    nonisolated enum Language: String, CaseIterable, Identifiable, Sendable, Codable {
        case any = ""
        case english = "en"
        case spanish = "es"
        case french = "fr"
        case german = "de"
        case chinese = "zh"
        case japanese = "ja"
        case korean = "ko"
        case russian = "ru"
        case portuguese = "ptBR"
        case italian = "it"
        case arabic = "ar"
        case indonesian = "id"
        case dutch = "nl"
        case polish = "pl"
        case filipino = "fil"
        case hindi = "hi"
        case thai = "th"
        case vietnamese = "vi"
        case turkish = "tr"
        var id: String { rawValue }
        var code: String? { self == .any ? nil : rawValue }
        var title: String {
            switch self {
            case .any: "Any language"
            case .english: "English"
            case .spanish: "Spanish"
            case .french: "French"
            case .german: "German"
            case .chinese: "Chinese"
            case .japanese: "Japanese"
            case .korean: "Korean"
            case .russian: "Russian"
            case .portuguese: "Portuguese (BR)"
            case .italian: "Italian"
            case .arabic: "Arabic"
            case .indonesian: "Indonesian"
            case .dutch: "Dutch"
            case .polish: "Polish"
            case .filipino: "Filipino"
            case .hindi: "Hindi"
            case .thai: "Thai"
            case .vietnamese: "Vietnamese"
            case .turkish: "Turkish"
            }
        }
    }

    nonisolated enum Sort: String, CaseIterable, Identifiable, Sendable, Codable {
        case relevance, dateUpdated, datePosted, words, kudos, hits, comments, bookmarks
        var id: String { rawValue }
        var title: String {
            switch self {
            case .relevance: "Best Match"
            case .dateUpdated: "Date Updated"
            case .datePosted: "Date Posted"
            case .words: "Word Count"
            case .kudos: "Kudos"
            case .hits: "Hits"
            case .comments: "Comments"
            case .bookmarks: "Bookmarks"
            }
        }
        /// AO3's `sort_column` value, or nil for AO3's default (relevance).
        var column: String? {
            switch self {
            case .relevance: nil
            case .dateUpdated: "revised_at"
            case .datePosted: "created_at"
            case .words: "word_count"
            case .kudos: "kudos_count"
            case .hits: "hits"
            case .comments: "comments_count"
            case .bookmarks: "bookmarks_count"
            }
        }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// An error surfaced from the AO3 client, with a user-facing description.
enum AO3Error: LocalizedError {
    /// HTTP 429. `retryAfter` is the server's `Retry-After` hint in seconds, if given.
    case rateLimited(retryAfter: TimeInterval?)
    case notFound
    /// HTTP 5xx — a transient server-side error (retried automatically).
    case server(status: Int)
    /// Any other unexpected HTTP status (e.g. 4xx other than 404/429).
    case http(status: Int)
    case network(String)
    case parse
    /// AO3 bounced an authenticated request to its login page — the saved session
    /// is no longer valid and the user needs to sign in again.
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .rateLimited: "AO3 is rate-limiting requests. Wait a moment and try again."
        case .notFound: "That work or page couldn't be found (it may be restricted)."
        case .server(let status): "AO3 had a server problem (HTTP \(status)). Try again shortly."
        case .http(let status): "AO3 returned an unexpected response (HTTP \(status))."
        case .network(let detail): detail
        case .parse: "AO3's page format wasn't what the app expected."
        case .authenticationRequired: "Your AO3 session expired. Please log in again."
        }
    }
}

// MARK: - Tag autocomplete

/// The AO3 tag-autocomplete categories used by the filter tag pickers. `tag` is the
/// "any tag" endpoint, used for the Exclude field.
enum AO3TagKind: String, Sendable {
    case fandom, character, relationship, freeform, tag
}

/// The three-state selection used by Search's cycling multi-select filters.
nonisolated enum FilterSelectionState: Equatable, Sendable {
    case clear, included, excluded

    var next: Self {
        switch self {
        case .clear: .included
        case .included: .excluded
        case .excluded: .clear
        }
    }
}

// MARK: - Work tags (categorized)

/// A work's AO3 tags split by type, as shown on the work page. Used to display
/// saved-work tags under per-category headers. Also carries the work's archive
/// warnings, categories, language, and word count so the Library can filter on
/// the same facets Search offers.
nonisolated struct AO3WorkTagGroups: Sendable {
    var fandoms: [String] = []
    var relationships: [String] = []
    var characters: [String] = []
    var freeforms: [String] = []
    var warnings: [String] = []
    var categories: [String] = []
    var language: String = ""
    var words: Int?
    /// Chapter count as AO3 prints it (e.g. "5/10", "3/?"); "" when unknown.
    var chapters: String = ""
    var kudos: Int?
    var comments: Int?
    var hits: Int?

    /// Whether the page yielded no *tags* — the signal for a locked/empty work
    /// page, where the caller keeps the EPUB tags and retries later. (Warnings,
    /// categories, language and word count don't count toward this.)
    var isEmpty: Bool {
        fandoms.isEmpty && relationships.isEmpty && characters.isEmpty && freeforms.isEmpty
    }

    /// Flat union in AO3's canonical order, for the Library filter and the
    /// pre-refresh fallback list.
    var flattened: [String] { fandoms + relationships + characters + freeforms }
}

/// A single AO3 work page's refreshable metadata. Unlike `AO3WorkSummary`, which
/// mirrors result blurbs, this can include fields only present on the work page
/// (for example the published date). Callers merge it into local records only after
/// a full successful parse, so refresh never becomes a destructive sync operation.
nonisolated struct AO3WorkMetadata: Sendable {
    var id: Int
    var title: String = ""
    var authors: [String] = []
    var summary: String = ""
    var rating: String = ""
    var fandoms: [String] = []
    var relationships: [String] = []
    var characters: [String] = []
    var freeforms: [String] = []
    var warnings: [String] = []
    var categories: [String] = []
    var language: String = ""
    var words: Int?
    var chapters: String = ""
    var kudos: Int?
    var comments: Int?
    var hits: Int?
    var datePublished: String = ""
    var dateUpdated: String = ""
    var isComplete: Bool?
    var seriesTitle: String?
    var seriesURL: String?
    var seriesPosition: Int?

    var authorText: String { authors.isEmpty ? "Anonymous" : authors.joined(separator: ", ") }

    var tagGroups: AO3WorkTagGroups {
        AO3WorkTagGroups(
            fandoms: fandoms,
            relationships: relationships,
            characters: characters,
            freeforms: freeforms,
            warnings: warnings,
            categories: categories,
            language: language,
            words: words,
            chapters: chapters,
            kudos: kudos,
            comments: comments,
            hits: hits
        )
    }

    var summaryValue: AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: title,
            authors: authors,
            fandoms: fandoms,
            rating: rating,
            warnings: warnings,
            categories: categories,
            relationships: relationships,
            characters: characters,
            isComplete: isComplete,
            dateUpdated: dateUpdated,
            tags: freeforms,
            summary: summary,
            language: language,
            words: words,
            chapters: chapters,
            comments: comments,
            kudos: kudos,
            hits: hits,
            seriesTitle: seriesTitle,
            seriesURL: seriesURL,
            seriesPosition: seriesPosition
        )
    }
}

// MARK: - Media browser

/// A fandom as listed on AO3's media page; its `name` is the canonical AO3 tag,
/// which drops straight into a fandom search. `workCount` is the number of works
/// tagged with the fandom, shown on the fandom list when available.
struct AO3Fandom: Identifiable, Hashable, Sendable, Codable {
    var name: String
    var workCount: Int? = nil
    var id: String { name }
}

/// An AO3 collection (a named shelf), as listed on a user's collections page. `name`
/// is the URL slug (`/collections/<name>`); `title` is the display name; `byline` is
/// the maintainers line when shown.
struct AO3Collection: Identifiable, Hashable, Sendable {
    var name: String
    var title: String
    var byline: String = ""
    var id: String { name }
    var url: URL { URL(string: "https://archiveofourown.org/collections/\(name)")! }
}

/// One of AO3's media categories (e.g. "TV Shows") with its featured fandoms,
/// scraped from `/media`. `fandomsURL` points at the category's full fandom index
/// (`/media/<name>/fandoms`), loaded on demand by the fandom detail page.
struct AO3MediaCategory: Identifiable, Hashable, Sendable {
    var name: String
    var fandoms: [AO3Fandom]
    var fandomsURL: String = ""
    var id: String { name }

    /// A representative SF Symbol, matched by AO3's category names with a fallback.
    var symbol: String {
        switch name {
        case "Anime & Manga": "sparkles"
        case "Books & Literature": "books.vertical"
        case "Cartoons & Comics & Graphic Novels": "books.vertical.fill"
        case "Celebrities & Real People": "person.2"
        case "Movies": "film"
        case "Music & Bands": "music.note"
        case "Other Media": "square.grid.2x2"
        case "Theater": "theatermasks"
        case "TV Shows": "tv"
        case "Video Games": "gamecontroller"
        case "Uncategorized Fandoms": "questionmark.folder"
        default: "tag"
        }
    }
}
