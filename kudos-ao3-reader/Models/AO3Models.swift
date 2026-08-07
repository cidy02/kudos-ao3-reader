import Foundation

// The value types describing AO3 search results and the inputs to a search.
// These are pure data (no networking) — `AO3Client` (in Services) fetches and
// populates them. The faceted-filter ids/values are taken from AO3's own search
// form; see `AO3Client` for the porting/verification notes.

/// A work as summarized on an AO3 search/listing page ("blurb").
nonisolated struct AO3WorkSummary: Identifiable, Hashable, Sendable {
    let id: Int
    var title: String
    var authors: [String]
    /// Verified identities parsed from the same AO3 byline links as `authors`.
    /// Kept alongside the legacy strings so existing consumers remain compatible.
    var authorIdentities: [AO3AuthorIdentity] = []
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
    /// Defaulted so the existing `AO3WorkSummary(...)` call sites that predate
    /// this stat keep compiling — AO3 omits `dd.bookmarks` when the count is 0.
    var bookmarks: Int?
    var hits: Int?
    /// Series info when the work is part of one (first series only, for v1).
    var seriesTitle: String?
    var seriesURL: String?
    var seriesPosition: Int?

    var workURL: URL {
        URL(string: "https://archiveofourown.org/works/\(id)")!
    }

    var authorText: String {
        authors.isEmpty ? "Anonymous" : authors.joined(separator: ", ")
    }

    /// A sparse summary for a *work subscription*. AO3's subscriptions page lists only
    /// each work's title, id, and author — no stats, fandoms, or rating — so those
    /// fields stay empty here; opening the work loads its full detail page.
    static func subscription(
        id: Int,
        title: String,
        authors: [String],
        authorIdentities: [AO3AuthorIdentity] = []
    ) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id, title: title, authors: authors, authorIdentities: authorIdentities,
            fandoms: [], rating: "",
            warnings: [], categories: [], isComplete: nil, dateUpdated: "",
            tags: [], summary: "", language: "", words: nil, chapters: "",
            comments: nil, kudos: nil, hits: nil,
            seriesTitle: nil, seriesURL: nil, seriesPosition: nil
        )
    }
}

/// One page of search results, with the current page and total page count
/// (parsed from AO3's pagination control) so the UI can show page navigation.
nonisolated struct AO3SearchPage: Sendable {
    var works: [AO3WorkSummary]
    var currentPage: Int
    var totalPages: Int
    /// AO3's own result-count heading, when the page carries one.
    var summary: AO3ResultSummary?
}

/// The count line AO3 prints above a works list — "92,495 Found",
/// "1 - 20 of 142,322 Works in Naruto (Anime & Manga)", "1 - 20 of 535 Works by
/// astolat". The *total* is the part worth having: it is the only place AO3
/// states how many works match, and it is not derivable from a page of 20 blurbs.
nonisolated struct AO3ResultSummary: Equatable, Sendable {
    /// Total matching works across every page.
    let total: Int
    /// AO3's own qualifier, verbatim and including its preposition — "in Naruto
    /// (Anime & Manga)", "by astolat". nil on `/works/search`, whose heading is
    /// just "<n> Found" and names no subject. Kept whole because it is what the
    /// spoken label reads out; the card shows `subject` instead.
    let scope: String?
    /// Which works this page is showing — `1...20` from AO3's "1 - 20 of …".
    /// nil on `/works/search`, which states a total and no range.
    let range: ClosedRange<Int>?

    /// The subject with AO3's preposition removed — "Naruto (Anime & Manga)",
    /// "astolat" — for use as a heading, where "in Naruto" would read oddly.
    var subject: String? {
        guard let scope else { return nil }
        for preposition in ["in ", "by "] where scope.hasPrefix(preposition) {
            return String(scope.dropFirst(preposition.count))
        }
        return scope
    }

    /// AO3 serves 20 works per page. Verified live 2026-08-06 on `/works/search`,
    /// and it is what AO3 itself prints on a tag list ("1 - 20 of …").
    static let worksPerPage = 20

    /// Which tag category this list's subject is, for the heading's glyph.
    ///
    /// Read off the works already on screen rather than asked of AO3: every work
    /// here carries the subject tag by definition, and `parseBlurb` has already
    /// sorted each work's tags into fandoms / relationships / characters /
    /// freeforms using AO3's own markup classes. So the answer is sitting in the
    /// page that was just parsed — no `/tags/<name>` round-trip, no guessing from
    /// the name.
    ///
    /// A user list ("by astolat") is not a tag at all, hence the `by` short-circuit.
    /// nil when nothing matches — a work tagged with a *synonym* displays the
    /// synonym while the heading shows the canonical name, and no icon is better
    /// than a wrong one.
    func subjectField(inAnyOf works: [AO3WorkSummary]) -> AO3TagSearch.Field? {
        guard let subject else { return nil }
        if scope?.hasPrefix("by ") == true { return .character }
        let needle = subject.lowercased()
        func matches(_ values: [String]) -> Bool {
            values.contains { $0.lowercased() == needle }
        }
        for work in works {
            if matches(work.fandoms) { return .fandom }
            if matches(work.relationships) { return .relationship }
            if matches(work.characters) { return .character }
            if matches(work.tags) { return .freeform }
        }
        return nil
    }

    /// Fills in what a `/works/search` heading leaves out.
    ///
    /// A tag or user list heading states its subject and its range; a search states
    /// only "142,327 Found". But a screen scoped to one fandom *knows* it is that
    /// fandom's works list, and knows which page it asked for — so it can complete
    /// its own card rather than showing a bare number. Anything AO3 actually said
    /// wins: this only ever fills a nil.
    ///
    /// `onPageCount` is how many works came back, which is what makes the last
    /// (short) page come out right. Only the *start* of the range depends on
    /// `worksPerPage`, so if AO3 ever changed its page size, page 1 would still be
    /// correct and later pages would drift — a visible, bounded wrongness rather
    /// than a silent one.
    func completing(subject: String?, page: Int, onPageCount: Int) -> AO3ResultSummary {
        var derived: ClosedRange<Int>?
        if range == nil, onPageCount > 0, page > 0 {
            let first = (page - 1) * Self.worksPerPage + 1
            derived = first ... max(first, min(first + onPageCount - 1, total))
        }
        return AO3ResultSummary(
            total: total,
            scope: scope ?? subject.map { "in \($0)" },
            range: range ?? derived
        )
    }
}

/// A bounded look at a series page. Used before automatic series preservation so
/// Kudos can avoid crawling an unknown large series merely to decide whether to ask.
nonisolated struct AO3SeriesPreview: Equatable, Sendable {
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
/// Tiny text-parsing helpers shared by `LibraryFilters` and `AO3SummaryFilter` —
/// both match a work's tag facets and word-count bounds, just over different
/// model shapes (`SavedWork`'s flat/categorized tags vs. `AO3WorkSummary`'s arrays).
nonisolated enum FilterTextMatching {
    static func lowercased(_ values: [String]) -> Set<String> {
        Set(values.map { $0.lowercased() })
    }

    /// The first run of digits in a free-typed word-count bound field, or nil if
    /// the field has none (e.g. empty or non-numeric).
    static func bound(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }
}

nonisolated struct AO3SearchFilters: Equatable, Codable, Sendable {
    var query: String = ""
    /// AO3's own `title` / `creators` fields. Distinct from `query`, which also
    /// matches summaries and tags — searching an author through `query` returns
    /// materially noisier results than the dedicated field does.
    var title: String = ""
    var creators: String = ""
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
    var chapterCount: ChapterCount = .any
    // AO3 parses the same range grammar for all five numeric fields.
    var wordsFrom: String = ""
    var wordsTo: String = ""
    var hitsFrom: String = ""
    var hitsTo: String = ""
    var kudosFrom: String = ""
    var kudosTo: String = ""
    var commentsFrom: String = ""
    var commentsTo: String = ""
    var bookmarksFrom: String = ""
    var bookmarksTo: String = ""
    var updated: Updated = .any
    /// Absolute bounds on the same axis as `updated` — otwarchive's `date_from`/
    /// `date_to` filter `revised_at`, exactly what the relative window does. AO3
    /// ANDs them, so setting both narrows to the intersection.
    var dateFrom: Date?
    var dateTo: Date?
    var language: Language = .any
    var sort: Sort = .relevance

    var sortDirection: SortDirection = .descending

    // `SavedSearch` persists this struct via Codable (SwiftData). Synthesized
    // `Decodable` requires every key to be present, so a plain new stored property
    // would fail to decode every `SavedSearch` a user already saved before this
    // field existed — decode it leniently instead, defaulting to `.any` when absent.
    // (`Language`'s own Codable is customized separately, for the same reason.)
    private enum CodingKeys: CodingKey {
        case query, title, creators, fandom, characters, relationships, additionalTags,
            excludedFandoms, excludedCharacters, excludedRelationships, excludedAdditionalTags,
            rating, ratingMatch, includeNotRated, warnings, excludedWarnings,
            categories, excludedCategories, crossover, completion, chapterCount,
            wordsFrom, wordsTo, hitsFrom, hitsTo, kudosFrom, kudosTo,
            commentsFrom, commentsTo, bookmarksFrom, bookmarksTo,
            updated, dateFrom, dateTo, language, sort, sortDirection
    }

    init(
        query: String = "", title: String = "", creators: String = "",
        fandom: String = "", characters: String = "", relationships: String = "",
        additionalTags: String = "", excludedFandoms: String = "", excludedCharacters: String = "",
        excludedRelationships: String = "", excludedAdditionalTags: String = "", rating: Rating = .any,
        ratingMatch: RatingMatch = .exact, includeNotRated: Bool = true, warnings: Set<Warning> = [],
        excludedWarnings: Set<Warning> = [], categories: Set<Category> = [],
        excludedCategories: Set<Category> = [], crossover: Crossover = .any, completion: Completion = .any,
        chapterCount: ChapterCount = .any, wordsFrom: String = "", wordsTo: String = "",
        hitsFrom: String = "", hitsTo: String = "", kudosFrom: String = "", kudosTo: String = "",
        commentsFrom: String = "", commentsTo: String = "",
        bookmarksFrom: String = "", bookmarksTo: String = "",
        updated: Updated = .any, dateFrom: Date? = nil, dateTo: Date? = nil,
        language: Language = .any, sort: Sort = .relevance,
        sortDirection: SortDirection = .descending
    ) {
        self.query = query
        self.title = title
        self.creators = creators
        self.fandom = fandom
        self.characters = characters
        self.relationships = relationships
        self.additionalTags = additionalTags
        self.excludedFandoms = excludedFandoms
        self.excludedCharacters = excludedCharacters
        self.excludedRelationships = excludedRelationships
        self.excludedAdditionalTags = excludedAdditionalTags
        self.rating = rating
        self.ratingMatch = ratingMatch
        self.includeNotRated = includeNotRated
        self.warnings = warnings
        self.excludedWarnings = excludedWarnings
        self.categories = categories
        self.excludedCategories = excludedCategories
        self.crossover = crossover
        self.completion = completion
        self.chapterCount = chapterCount
        self.wordsFrom = wordsFrom
        self.wordsTo = wordsTo
        self.hitsFrom = hitsFrom
        self.hitsTo = hitsTo
        self.kudosFrom = kudosFrom
        self.kudosTo = kudosTo
        self.commentsFrom = commentsFrom
        self.commentsTo = commentsTo
        self.bookmarksFrom = bookmarksFrom
        self.bookmarksTo = bookmarksTo
        self.updated = updated
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.language = language
        self.sort = sort
        self.sortDirection = sortDirection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decode(String.self, forKey: .query)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        creators = try container.decodeIfPresent(String.self, forKey: .creators) ?? ""
        fandom = try container.decode(String.self, forKey: .fandom)
        characters = try container.decode(String.self, forKey: .characters)
        relationships = try container.decode(String.self, forKey: .relationships)
        additionalTags = try container.decode(String.self, forKey: .additionalTags)
        excludedFandoms = try container.decode(String.self, forKey: .excludedFandoms)
        excludedCharacters = try container.decode(String.self, forKey: .excludedCharacters)
        excludedRelationships = try container.decode(String.self, forKey: .excludedRelationships)
        excludedAdditionalTags = try container.decode(String.self, forKey: .excludedAdditionalTags)
        rating = try container.decode(Rating.self, forKey: .rating)
        ratingMatch = try container.decode(RatingMatch.self, forKey: .ratingMatch)
        includeNotRated = try container.decode(Bool.self, forKey: .includeNotRated)
        warnings = try container.decode(Set<Warning>.self, forKey: .warnings)
        excludedWarnings = try container.decode(Set<Warning>.self, forKey: .excludedWarnings)
        categories = try container.decode(Set<Category>.self, forKey: .categories)
        excludedCategories = try container.decode(Set<Category>.self, forKey: .excludedCategories)
        crossover = try container.decode(Crossover.self, forKey: .crossover)
        completion = try container.decode(Completion.self, forKey: .completion)
        chapterCount = try container.decodeIfPresent(ChapterCount.self, forKey: .chapterCount) ?? .any
        wordsFrom = try container.decode(String.self, forKey: .wordsFrom)
        wordsTo = try container.decode(String.self, forKey: .wordsTo)
        hitsFrom = try container.decodeIfPresent(String.self, forKey: .hitsFrom) ?? ""
        hitsTo = try container.decodeIfPresent(String.self, forKey: .hitsTo) ?? ""
        kudosFrom = try container.decodeIfPresent(String.self, forKey: .kudosFrom) ?? ""
        kudosTo = try container.decodeIfPresent(String.self, forKey: .kudosTo) ?? ""
        commentsFrom = try container.decodeIfPresent(String.self, forKey: .commentsFrom) ?? ""
        commentsTo = try container.decodeIfPresent(String.self, forKey: .commentsTo) ?? ""
        bookmarksFrom = try container.decodeIfPresent(String.self, forKey: .bookmarksFrom) ?? ""
        bookmarksTo = try container.decodeIfPresent(String.self, forKey: .bookmarksTo) ?? ""
        updated = try container.decode(Updated.self, forKey: .updated)
        dateFrom = try container.decodeIfPresent(Date.self, forKey: .dateFrom)
        dateTo = try container.decodeIfPresent(Date.self, forKey: .dateTo)
        language = try container.decode(Language.self, forKey: .language)
        sort = try container.decode(Sort.self, forKey: .sort)
        sortDirection = try container.decodeIfPresent(SortDirection.self, forKey: .sortDirection) ?? .descending
    }

    /// True when any filter beyond the plain query is set (drives the filter
    /// button's "active" icon and the Reset action).
    var hasActiveFilters: Bool {
        !title.isBlank || !creators.isBlank
            || !fandom.isBlank || !characters.isBlank || !relationships.isBlank
            || !additionalTags.isBlank || !excludedFandoms.isBlank
            || !excludedCharacters.isBlank || !excludedRelationships.isBlank
            || !excludedAdditionalTags.isBlank
            || rating != .any || !includeNotRated
            || !warnings.isEmpty || !excludedWarnings.isEmpty
            || !categories.isEmpty || !excludedCategories.isEmpty
            || crossover != .any || completion != .any || chapterCount != .any
            || !wordsFrom.isBlank || !wordsTo.isBlank
            || !hitsFrom.isBlank || !hitsTo.isBlank
            || !kudosFrom.isBlank || !kudosTo.isBlank
            || !commentsFrom.isBlank || !commentsTo.isBlank
            || !bookmarksFrom.isBlank || !bookmarksTo.isBlank
            || updated != .any || dateFrom != nil || dateTo != nil
            || language != .any
            || sort != .relevance || sortDirection != .descending
    }

    /// True when there's enough to run a search (free text or any filter).
    var isSearchable: Bool {
        !query.isBlank || hasActiveFilters
    }

    /// One chip on the results card.
    struct SummaryLabel: Equatable, Hashable, Sendable {
        let text: String
        /// The tag category's glyph, for the entries that *are* tags. nil for
        /// facets like a rating or the sort, which are not tag categories and
        /// would be given a misleading one.
        let symbol: String?
    }

    /// What this search is *of*, for the results card's heading.
    ///
    /// `/works/search` answers with a bare `"202,439 Found"` — no scope clause at
    /// all, where a tag or user list says "… in Naruto" — so the card had a count
    /// and nothing above it. The screen knows what was asked for even though the
    /// response doesn't restate it.
    ///
    /// A tag field wins over the free-text query and brings its own category with
    /// it, so a search for the *fandom* Naruto is titled like a fandom rather than
    /// guessed at from the results. Exactly one field, holding exactly one name:
    /// with two set, no single one of them is what the list is "of", and a heading
    /// naming one would misdescribe the other.
    ///
    /// Never nil: a search run on facets alone (a rating, a language, a word
    /// count) has no name of its own, and `searchResultsFallback` titles it rather
    /// than leaving the card as a floating number.
    var searchSubject: (text: String, field: AO3TagSearch.Field?) {
        let tagFields: [(String, AO3TagSearch.Field)] = [
            (fandom, .fandom),
            (characters, .character),
            (relationships, .relationship),
            (additionalTags, .freeform),
        ]
        let filled = tagFields.filter { !$0.0.trimmingCharacters(in: .whitespaces).isEmpty }
        if filled.count == 1, let only = filled.first {
            let names = only.0
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if names.count == 1, let name = names.first { return (name, only.1) }
        }
        let text = query.trimmingCharacters(in: .whitespaces)
        return (text.isEmpty ? Self.searchResultsFallback : text, nil)
    }

    /// AO3's own wording for a results page with nothing to name — it is what the
    /// site prints as the `<h3>` on `/works/search` before the count line.
    static let searchResultsFallback = "Search Results"

    /// what the results card shows so the user can see the filters without
    /// reopening the panel.
    ///
    /// Only *non-default* settings appear. "Any rating" and "All" are the absence
    /// of a filter, and listing them would spend the card's height saying nothing,
    /// loudest in the common case where nothing is set.
    ///
    /// Order and wording follow the Android port's `activeFilterChips` so the two
    /// apps describe the same filter set the same way, and every label is an
    /// existing `title` rather than new prose. `excluding` names the one thing this
    /// list would otherwise repeat: on a fandom's page the card's own heading is
    /// already the fandom.
    /// `includesSort: false` for a screen whose filters only narrow what is already
    /// on the page (`AO3FilterPanel.Mode.refine`). That panel deliberately hides
    /// Sort — re-ordering needs a fresh AO3 query — so advertising a sort on the
    /// card would name a control the user cannot reach and an order that is not
    /// being applied.
    func summaryLabels(excluding subject: String? = nil, includesSort: Bool = true) -> [SummaryLabel] {
        var labels: [SummaryLabel] = []

        func add(_ text: String, _ symbol: String? = nil) {
            labels.append(SummaryLabel(text: text, symbol: symbol))
        }
        func addTags(_ field: AO3TagSearch.Field, included: String, excluded: String) {
            for tag in Self.commaSeparatedValues(included) where tag != subject {
                add(tag, field.symbol)
            }
            for tag in Self.commaSeparatedValues(excluded) {
                add("−\(tag)", field.symbol)
            }
        }
        addTags(.fandom, included: fandom, excluded: excludedFandoms)
        addTags(.character, included: characters, excluded: excludedCharacters)
        addTags(.relationship, included: relationships, excluded: excludedRelationships)
        addTags(.freeform, included: additionalTags, excluded: excludedAdditionalTags)

        if !title.isBlank { add("Title: \(title)") }
        if !creators.isBlank { add("By: \(creators)") }

        if rating != .any {
            switch ratingMatch {
            case .exact: add(rating.title)
            case .orHigher: add("\(rating.title)+")
            case .orLower: add("\(rating.title)−")
            }
        }
        if !includeNotRated { add("No Not Rated") }

        for warning in Warning.allCases.filter(warnings.contains) { add(warning.title, AO3TagSearch.Field.warning.symbol) }
        for warning in Warning.allCases.filter(excludedWarnings.contains) { add("−\(warning.title)", AO3TagSearch.Field.warning.symbol) }
        for category in Category.allCases.filter(categories.contains) { add(category.title) }
        for category in Category.allCases.filter(excludedCategories.contains) { add("−\(category.title)") }

        if crossover != .any { add("Crossover: \(crossover.title)") }
        if completion != .any { add(completion.title) }
        if chapterCount != .any { add(chapterCount.title) }

        for (name, from, to) in [
            ("Words", wordsFrom, wordsTo), ("Hits", hitsFrom, hitsTo),
            ("Kudos", kudosFrom, kudosTo), ("Comments", commentsFrom, commentsTo),
            ("Bookmarks", bookmarksFrom, bookmarksTo)
        ] {
            let lower = from.trimmingCharacters(in: .whitespaces)
            let upper = to.trimmingCharacters(in: .whitespaces)
            switch (lower.isEmpty, upper.isEmpty) {
            case (false, false): add("\(name) \(lower)–\(upper)")
            case (false, true): add("\(name) ≥ \(lower)")
            case (true, false): add("\(name) ≤ \(upper)")
            case (true, true): break
            }
        }

        if updated != .any { add(updated.title) }
        if let dateFrom { add("After \(Self.dateBoundFormatter.string(from: dateFrom))") }
        if let dateTo { add("Before \(Self.dateBoundFormatter.string(from: dateTo))") }
        if language != .any { add(language.title) }

// Sort last, and unconditionally where it applies: unlike every entry
        // above there is always an order in effect, so this is the one label that
        // is never noise — and it is the setting users most often forget.
        if includesSort { add("Sort: \(sort.title)") }
        return labels
    }

    /// The free-text query AO3 receives, augmented with exclusions and any
    /// multi-rating expression that the single-value rating field can't express.
    nonisolated var searchQuery: String {
        var clauses: [String] = []
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty { clauses.append(trimmedQuery) }
        // Excluded *tags* are no longer folded in here — they go to AO3's own
        // `work_search[excluded_tag_names]` (see `excludedTagNames`). Warnings and
        // categories stay, because AO3 has no structured exclusion for those.
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

    /// The four excluded-tag fields as AO3's own `work_search[excluded_tag_names]`
    /// — a comma-separated list, live-verified to take more than one name.
    ///
    /// This used to be synthesized into `work_search[query]` as `-"tag"`, because
    /// AO3's *form* has no exclusion inputs. The endpoint does
    /// (`WorkSearchForm::ATTRIBUTES`), and it is the better channel on both counts:
    /// it excludes by tag rather than by phrase, where a quoted phrase also hit
    /// summary and title text, and it removes the need to escape user text into
    /// query syntax at all. Measured on one corpus (92,493 works): excluding
    /// "Time Travel" + "Fluff" leaves 74,261 here vs 73,419 through query syntax,
    /// the difference being works that merely *mention* those words.
    ///
    /// otwarchive splits each name down one of **two** routes, and which one it
    /// takes decides how well the exclusion works:
    ///   - **Recognised names** are looked up in the tag DB and their ids go into
    ///     `exclusion_ids` → `term_filter(:filter_ids, id)`. `filter_ids` are a
    ///     work's *canonical* filter tags, so this also removes synonyms and
    ///     sub-tags of the excluded tag. This is the common case and the point.
    ///   - **Unrecognised names** fall through to `named_tag_exclusion_filter` →
    ///     `match_filter(:tag, name)`, an AND over the name's tokens. A typo
    ///     therefore excludes *nothing*, silently — correct (no work carries that
    ///     tag) but invisible.
    ///
    /// Case matters on AO3's side, and the app is already insulated from it.
    /// `taggable_query.rb` computes missing names as `names - found.map(&:second)`,
    /// a case-*sensitive* Ruby array difference, while the DB lookup that produced
    /// `found` is case-*insensitive*. A wrongly-cased name is therefore both found
    /// and missing and gets both filters — so it excludes slightly *more*, never
    /// less. Measured on the same corpus: `Time Travel` → 89,855, `time travel` →
    /// 89,741.
    ///
    /// Nothing is normalised here on purpose: **these strings are already AO3's
    /// own.** Every tag in the filter panel arrives from `TagSelectField`, which
    /// has no free-text entry — the only way in is picking a result from AO3's
    /// autocomplete (`AO3Client.autocompleteTags`) or tapping a tag on a work,
    /// both of which are AO3's own spelling. Guessing at case here would risk
    /// mangling a name AO3 supplied, to fix input the app does not accept.
    nonisolated var excludedTagNames: String? {
        let tags = [excludedFandoms, excludedCharacters, excludedRelationships, excludedAdditionalTags]
            .flatMap(Self.commaSeparatedValues)
            .reduce(into: [String]()) { result, tag in
                if !result.contains(tag) { result.append(tag) }
            }
        return tags.isEmpty ? nil : tags.joined(separator: ",")
    }

    private nonisolated var ratingSearchClause: String? {
        if rating == .any {
            return includeNotRated ? nil : "-rating_ids:9"
        }
        let ratings = selectedRatings
        guard ratings.count > 1 else { return nil }
        return "(\(ratings.map(\.ratingQueryToken).joined(separator: " OR ")))"
    }

    private nonisolated var selectedRatings: [Rating] {
        guard rating != .any else { return [] }
        if rating == .notRated { return [.notRated] }

        let ranked: [Rating] = [.general, .teen, .mature, .explicit]
        guard let index = ranked.firstIndex(of: rating) else { return [] }
        var result: [Rating] = switch ratingMatch {
        case .exact: [rating]
        case .orHigher: Array(ranked[index...])
        case .orLower: Array(ranked[...index])
        }
        if includeNotRated { result.append(.notRated) }
        return result
    }

    // `quotedPhrase(_:)` lived here: it backslash-escaped user text before
    // interpolating it into `work_search[query]` as `-"tag"`. Deleted along with
    // its only caller — exclusions now go through `excluded_tag_names`, so no user
    // text is interpolated into query syntax any more and there is nothing left to
    // escape. (The escape sequence was correct; the whole hazard is simply gone.)

    /// The `yyyy-MM-dd` AO3 wants for `date_from`/`date_to`. Fixed format, so a
    /// POSIX locale and a static instance — same reason as `retryAfterDateFormatter`.
    ///
    /// **Local time zone, unlike `retryAfterDateFormatter`'s GMT.** That one parses
    /// an HTTP-date, which really is an instant in GMT. This one formats a *calendar
    /// day the user picked off a `DatePicker`*, and AO3's `date_from`/`date_to` are
    /// calendar days too — so there is no instant to convert and pinning to UTC only
    /// shifts the day. It shifted it in both directions: `DatePicker(.date)` keeps
    /// the bound's time-of-day, which `AO3FilterPanel.dateBound` seeds with the local
    /// wall-clock moment the toggle was switched on, so a UTC+ user who toggled in
    /// the morning emitted the *previous* day and a UTC− user who toggled in the
    /// evening emitted the *next* one (4 of 9 realistic zone/hour pairs were wrong).
    /// `.autoupdatingCurrent`, not `.current`, because this instance outlives any
    /// time-zone change the user makes while the app is running.
    nonisolated static let dateBoundFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// AO3's numeric range grammar, shared by `word_count`, `hits`,
    /// `kudos_count`, `comments_count` and `bookmarks_count` — all five parse
    /// identically server-side (otwarchive `SearchRange`). nil when unbounded.
    nonisolated static func rangeExpression(from: String, to: String) -> String? {
        let lower = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = to.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (lower.isEmpty, upper.isEmpty) {
        case (false, false): return "\(lower)-\(upper)"
        case (false, true): return "> \(lower)"
        case (true, false): return "< \(upper)"
        case (true, true): return nil
        }
    }

    private nonisolated static func commaSeparatedValues(_ field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    nonisolated enum Rating: String, CaseIterable, Identifiable, Codable {
        case any, general, teen, mature, explicit, notRated
        var id: String {
            rawValue
        }

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

    nonisolated enum RatingMatch: String, CaseIterable, Identifiable, Codable {
        case exact, orHigher, orLower
        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .exact: "Exact"
            case .orHigher: "Rating+"
            case .orLower: "Rating−"
            }
        }
    }

    /// Archive warnings (AO3 `archive_warning_ids`). Raw value is the AO3 id.
    nonisolated enum Warning: String, CaseIterable, Identifiable, Codable {
        case noWarnings = "16"
        case chooseNotTo = "14"
        case violence = "17"
        case death = "18"
        case nonCon = "19"
        case underage = "20"
        var id: String {
            rawValue
        }

        var ao3ID: String {
            rawValue
        }

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
    nonisolated enum Category: String, CaseIterable, Identifiable, Codable {
        case ff = "116", fm = "22", gen = "21", mm = "23", multi = "2246", other = "24"
        var id: String {
            rawValue
        }

        var ao3ID: String {
            rawValue
        }

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

    nonisolated enum Crossover: String, CaseIterable, Identifiable, Codable {
        case any, exclude, only
        var id: String {
            rawValue
        }

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

    nonisolated enum Completion: String, CaseIterable, Identifiable, Codable {
        case any, complete, inProgress
        var id: String {
            rawValue
        }

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

    /// AO3's "Single Chapter?" search checkbox — the only chapter-count filter the
    /// site's search form offers (no "multi-chapter only" counterpart exists).
    nonisolated enum ChapterCount: String, CaseIterable, Identifiable, Codable {
        case any, singleChapter
        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .any: "Any"
            case .singleChapter: "Single Chapter Only"
            }
        }

        /// AO3's `single_chapter` value, or nil for no filter.
        var value: String? {
            self == .singleChapter ? "1" : nil
        }
    }

    /// "Updated within" — maps to AO3's `revised_at` (age-based: "< 1 week ago"
    /// means updated in the last week, verified against live AO3).
    nonisolated enum Updated: String, CaseIterable, Identifiable, Codable {
        case any, week, month, sixMonths, year
        var id: String {
            rawValue
        }

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

    /// Every language AO3's own search form offers (`work_search[language_id]`
    /// values and labels), live-verified against archiveofourown.org/works/search —
    /// not a curated subset, since a curated list is exactly the parity gap this
    /// closes. Labels are AO3's own text verbatim (native names, dual-script
    /// entries like "中文-普通话 國語") rather than re-translated, so there's one
    /// source of truth for what each id means.
    nonisolated struct Language: Identifiable, Equatable, Hashable, Codable, Sendable {
        /// AO3's `language_id` value; "" for the "Any language" placeholder.
        ///
        /// **The only stored property, deliberately.** `title` is derived from it
        /// (`rawList` is the one source of truth for both), and that is load-bearing
        /// for persistence, not just tidiness: `SavedSearch.filters` is a SwiftData
        /// composite attribute, so every *stored* property here becomes its own
        /// SQLite column. When `title` was stored too, the columns were `ZID` and
        /// `ZTITLE1` — and because SwiftData fills those columns from the
        /// `Encodable` conformance, a `singleValueContainer` encoder supplied one
        /// value for two columns, wrote `title` as `NULL`, and CoreData then
        /// rejected the whole row ("missing mandatory text data for property
        /// 'title'"). Every saved search vanished on read. One stored property
        /// cannot have that failure, and it restores the single-column shape the
        /// original `enum Language: String` had, so rows written while `title` was
        /// stored — `NULL` column and all — load again.
        let id: String

        init(id: String) {
            self.id = id
        }

        static let any = Language(id: "")

        /// AO3's own label for this id. Native names verbatim, never re-translated.
        /// Unknown ids (AO3 adds a language this build predates) show the raw id
        /// rather than nothing.
        var title: String {
            if id.isEmpty { return "Any language" }
            return Self.titlesByID[id] ?? id
        }

        /// The `work_search[language_id]` query value, or nil to leave it unset.
        var code: String? {
            id.isEmpty ? nil : id
        }

        static let allCases: [Language] = [.any] + rawList.map { Language(id: $0.0) }

        private static let titlesByID: [String: String] =
            Dictionary(rawList, uniquingKeysWith: { first, _ in first })

        private static let rawList: [(String, String)] = [
            ("so", "af Soomaali"), ("afr", "Afrikaans"), ("ain", "Aynu itak | アイヌ イタㇰ"), ("akk", "𒀝𒅗𒁺𒌑"),
            ("ar", "العربية"), ("amh", "አማርኛ"), ("egy", "𓂋𓏺𓈖 𓆎𓅓𓏏𓊖"), ("oji", "Anishinaabemowin"),
            ("arc", "ܐܪܡܝܐ | ארמיא"), ("hy", "հայերեն"), ("ase", "American Sign Language"), ("ast", "asturianu"),
            ("azj", "Azərbaycan dili | آذربایجان دیلی"), ("id", "Bahasa Indonesia"), ("ms", "Bahasa Malaysia"),
            ("bg", "Български"), ("bn", "বাংলা"), ("jv", "Basa Jawa"), ("sun", "ᮘᮞ ᮞᮥᮔ᮪ᮓ | Basa Sunda"),
            ("ba", "Башҡорт теле"), ("be", "беларуская"), ("bar", "Boarisch"), ("bos", "Bosanski"),
            ("br", "Brezhoneg"), ("bfi", "British Sign Language"),
            ("bua", "Буряад хэлэн | ᠪᠤᠷᠢᠶᠠᠳ ᠮᠣᠩᠭᠣᠯ ᠬᠡᠯᠡ"), ("ca", "Català"), ("ceb", "Cebuano"), ("cs", "Čeština"),
            ("chn", "Chinuk Wawa"), ("crh", "къырымтатар тили | qırımtatar tili"), ("cy", "Cymraeg"),
            ("da", "Dansk"), ("de", "Deutsch"), ("div", "ދިވެހި,"), ("et", "eesti keel"), ("el", "Ελληνικά"),
            ("sux", "𒅴𒂠"), ("en", "English"), ("ang", "Eald Englisċ"), ("es", "Español"), ("eo", "Esperanto"),
            ("eu", "Euskara"), ("fa", "فارسی"), ("fil", "Filipino"), ("cha", "Finuʼ Chamorro"),
            ("fr", "Français"), ("frr", "Friisk"), ("fry", "Frysk"), ("fur", "Furlan"), ("ga", "Gaeilge"),
            ("gd", "Gàidhlig"), ("gl", "Galego"), ("got", "𐌲𐌿𐍄𐌹𐍃𐌺𐌰"), ("gyn", "Creolese"),
            ("hak", "中文-客家话"), ("ko", "한국어"), ("hau", "Hausa | هَرْشَن هَوْسَ"), ("hi", "हिन्दी"),
            ("mww", "Hmoob dawb"), ("hr", "Hrvatski"), ("haw", "ʻŌlelo Hawaiʻi"), ("ia", "Interlingua"),
            ("zu", "isiZulu"), ("is", "Íslenska"), ("it", "Italiano"), ("he", "עברית"), ("kal", "Kalaallisut"),
            ("xal", "Хальмг Өөрдин келн"), ("moh", "Kanienʼkéha"), ("kan", "ಕನ್ನಡ"), ("kat", "ქართული"),
            ("cor", "Kernewek"), ("khm", "ភាសាខ្មែរ"), ("qkz", "Khuzdul"), ("sw", "Kiswahili"),
            ("ht", "kreyòl ayisyen"), ("ku", "Kurdî | کوردی"), ("kir", "Кыргызча"), ("lad", "Ladino / לאדינו"),
            ("fcs", "Langue des signes québécoise"), ("lv", "Latviešu valoda"), ("lb", "Lëtzebuergesch"),
            ("lt", "Lietuvių kalba"), ("la", "Lingua latina"), ("hu", "Magyar"), ("mk", "македонски"),
            ("ml", "മലയാളം"), ("mt", "Malti"), ("mnc", "ᠮᠠᠨᠵᡠ ᡤᡳᠰᡠᠨ"), ("qmd", "Mando'a"), ("mr", "मराठी"),
            ("mic", "Mi'kmaq"), ("enm", "Middel Englisch"), ("mik", "Mikisúkî"), ("hnj", "Moob leeg"),
            ("mon", "ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ᠌ | Монгол Кирилл үсэг"), ("my", "မြန်မာဘာသာ"), ("myv", "Эрзянь кель"),
            ("qnv", "Lìʼfya leNaʼvi"), ("nah", "Nāhuatl"), ("nan", "中文-闽南话 臺語"), ("ppl", "Nawat"),
            ("nl", "Nederlands"), ("ja", "日本語"), ("no", "Norsk"), ("ce", "Нохчийн мотт"),
            ("ood", "O'odham Ñiok"), ("ota", "لسان عثمانى"), ("ps", "پښتو"),
            ("pdc", "Pennsilfaanisch Deitsch"), ("nds", "Plattdüütsch"), ("pl", "Polski"),
            ("ptBR", "Português brasileiro"), ("ptPT", "Português europeu"), ("fuc", "Pulaar"),
            ("pa", "ਪੰਜਾਬੀ"), ("kaz", "qazaqşa | қазақша"), ("qlq", "Uncategorized Constructed Languages"),
            ("qya", "Quenya"), ("ro", "Română"), ("rom", "RRomani Ćhib"), ("ru", "Русский"), ("smi", "Sámi"),
            ("sah", "саха тыла"), ("sco", "Scots"), ("sq", "Shqip"), ("sjn", "Sindarin"), ("si", "සිංහල"),
            ("sk", "Slovenčina"), ("slv", "Slovenščina"), ("sla", "Slověnьskъ Językъ"),
            ("gem", "Sprēkō Þiudiskō"), ("sr", "Српски"), ("fi", "suomi"), ("sv", "Svenska"),
            ("ta", "தமிழ்"), ("tat", "татар теле"), ("mri", "te reo Māori"), ("tel", "తెలుగు"),
            ("tir", "ትግርኛ"), ("th", "ไทย"), ("tqx", "Thermian"), ("bod", "བོད་སྐད་"), ("vi", "Tiếng Việt"),
            ("cop", "ϯⲙⲉⲧⲣⲉⲙⲛ̀ⲭⲏⲙⲓ"), ("tlh", "tlhIngan-Hol"), ("tok", "toki pona"),
            ("trf", "Trinidadian Creole"), ("tsd", "τσακώνικα"), ("chr", "ᏣᎳᎩ ᎦᏬᏂᎯᏍᏗ"), ("tr", "Türkçe"),
            ("uk", "Українська"), ("ale", "Unangam Tunuu"), ("urd", "اُردُو"), ("uig", "ئۇيغۇر تىلى"),
            ("vol", "Volapük"), ("wuu", "中文-吴语"), ("yi", "יידיש"), ("yua", "maayaʼ tʼàan"),
            ("yue", "中文-广东话 粵語"), ("zh", "中文-普通话 國語")
        ]

        // Only `id`: it is the only stored property, and a case without one would
        // stop `encode(to:)` synthesizing. A `title` in an older payload is simply
        // an unread key.
        enum CodingKeys: String, CodingKey {
            case id
        }

        /// Accepts all three shapes this type has ever been written in, because
        /// `SavedSearch` records survive across every one of them:
        ///   1. `{"id": "fr"}` — today, and what the synthesized encoder emits.
        ///   2. `{"id": "fr", "title": "Français"}` — written while `title` was a
        ///      stored property. The title is read but ignored; `rawList` is the
        ///      source of truth, so a label AO3 has since re-spelled self-heals.
        ///   3. `"fr"` — a bare string, from the original `enum Language: String`.
        ///
        /// `encode(to:)` is deliberately **not** implemented. A custom one is what
        /// broke persistence in the first place (see `id`), and the synthesized
        /// keyed encoder is the only shape that stays in step with the stored
        /// properties SwiftData built its columns from.
        init(from decoder: Decoder) throws {
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
               let code = try? keyed.decode(String.self, forKey: .id) {
                self = Language(id: code)
                return
            }
            let container = try decoder.singleValueContainer()
            self = Language(id: try container.decode(String.self))
        }
    }

    nonisolated enum Sort: String, CaseIterable, Identifiable, Codable {
        case relevance, creator, workTitle, dateUpdated, datePosted, words, kudos, hits, comments, bookmarks
        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .relevance: "Best Match"
            case .creator: "Creator"
            case .workTitle: "Title"
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
            case .creator: "authors_to_sort_on"
            case .workTitle: "title_to_sort_on"
            case .dateUpdated: "revised_at"
            case .datePosted: "created_at"
            case .words: "word_count"
            case .kudos: "kudos_count"
            case .hits: "hits"
            case .comments: "comments_count"
            case .bookmarks: "bookmarks_count"
            }
        }

        /// The direction a reader expects when they first pick this column.
        /// Alphabetical sorts read forwards; counts and dates read biggest/newest
        /// first. Only a starting point — `sortDirection` remains user-settable.
        var naturalDirection: SortDirection {
            switch self {
            case .creator, .workTitle: .ascending
            default: .descending
            }
        }
    }

    /// AO3's `sort_direction`. AO3 itself defaults to `desc` when the parameter
    /// is absent (otwarchive `WorkQuery`), so `.descending` preserves the
    /// behaviour this app had before the field was sent at all.
    nonisolated enum SortDirection: String, CaseIterable, Identifiable, Codable {
        case descending, ascending
        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .descending: "Descending"
            case .ascending: "Ascending"
            }
        }

        var value: String {
            switch self {
            case .descending: "desc"
            case .ascending: "asc"
            }
        }
    }
}

private extension String {
    nonisolated var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// An error surfaced from the AO3 client, with a user-facing description.
nonisolated enum AO3Error: LocalizedError, Sendable {
    /// HTTP 429. `retryAfter` is the server's `Retry-After` hint in seconds, if given.
    case rateLimited(retryAfter: TimeInterval?)
    case notFound
    /// HTTP 403 — AO3 (or its CDN) refused the request outright. Not retried:
    /// hammering a block only prolongs it.
    case forbidden
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
        case .forbidden: "AO3 refused the request (HTTP 403). Wait a while before trying again."
        case .notFound: "That work or page couldn't be found (it may be restricted)."
        case let .server(status): "AO3 had a server problem (HTTP \(status)). Try again shortly."
        case let .http(status): "AO3 returned an unexpected response (HTTP \(status))."
        case let .network(detail): detail
        case .parse: "AO3's page format wasn't what the app expected."
        case .authenticationRequired: "Your AO3 session expired. Please log in again."
        }
    }
}

// MARK: - Tag autocomplete

/// The AO3 tag-autocomplete categories used by the filter tag pickers. `tag` is the
/// "any tag" endpoint, used for the Exclude field.
nonisolated enum AO3TagKind: String, Sendable {
    case fandom, character, relationship, freeform, tag
}

/// The three-state selection used by Search's cycling multi-select filters.
nonisolated enum FilterSelectionState: Equatable {
    case clear, included, excluded

    var next: Self {
        switch self {
        case .clear: .included
        case .included: .excluded
        case .excluded: .clear
        }
    }

    /// VoiceOver-only status word, appended to a facet/tag's name so a cycling
    /// row's title and its include/exclude indicator announce as one combined
    /// stop instead of two. `nil` for `.clear` — sighted users see no badge
    /// either, so the announcement is just the bare name.
    var accessibilityStatus: String? {
        switch self {
        case .clear: nil
        case .included: "Included"
        case .excluded: "Excluded"
        }
    }
}

// MARK: - Work tags (categorized)

/// A work's AO3 tags split by type, as shown on the work page. Used to display
/// saved-work tags under per-category headers. Also carries the work's archive
/// warnings, categories, language, and word count so the Library can filter on
/// the same facets Search offers.
nonisolated struct AO3WorkTagGroups {
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
    var bookmarks: Int?
    var hits: Int?

    /// Whether the page yielded no *tags* — the signal for a locked/empty work
    /// page, where the caller keeps the EPUB tags and retries later. (Warnings,
    /// categories, language and word count don't count toward this.)
    var isEmpty: Bool {
        fandoms.isEmpty && relationships.isEmpty && characters.isEmpty && freeforms.isEmpty
    }

    /// Flat union in AO3's canonical order, for the Library filter and the
    /// pre-refresh fallback list.
    var flattened: [String] {
        fandoms + relationships + characters + freeforms
    }
}

/// A single AO3 work page's refreshable metadata. Unlike `AO3WorkSummary`, which
/// mirrors result blurbs, this can include fields only present on the work page
/// (for example the published date). Callers merge it into local records only after
/// a full successful parse, so refresh never becomes a destructive sync operation.
nonisolated struct AO3WorkMetadata {
    var id: Int
    var title: String = ""
    var authors: [String] = []
    var authorIdentities: [AO3AuthorIdentity] = []
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
    var bookmarks: Int?
    var hits: Int?
    var datePublished: String = ""
    var dateUpdated: String = ""
    var isComplete: Bool?
    var seriesTitle: String?
    var seriesURL: String?
    var seriesPosition: Int?

    var authorText: String {
        authors.isEmpty ? "Anonymous" : authors.joined(separator: ", ")
    }

    /// The same work as a list blurb, so a screen that only had a sparse summary
    /// can show a full card once the work page has been read.
    ///
    /// AO3's subscriptions page is the case this exists for: it lists nothing but
    /// each work's title, id and author, so those cards render blank where every
    /// other list shows tags, stats and a summary.
    var asWorkSummary: AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: title,
            authors: authors,
            authorIdentities: authorIdentities,
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
            bookmarks: bookmarks,
            hits: hits,
            seriesTitle: seriesTitle,
            seriesURL: seriesURL,
            seriesPosition: seriesPosition
        )
    }

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
            bookmarks: bookmarks,
            hits: hits
        )
    }

    var summaryValue: AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: title,
            authors: authors,
            authorIdentities: authorIdentities,
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
            bookmarks: bookmarks,
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
nonisolated struct AO3Fandom: Identifiable, Hashable, Codable, Sendable {
    var name: String
    var workCount: Int?
    var id: String {
        name
    }
}

/// An AO3 collection (a named shelf), as listed on a user's collections page. `name`
/// is the URL slug (`/collections/<name>`); `title` is the display name; `byline` is
/// the maintainers line when shown.
nonisolated struct AO3Collection: Identifiable, Hashable, Sendable {
    var name: String
    var title: String
    var byline: String = ""
    var maintainerNames: [String] = []
    var maintainerIdentities: [AO3AuthorIdentity] = []
    var id: String {
        name
    }

    var url: URL {
        URL(string: "https://archiveofourown.org/collections/\(name)")!
    }
}

/// One of AO3's media categories (e.g. "TV Shows") with its featured fandoms,
/// scraped from `/media`. `fandomsURL` points at the category's full fandom index
/// (`/media/<name>/fandoms`), loaded on demand by the fandom detail page.
nonisolated struct AO3MediaCategory: Identifiable, Hashable, Sendable {
    var name: String
    var fandoms: [AO3Fandom]
    var fandomsURL: String = ""
    var id: String {
        name
    }

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
