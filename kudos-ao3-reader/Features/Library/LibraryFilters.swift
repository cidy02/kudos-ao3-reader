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
    /// `.natural` keeps each section's own order — History and Reading Now are
    /// most-recently-read first, and their headers say so.
    var sort: LibrarySort = .natural

    /// Whether anything beyond the defaults is set — drives the filter button's
    /// "active" icon and the Reset action.
    var hasActiveFilters: Bool {
        !userTags.isEmpty || !fandoms.isEmpty || !characters.isEmpty
            || !relationships.isEmpty || !additionalTags.isEmpty || !excludeTags.isEmpty
            || rating != .any || !warnings.isEmpty || !categories.isEmpty
            || completion != .any || !language.isEmpty
            || !wordsFrom.isLibraryBlank || !wordsTo.isLibraryBlank
            || sort != .natural
    }

    /// Every stored field, in a fixed order — the filter half of the Library
    /// dashboard's cache key (`LibraryView.sectionsRevision`).
    ///
    /// That key used to list a hand-picked subset: no characters,
    /// relationships, additional tags, excluded tags, warnings or categories,
    /// and only the *count* of user tags. Changing one of those while another
    /// filter was already on left the key unchanged, so every carousel kept
    /// showing the previous filter's works and counts. Sets are sorted so two
    /// equal filters give the same key whatever order they were built in; the
    /// two control-character separators cannot occur in a tag name.
    var revisionKey: String {
        func joined(_ names: Set<String>) -> String {
            names.sorted().joined(separator: "\u{1F}")
        }
        return [
            joined(userTags),
            joined(fandoms),
            joined(characters),
            joined(relationships),
            joined(additionalTags),
            joined(excludeTags),
            rating.rawValue,
            joined(Set(warnings.map(\.rawValue))),
            joined(Set(categories.map(\.rawValue))),
            completion.rawValue,
            language,
            wordsFrom,
            wordsTo,
            sort.rawValue
        ].joined(separator: "\u{1E}")
    }

    // MARK: Summary

    /// The active filters as chips, for the rail the redesign puts under a page
    /// header (spec 1k, 1ad, 1c/1d, 1ah, 1aj).
    ///
    /// Deliberately mirrors `AO3SearchFilters.summaryLabels(excluding:includesSort:)`
    /// — same `SummaryLabel` type, same "only non-default settings appear" rule,
    /// same tag glyphs, sort last — so a Library rail and a Search rail read as
    /// the same control rather than as two lists that happen to look alike.
    ///
    /// Sort is last and unconditional where it applies, for the reason the AO3
    /// version gives: there is always an order in effect, so it is the one label
    /// that is never noise, and it is the setting people most often forget they
    /// set.
    func summaryLabels(
        includesSort: Bool = true, includesInProgress: Bool = true
    ) -> [AO3SearchFilters.SummaryLabel] {
        var labels: [AO3SearchFilters.SummaryLabel] = []

        func add(_ text: String, _ symbol: String? = nil) {
            labels.append(AO3SearchFilters.SummaryLabel(text: text, symbol: symbol))
        }
        func addTags(_ names: Set<String>, _ field: AO3TagSearch.Field) {
            for name in names.sorted() { add(name, field.symbol) }
        }

        // The user's own tags are not an AO3 tag category, so they take a
        // bookmark glyph of their own rather than borrowing `.freeform`'s —
        // spec 1q is explicit that local User Tags stay "visually distinct" from
        // AO3's.
        for name in userTags.sorted() { add(name, "bookmark") }
        addTags(fandoms, .fandom)
        addTags(relationships, .relationship)
        addTags(characters, .character)
        addTags(additionalTags, .freeform)
        for name in excludeTags.sorted() { add("−\(name)", AO3TagSearch.Field.freeform.symbol) }

        if rating != .any { add(rating.title) }
        for warning in AO3SearchFilters.Warning.allCases.filter(warnings.contains) {
            add(warning.title, AO3TagSearch.Field.warning.symbol)
        }
        for category in AO3SearchFilters.Category.allCases.filter(categories.contains) {
            add(category.title)
        }
        if completion == .complete || (completion == .inProgress && includesInProgress) {
            add(completion.title)
        }
        if !language.isEmpty { add(language) }

        let lowerWordBound = wordsFrom.trimmingCharacters(in: .whitespaces)
        let upperWordBound = wordsTo.trimmingCharacters(in: .whitespaces)
        switch (lowerWordBound.isEmpty, upperWordBound.isEmpty) {
        case (false, false): add("Words \(lowerWordBound)–\(upperWordBound)")
        case (false, true): add(Self.minimumWordsLabel(lowerWordBound))
        case (true, false): add("Words ≤ \(upperWordBound)")
        case (true, true): break
        }

        if includesSort, sort != .natural { add("Sort: \(sort.title)") }
        return labels
    }

    // MARK: Quick pills

    /// 1ad's "All N" and "WIP N": what each pill would show with every other
    /// filter held. The pills *are* the completion filter (All = any, WIP = in
    /// progress — AO3's posted status, as `FavoriteQuickFilter.wip`), so they
    /// narrow alongside the panel and the collision card can drop them like any
    /// other filter. 1ad's "Offline" pill is not built: Reading Now already
    /// requires the EPUB, so it would always equal All.
    func completionPillCounts(in works: [SavedWork]) -> (all: Int, wip: Int) {
        var all = self
        all.completion = .any
        var wip = self
        wip.completion = .inProgress
        return (works.filter(all.matches).count, works.filter(wip.matches).count)
    }

    // MARK: Collision drops

    /// One active filter removed, with how many works would remain. Sort is not
    /// a narrowing predicate, so it is never a candidate. `id` names the facet
    /// too, so a user tag and a language both called "English" stay two rows.
    struct FilterDrop: Equatable, Identifiable {
        var id: String
        var filterLabel: String
        var remainingCount: Int
        var remainingFilters: LibraryFilters
    }

    /// Evaluates the predicate set minus one member over `works`. Cheap over an
    /// in-memory list; the empty state uses the counts so a colliding set of
    /// filters is actionable rather than apologetic.
    func droppingEachActiveFilter(from works: [SavedWork]) -> [FilterDrop] {
        activeMembers.map { member in
            var remaining = self
            member.clear(&remaining)
            return FilterDrop(
                id: member.id,
                filterLabel: member.label,
                remainingCount: works.filter(remaining.matches).count,
                remainingFilters: remaining
            )
        }
    }

    /// The smallest set of active filters that already matches nothing over
    /// `works` (1ay.3): one filter no work passes on its own, else the first
    /// pair with no work in common, else every active filter. Each member is
    /// judged alone — `self` with every *other* member cleared — so the pair
    /// named really is the collision, not a bystander. O(k² · n) for k filters;
    /// k is a handful of chips.
    func collidingFilterLabels(in works: [SavedWork]) -> [String] {
        let members = activeMembers
        let alone: [LibraryFilters] = members.indices.map { index in
            var only = self
            for other in members.indices where other != index { members[other].clear(&only) }
            return only
        }
        for index in members.indices where !works.contains(where: alone[index].matches) {
            return [members[index].label]
        }
        for first in members.indices {
            for second in members.indices where second > first {
                let overlap = works.contains { alone[first].matches($0) && alone[second].matches($0) }
                if !overlap { return [members[first].label, members[second].label] }
            }
        }
        return members.map(\.label)
    }

    private struct Member {
        /// "<facet>:<value>", unique among the active filters.
        var id: String
        var label: String
        /// Added to `label` only when another active filter reads the same.
        var facet: String
        var clear: (inout LibraryFilters) -> Void
    }

    /// Every active narrowing filter, labelled as `summaryLabels` labels it,
    /// with how to clear just that one. Sort is not a narrowing predicate, so
    /// it is never a member. Two members that would read the same (a user tag
    /// and a language both "English") are told apart by their facet.
    private var activeMembers: [Member] {
        var members: [Member] = []
        func add(
            _ facet: String, _ key: String, _ label: String,
            _ clear: @escaping (inout LibraryFilters) -> Void
        ) {
            members.append(Member(id: "\(facet):\(key)", label: label, facet: facet, clear: clear))
        }
        for name in userTags.sorted() { add("your tag", name, name) { $0.userTags.remove(name) } }
        for name in fandoms.sorted() { add("fandom", name, name) { $0.fandoms.remove(name) } }
        for name in characters.sorted() { add("character", name, name) { $0.characters.remove(name) } }
        for name in relationships.sorted() { add("relationship", name, name) { $0.relationships.remove(name) } }
        for name in additionalTags.sorted() { add("tag", name, name) { $0.additionalTags.remove(name) } }
        for name in excludeTags.sorted() { add("excluded tag", name, "−\(name)") { $0.excludeTags.remove(name) } }
        if rating != .any { add("rating", rating.rawValue, rating.title) { $0.rating = .any } }
        for warning in AO3SearchFilters.Warning.allCases where warnings.contains(warning) {
            add("warning", warning.rawValue, warning.title) { $0.warnings.remove(warning) }
        }
        for category in AO3SearchFilters.Category.allCases where categories.contains(category) {
            add("category", category.rawValue, category.title) { $0.categories.remove(category) }
        }
        if completion != .any { add("status", completion.rawValue, completion.title) { $0.completion = .any } }
        if !language.isEmpty { add("language", language, language) { $0.language = "" } }
        let lowerWordBound = wordsFrom.trimmingCharacters(in: .whitespaces)
        let upperWordBound = wordsTo.trimmingCharacters(in: .whitespaces)
        let wordLabel: String? = switch (lowerWordBound.isEmpty, upperWordBound.isEmpty) {
        case (false, false): "Words \(lowerWordBound)–\(upperWordBound)"
        case (false, true): Self.minimumWordsLabel(lowerWordBound)
        case (true, false): "Words ≤ \(upperWordBound)"
        case (true, true): nil
        }
        if let wordLabel {
            add("words", wordLabel, wordLabel) {
                $0.wordsFrom = ""
                $0.wordsTo = ""
            }
        }
        let repeated = Dictionary(grouping: members, by: \.label).filter { $0.value.count > 1 }.keys
        return members.map { member in
            var member = member
            if repeated.contains(member.label) { member.label += " (\(member.facet))" }
            return member
        }
    }

    // MARK: Applying

    /// Filters and sorts a list of works by the current settings.
    func apply(to works: [SavedWork]) -> [SavedWork] {
        let kept = works.filter(matches)
        return sort == .natural ? kept : kept.sorted(by: isOrderedBefore)
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
        // By family: "Doctor Who" and "Doctor Who (2005)" are one fandom here,
        // as Browse (1g) and every kicker already treat them.
        if !fandoms.isEmpty,
           !Set(fandoms.map(FandomDisplayName.bareTitle))
            .isSubset(of: Set(tagSet(work.workFandoms, fallback: work.workTags).map(FandomDisplayName.bareTitle))) {
            return false
        }
        if !characters.isEmpty,
           !characters.isSubset(of: tagSet(work.workCharacters, fallback: work.workTags)) { return false }
        if !relationships.isEmpty,
           !relationships.isSubset(of: tagSet(work.workRelationships, fallback: work.workTags)) { return false }
        if !additionalTags.isEmpty,
           !additionalTags.isSubset(of: tagSet(work.workFreeforms, fallback: work.workTags)) { return false }
        if !excludeTags.isEmpty, !excludeTags.isDisjoint(with: Set(work.workTags)) { return false }

        if rating != .any, !rating.matchesRatingText(work.rating) { return false }

        if !warnings.isEmpty {
            let present = FilterTextMatching.lowercased(work.workWarnings.isEmpty ? work.workTags : work.workWarnings)
            for warning in warnings where !warning.matchNames.contains(where: { present.contains($0.lowercased()) }) {
                return false
            }
        }

        if !categories.isEmpty {
            let present = FilterTextMatching.lowercased(work.workCategories.isEmpty ? work.workTags : work.workCategories)
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
            if let from = FilterTextMatching.bound(wordsFrom), work.wordCount < from { return false }
            if let to = FilterTextMatching.bound(wordsTo), work.wordCount > to { return false }
        }

        return true
    }

    private func isOrderedBefore(_ first: SavedWork, _ second: SavedWork) -> Bool {
        switch sort {
        case .natural: false
        case .dateAdded: first.dateAdded > second.dateAdded
        case .dateDownloaded:
            (first.downloadedAt ?? first.dateAdded) > (second.downloadedAt ?? second.dateAdded)
        case .lastRead:
            // Most recently read first; never-read works last.
            switch (first.lastReadDate, second.lastReadDate) {
            case let (lhs?, rhs?): lhs > rhs
            case (_?, nil): true
            default: false
            }
        case .title: first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
        case .author: first.author.localizedCaseInsensitiveCompare(second.author) == .orderedAscending
        case .wordCount: first.wordCount > second.wordCount
        case .kudos: first.kudos > second.kudos
        }
    }

    // MARK: Helpers

    /// The set to match a categorized tag field against: the work's own categorized
    /// list, or its flat tag list when the work hasn't been refreshed from AO3 yet.
    private func tagSet(_ categorized: [String], fallback: [String]) -> Set<String> {
        Set(categorized.isEmpty ? fallback : categorized)
    }
}

/// The Library's sort options, the same on Android (`LibrarySort.kt`). Last Read
/// and Kudos are the owner's additions (2026-10-03): the kudos count is kept on
/// each saved work, refreshed with its metadata.
enum LibrarySort: String, CaseIterable, Identifiable, Equatable {
    case natural, dateAdded, dateDownloaded, lastRead, title, author, wordCount, kudos
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .natural: "Default"
        case .dateAdded: "Date Added"
        case .dateDownloaded: "Date Downloaded"
        case .lastRead: "Last Read"
        case .title: "Title"
        case .author: "Author"
        case .wordCount: "Word Count"
        case .kudos: "Kudos"
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

extension LibraryFilters {
    /// 1ay's "50k+ words": a lower bound reads as a size, compact like every
    /// other count on a chip. A bound that is not a number stays as typed.
    static func minimumWordsLabel(_ bound: String) -> String {
        guard let value = Int(bound) else { return "Words ≥ \(bound)" }
        return "\(value.compactCount)+ words"
    }
}
