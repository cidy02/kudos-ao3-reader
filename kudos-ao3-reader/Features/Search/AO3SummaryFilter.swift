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
            && (rating == .any || rating.matchesRatingText(work.rating))
            && warningsMatch(work)
            && categoriesMatch(work)
            && completionMatches(work)
            && languageMatches(work)
            && wordCountMatches(work)
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
