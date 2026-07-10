import Foundation

/// In-memory filter + sort state for the Library, at parity with the Search
/// filters but applied to the user's saved works rather than an AO3 query. The
/// facet enums (Rating, Warning, Category, Completion, Language) are shared with
/// `AO3SearchFilters` so the two filter UIs offer identical options.
struct LibraryFilters: Equatable {
    /// The user's own organizational tags (kept from the original Library filter).
    var userTags: Set<String> = []
    // AO3 work tags, by category. Matched against the work's categorized tags,
    // falling back to its flat tag list for works not yet refreshed from AO3.
    var fandoms: Set<String> = []
    var characters: Set<String> = []
    var relationships: Set<String> = []
    var additionalTags: Set<String> = []
    var excludeTags: Set<String> = []
    // Faceted filters (shared enums with Search).
    var rating: AO3SearchFilters.Rating = .any
    var warnings: Set<AO3SearchFilters.Warning> = []
    var categories: Set<AO3SearchFilters.Category> = []
    var completion: AO3SearchFilters.Completion = .any
    /// A language display name (e.g. "English"); empty means any.
    var language: String = ""
    var wordsFrom: String = ""
    var wordsTo: String = ""
    var sort: LibrarySort = .dateAdded

    /// Whether anything beyond the defaults is set — drives the filter button's
    /// "active" icon and the Reset action.
    var hasActiveFilters: Bool {
        !userTags.isEmpty || !fandoms.isEmpty || !characters.isEmpty
            || !relationships.isEmpty || !additionalTags.isEmpty || !excludeTags.isEmpty
            || rating != .any || !warnings.isEmpty || !categories.isEmpty
            || completion != .any || !language.isEmpty
            || !wordsFrom.isLibraryBlank || !wordsTo.isLibraryBlank
            || sort != .dateAdded
    }

    // MARK: Applying

    /// Filters and sorts a list of works by the current settings.
    func apply(to works: [SavedWork]) -> [SavedWork] {
        works.filter(matches).sorted(by: isOrderedBefore)
    }

    // Lint: multi-facet predicate reads safest as one guard sequence.
    /// Whether a single work passes every active filter (AND across fields; AND
    /// within a multi-select field, matching AO3's "include all" tag behavior).
    /// Each tag facet builds its per-work `Set` only when that facet is actually
    /// set — with no active filters this is pure guard fall-through, so applying
    /// default filters over a large library costs no per-work set construction
    /// (and no faulting of the `tags` relationship).
    func matches(_ work: SavedWork) -> Bool { // swiftlint:disable:this cyclomatic_complexity
        if !userTags.isEmpty, !userTags.isSubset(of: Set(work.tags.map(\.name))) { return false }
        if !fandoms.isEmpty,
           !fandoms.isSubset(of: tagSet(work.workFandoms, fallback: work.workTags)) { return false }
        if !characters.isEmpty,
           !characters.isSubset(of: tagSet(work.workCharacters, fallback: work.workTags)) { return false }
        if !relationships.isEmpty,
           !relationships.isSubset(of: tagSet(work.workRelationships, fallback: work.workTags)) { return false }
        if !additionalTags.isEmpty,
           !additionalTags.isSubset(of: tagSet(work.workFreeforms, fallback: work.workTags)) { return false }
        if !excludeTags.isEmpty, !excludeTags.isDisjoint(with: Set(work.workTags)) { return false }

        if rating != .any, !rating.matchesRatingText(work.rating) { return false }

        if !warnings.isEmpty {
            let present = lowercased(work.workWarnings.isEmpty ? work.workTags : work.workWarnings)
            for warning in warnings where !warning.matchNames.contains(where: { present.contains($0.lowercased()) }) {
                return false
            }
        }

        if !categories.isEmpty {
            let present = lowercased(work.workCategories.isEmpty ? work.workTags : work.workCategories)
            for category in categories where !present.contains(category.title.lowercased()) {
                return false
            }
        }

        switch completion {
        case .any: break
        case .complete: if !work.isComplete { return false }
        case .inProgress: if work.isComplete { return false }
        }

        if !language.isEmpty,
           work.language.caseInsensitiveCompare(language) != .orderedSame { return false }

        // Word-count bounds only apply to works whose count is known (> 0); works
        // not yet refreshed from AO3 keep an unknown count and aren't hidden.
        if work.wordCount > 0 {
            if let from = boundValue(wordsFrom), work.wordCount < from { return false }
            if let to = boundValue(wordsTo), work.wordCount > to { return false }
        }

        return true
    }

    private func isOrderedBefore(_ first: SavedWork, _ second: SavedWork) -> Bool {
        switch sort {
        case .dateAdded: first.dateAdded > second.dateAdded
        case .title: first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
        case .author: first.author.localizedCaseInsensitiveCompare(second.author) == .orderedAscending
        case .wordCount: first.wordCount > second.wordCount
        }
    }

    // MARK: Helpers

    /// The set to match a categorized tag field against: the work's own categorized
    /// list, or its flat tag list when the work hasn't been refreshed from AO3 yet.
    private func tagSet(_ categorized: [String], fallback: [String]) -> Set<String> {
        Set(categorized.isEmpty ? fallback : categorized)
    }

    private func lowercased(_ values: [String]) -> Set<String> {
        Set(values.map { $0.lowercased() })
    }

    private func boundValue(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }
}

/// The Library's sort options — limited to fields stored locally for saved works
/// (AO3's kudos/hits/comments counts aren't kept, so they aren't offered).
enum LibrarySort: String, CaseIterable, Identifiable, Equatable {
    case dateAdded, title, author, wordCount
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .dateAdded: "Date Added"
        case .title: "Title"
        case .author: "Author"
        case .wordCount: "Word Count"
        }
    }
}

// MARK: - Shared-enum matching against locally stored strings

extension AO3SearchFilters.Rating {
    /// Whether a stored rating string (e.g. "Teen And Up Audiences") matches this
    /// rating. Lenient because EPUB and AO3 spellings differ slightly.
    func matchesRatingText(_ text: String) -> Bool {
        let ratingText = text.lowercased()
        switch self {
        case .any: return true
        case .general: return ratingText.contains("general")
        case .teen: return ratingText.contains("teen")
        case .mature: return ratingText.contains("mature")
        case .explicit: return ratingText.contains("explicit")
        case .notRated: return ratingText.contains("not rated")
        }
    }
}

extension AO3SearchFilters.Warning {
    /// The names AO3 uses for this warning across EPUB subjects and work pages
    /// (only "Underage" differs from the canonical title).
    var matchNames: [String] {
        switch self {
        case .underage: ["Underage Sex", "Underage"]
        default: [title]
        }
    }
}

private extension String {
    var isLibraryBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
