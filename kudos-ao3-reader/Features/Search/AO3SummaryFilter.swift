import Foundation

/// Client-side refine for already-loaded AO3 work summaries. Pages backed by a fixed
/// AO3 list — a user's bookmarks / history / subscriptions / works, a collection, or a
/// single tag's works — can't be re-run through AO3's search endpoint, so the same
/// `AO3SearchFilters` facets are applied *in place* to the works on screen instead.
/// This keeps the filter contextual to the page you're on rather than firing a fresh
/// website-wide search. Mirrors `LibraryFilters.matches` (the local-works equivalent)
/// and reuses its shared facet-matching helpers (`Rating.matchesRatingText`,
/// `Warning.matchNames`).
extension AO3SearchFilters {
    /// The loaded summaries narrowed to those passing every active facet. Order is
    /// preserved (AO3's own ordering for the page); refine doesn't re-sort.
    func apply(to summaries: [AO3WorkSummary]) -> [AO3WorkSummary] {
        summaries.filter(matchesSummary)
    }

    /// Whether one summary passes every active filter (AND across fields; AND within a
    /// multi-value field, matching AO3's "include all" tag behavior). Crossover and
    /// Updated aren't checked — they can't be derived from a blurb client-side, so the
    /// refine panel hides them.
    func matchesSummary(_ work: AO3WorkSummary) -> Bool {
        tagsMatch(work)
            && ratingMatches(work)
            && warningsMatch(work)
            && categoriesMatch(work)
            && completionMatches(work)
            && chapterCountMatches(work)
            && languageMatches(work)
            && wordCountMatches(work)
    }

    /// Rating, its match mode, and Not Rated — all three of which artboard 1au
    /// draws on this very panel, and none of which used to be read here: the
    /// rating clause was a bare `matchesRatingText`, so "Rating+" narrowed
    /// exactly as much as "Exact" and the Not Rated toggle did nothing at all.
    ///
    /// A blurb does carry enough to answer them. The rating text names a rung on
    /// `Rating.severityRank`, so "or higher" / "or lower" are comparisons; and
    /// "Not Rated" is a rating AO3 prints by name, so it can be kept or dropped
    /// rather than guessed at.
    private func ratingMatches(_ work: AO3WorkSummary) -> Bool {
        guard rating != .any else { return true }
        // Handled before the ladder: Not Rated is not a rung on it, so it is in or
        // out by its own toggle whatever the selected rating and match mode are.
        if Rating.notRated.matchesRatingText(work.rating) { return includeNotRated }
        guard let wanted = rating.severityRank,
              let found = Rating.severityRank(ofRatingText: work.rating)
        else { return false }
        switch ratingMatch {
        case .exact: return found == wanted
        case .orHigher: return found >= wanted
        case .orLower: return found <= wanted
        }
    }

    /// AO3 counts a work as single-chapter when it is finished at one chapter, so
    /// a blurb reading "1/?" is a one-chapter WIP rather than a match — the author
    /// has said more is coming. Anything the parser could not read stays visible.
    private func chapterCountMatches(_ work: AO3WorkSummary) -> Bool {
        guard chapterCount == .singleChapter else { return true }
        let parts = work.chapters.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return true }
        let posted = parts[0].trimmingCharacters(in: .whitespaces)
        let total = parts[1].trimmingCharacters(in: .whitespaces)
        return posted == "1" && total == "1"
    }

    /// Include tags must all be present (AND); no excluded tag may appear.
    private func tagsMatch(_ work: AO3WorkSummary) -> Bool {
        guard includeTags(fandom).allSatisfy({ contains($0, in: work.fandoms) }),
              includeTags(characters).allSatisfy({ contains($0, in: work.characters) }),
              includeTags(relationships).allSatisfy({ contains($0, in: work.relationships) }),
              includeTags(additionalTags).allSatisfy({ contains($0, in: work.tags) })
        else { return false }

        let everyTag = work.fandoms + work.characters + work.relationships + work.tags + work.warnings
        let excluded = includeTags(excludedFandoms) + includeTags(excludedCharacters)
            + includeTags(excludedRelationships) + includeTags(excludedAdditionalTags)
        return !excluded.contains { contains($0, in: everyTag) }
    }

    private func warningsMatch(_ work: AO3WorkSummary) -> Bool {
        guard !warnings.isEmpty || !excludedWarnings.isEmpty else { return true }
        let present = FilterTextMatching.lowercased(work.warnings)
        func hasWarning(_ warning: AO3SearchFilters.Warning) -> Bool {
            warning.matchNames.contains { present.contains($0.lowercased()) }
        }
        return warnings.allSatisfy(hasWarning) && !excludedWarnings.contains(where: hasWarning)
    }

    private func categoriesMatch(_ work: AO3WorkSummary) -> Bool {
        guard !categories.isEmpty || !excludedCategories.isEmpty else { return true }
        let present = FilterTextMatching.lowercased(work.categories)
        func hasCategory(_ category: AO3SearchFilters.Category) -> Bool {
            present.contains(category.title.lowercased())
        }
        return categories.allSatisfy(hasCategory) && !excludedCategories.contains(where: hasCategory)
    }

    private func completionMatches(_ work: AO3WorkSummary) -> Bool {
        switch completion {
        case .any: true
        case .complete: work.isComplete == true
        case .inProgress: work.isComplete == false
        }
    }

    private func languageMatches(_ work: AO3WorkSummary) -> Bool {
        guard language != .any, !language.title.isEmpty else { return true }
        return work.language.caseInsensitiveCompare(language.title) == .orderedSame
    }

    /// Word-count bounds only apply when AO3 gave a count; works without one aren't hidden.
    private func wordCountMatches(_ work: AO3WorkSummary) -> Bool {
        guard let words = work.words else { return true }
        if let from = FilterTextMatching.bound(wordsFrom), words < from { return false }
        if let to = FilterTextMatching.bound(wordsTo), words > to { return false }
        return true
    }

    /// Splits a comma-separated include/exclude field into trimmed, non-empty values.
    private func includeTags(_ field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Lenient tag membership: case-insensitive exact match, falling back to a contains
    /// check so a partially-typed tag still narrows the page.
    private func contains(_ value: String, in tags: [String]) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            || tags.contains { $0.localizedCaseInsensitiveContains(value) }
    }

}
