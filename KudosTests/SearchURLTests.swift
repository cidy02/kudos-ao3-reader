import Foundation
import Testing
@testable import Kudos

/// Pins `AO3Client.searchURL` against AO3's own `/works/search` form.
///
/// Every parameter name and id asserted here was verified against the live site
/// on 2026-08-06 (see `docs/reports/ao3-networking-audit.md`). They are
/// load-bearing constants: a typo in one degrades to an empty result page rather
/// than an error, which is exactly the kind of breakage that survives a release.
struct SearchURLTests {
    /// Query items as `name → [values]`, so assertions don't depend on ordering.
    private func params(_ filters: AO3SearchFilters, page: Int = 1) throws -> [String: [String]] {
        let url = try #require(AO3Client.searchURL(filters: filters, page: page))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return (components.queryItems ?? []).reduce(into: [:]) { result, item in
            result[item.name, default: []].append(item.value ?? "")
        }
    }

    @Test func defaultFiltersSendOnlyPaging() throws {
        let values = try params(AO3SearchFilters())
        #expect(values["page"] == ["1"])
        // Nothing else: an untouched filter must not narrow the search.
        #expect(values.keys.filter { $0.hasPrefix("work_search") }.isEmpty)
    }

    @Test func searchNeverSendsViewAdult() throws {
        // `view_adult` is a work-page parameter — it clears AO3's adult-content
        // interstitial, which listing pages don't have. Measured: an identical
        // search with and without it returns the same works, Explicit included.
        // Sending it is not free, though: it flips AO3's response from
        // `max-age=600, public` to `no-store`, so the response cache in
        // `makeAnonymousSessionConfiguration` can never fire on a search.
        var filters = AO3SearchFilters()
        filters.rating = .explicit
        #expect(try params(filters)["view_adult"] == nil)
        #expect(try params(AO3SearchFilters(), page: 3)["view_adult"] == nil)
    }

    @Test func searchURLPointsAtAO3sWorksSearchEndpoint() throws {
        let url = try #require(AO3Client.searchURL(filters: AO3SearchFilters(), page: 1))
        #expect(url.absoluteString.hasPrefix("https://archiveofourown.org/works/search?"))
    }

    @Test func pageNumberIsSentVerbatim() throws {
        #expect(try params(AO3SearchFilters(), page: 7)["page"] == ["7"])
    }

    @Test func tagFieldsUseAO3sNameParameters() throws {
        var filters = AO3SearchFilters()
        filters.fandom = "Naruto"
        filters.characters = "Sasuke Uchiha"
        filters.relationships = "Naruto/Sasuke"
        filters.additionalTags = "Fluff"
        let values = try params(filters)
        #expect(values["work_search[fandom_names]"] == ["Naruto"])
        #expect(values["work_search[character_names]"] == ["Sasuke Uchiha"])
        #expect(values["work_search[relationship_names]"] == ["Naruto/Sasuke"])
        #expect(values["work_search[freeform_names]"] == ["Fluff"])
    }

    @Test func titleAndCreatorUseTheirOwnFieldsNotTheFreeTextQuery() throws {
        var filters = AO3SearchFilters()
        filters.title = "Chunin Exams"
        filters.creators = "someauthor"
        let values = try params(filters)
        #expect(values["work_search[title]"] == ["Chunin Exams"])
        #expect(values["work_search[creators]"] == ["someauthor"])
        #expect(values["work_search[query]"] == nil)
    }

    @Test func singleRatingUsesTheStructuredFieldWithAO3sID() throws {
        var filters = AO3SearchFilters()
        filters.rating = .explicit
        filters.includeNotRated = false
        let values = try params(filters)
        #expect(values["work_search[rating_ids]"] == ["13"])
        // One rating fits the structured field, so nothing is folded into query.
        #expect(values["work_search[query]"] == nil)
    }

    @Test func multiRatingFallsBackToQuerySyntaxAndDropsTheStructuredField() throws {
        var filters = AO3SearchFilters()
        filters.rating = .teen
        filters.ratingMatch = .orHigher
        filters.includeNotRated = false
        let values = try params(filters)
        // AO3's structured rating select holds exactly one value, so a range has
        // to go through query syntax — and both must never be sent at once.
        #expect(values["work_search[rating_ids]"] == nil)
        let query = try #require(values["work_search[query]"]?.first)
        #expect(query.contains("rating_ids:11"))
        #expect(query.contains("rating_ids:13"))
        #expect(query.contains(" OR "))
    }

    @Test func warningsAndCategoriesUseBracketedMultiValueParameters() throws {
        var filters = AO3SearchFilters()
        filters.warnings = [.violence, .death]
        filters.categories = [.mm, .gen]
        let values = try params(filters)
        #expect(values["work_search[archive_warning_ids][]"]?.sorted() == ["17", "18"])
        #expect(values["work_search[category_ids][]"]?.sorted() == ["21", "23"])
    }

    @Test func exclusionsSplitBetweenTheTagFieldAndQuerySyntax() throws {
        var filters = AO3SearchFilters()
        filters.excludedWarnings = [.chooseNotTo]
        filters.excludedCategories = [.gen]
        filters.excludedFandoms = "Bleach"
        let values = try params(filters)
        // Tags have a structured field; warnings and categories don't, so those
        // two still go through AO3's query syntax as negated id clauses.
        #expect(values["work_search[excluded_tag_names]"] == ["Bleach"])
        let query = try #require(values["work_search[query]"]?.first)
        #expect(query.contains("-archive_warning_ids:14"))
        #expect(query.contains("-category_ids:21"))
        #expect(!query.contains("Bleach"))
    }

    @Test func absoluteDateBoundsUseAO3sISOFormat() throws {
        var filters = AO3SearchFilters()
        var components = DateComponents()
        components.year = 2024; components.month = 1; components.day = 31
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        filters.dateFrom = try #require(calendar.date(from: components))
        components.year = 2025; components.month = 12; components.day = 25
        filters.dateTo = try #require(calendar.date(from: components))

        let values = try params(filters)
        #expect(values["work_search[date_from]"] == ["2024-01-31"])
        #expect(values["work_search[date_to]"] == ["2025-12-25"])
    }

    @Test func absoluteDateBoundsAreOmittedWhenUnset() throws {
        let values = try params(AO3SearchFilters())
        #expect(values["work_search[date_from]"] == nil)
        #expect(values["work_search[date_to]"] == nil)
    }

    @Test func facetedChoicesUseAO3sFlagValues() throws {
        var filters = AO3SearchFilters()
        filters.crossover = .exclude
        filters.completion = .complete
        filters.chapterCount = .singleChapter
        let values = try params(filters)
        #expect(values["work_search[crossover]"] == ["F"])
        #expect(values["work_search[complete]"] == ["T"])
        #expect(values["work_search[single_chapter]"] == ["1"])
    }

    @Test func everyNumericFieldUsesAO3sRangeGrammar() throws {
        var filters = AO3SearchFilters()
        filters.wordsFrom = "1000"
        filters.wordsTo = "5000"
        filters.hitsFrom = "100"
        filters.kudosTo = "50"
        filters.commentsFrom = "5"
        filters.bookmarksFrom = "2"
        filters.bookmarksTo = "20"
        let values = try params(filters)
        #expect(values["work_search[word_count]"] == ["1000-5000"])
        #expect(values["work_search[hits]"] == ["> 100"])
        #expect(values["work_search[kudos_count]"] == ["< 50"])
        #expect(values["work_search[comments_count]"] == ["> 5"])
        #expect(values["work_search[bookmarks_count]"] == ["2-20"])
    }

    @Test func sortSendsColumnAndDirectionTogether() throws {
        var filters = AO3SearchFilters()
        filters.sort = .kudos
        filters.sortDirection = .descending
        var values = try params(filters)
        #expect(values["work_search[sort_column]"] == ["kudos_count"])
        #expect(values["work_search[sort_direction]"] == ["desc"])

        filters.sort = .workTitle
        filters.sortDirection = .ascending
        values = try params(filters)
        #expect(values["work_search[sort_column]"] == ["title_to_sort_on"])
        #expect(values["work_search[sort_direction]"] == ["asc"])
    }

    @Test func relevanceSortSendsNeitherColumnNorDirection() throws {
        var filters = AO3SearchFilters()
        filters.sort = .relevance
        // Direction is meaningless without a column; sending it would pin AO3's
        // relevance score ascending — worst match first.
        filters.sortDirection = .ascending
        let values = try params(filters)
        #expect(values["work_search[sort_column]"] == nil)
        #expect(values["work_search[sort_direction]"] == nil)
    }

    @Test func languageAndUpdatedWindowUseAO3sValues() throws {
        var filters = AO3SearchFilters()
        filters.language = try #require(AO3SearchFilters.Language.allCases.first { $0.id == "en" })
        filters.updated = .week
        let values = try params(filters)
        #expect(values["work_search[language_id]"] == ["en"])
        #expect(values["work_search[revised_at]"] == ["< 1 week ago"])
    }

    /// Every AO3 facet id, not just the handful the behavioural tests happen to
    /// exercise. Before this, 10 of the 17 were asserted nowhere — changing
    /// `Category.multi` from `2246` to a typo left the whole suite green, and
    /// because these raw values are also what `SavedSearch` persists, the error
    /// would have been written into every saved search using that facet.
    ///
    /// Verified against the live `/works/search` form on 2026-08-06.
    @Test func everyFacetIDMatchesAO3sOwnForm() {
        #expect(AO3SearchFilters.Rating.allCases.map(\.ao3ID) == [
            nil,    // .any — no rating filter
            "10",   // General Audiences
            "11",   // Teen And Up Audiences
            "12",   // Mature
            "13",   // Explicit
            "9"     // Not Rated
        ])
        #expect(AO3SearchFilters.Warning.allCases.map(\.ao3ID) == [
            "16",   // No Archive Warnings Apply
            "14",   // Creator Chose Not To Use Archive Warnings
            "17",   // Graphic Depictions Of Violence
            "18",   // Major Character Death
            "19",   // Rape/Non-Con
            "20"    // Underage Sex
        ])
        #expect(AO3SearchFilters.Category.allCases.map(\.ao3ID) == [
            "116",  // F/F
            "22",   // F/M
            "21",   // Gen
            "23",   // M/M
            "2246", // Multi
            "24"    // Other
        ])
    }

    @Test func equalFilterSetsAlwaysProduceTheSameURL() throws {
        // `Set` iteration order isn't stable across equal sets, so emitting
        // warnings/categories in iteration order made the URL depend on how the
        // filter was built. Both `RequestCoalescer` and the response cache key on
        // the URL, so that silently cost de-duplication and cache hits.
        var viaLiteral = AO3SearchFilters()
        viaLiteral.warnings = [.violence, .death, .nonCon]
        viaLiteral.categories = [.mm, .gen, .multi]

        var viaInsertion = AO3SearchFilters()
        for warning in [AO3SearchFilters.Warning.nonCon, .death, .violence] {
            viaInsertion.warnings.insert(warning)
        }
        for category in [AO3SearchFilters.Category.multi, .gen, .mm] {
            viaInsertion.categories.insert(category)
        }

        var viaRemoval = AO3SearchFilters()
        viaRemoval.warnings = Set(AO3SearchFilters.Warning.allCases)
        viaRemoval.warnings.subtract([.noWarnings, .chooseNotTo, .underage])
        viaRemoval.categories = Set(AO3SearchFilters.Category.allCases)
        viaRemoval.categories.subtract([.ff, .fm, .other])

        #expect(viaLiteral == viaInsertion)
        #expect(viaLiteral == viaRemoval)
        let urls = try [viaLiteral, viaInsertion, viaRemoval].map {
            try #require(AO3Client.searchURL(filters: $0, page: 1)).absoluteString
        }
        #expect(Set(urls).count == 1)
    }

    @Test func blankFieldsAreOmittedRatherThanSentEmpty() throws {
        var filters = AO3SearchFilters()
        filters.title = "   "
        filters.fandom = ""
        filters.wordsFrom = "  "
        let values = try params(filters)
        #expect(values["work_search[title]"] == nil)
        #expect(values["work_search[fandom_names]"] == nil)
        #expect(values["work_search[word_count]"] == nil)
    }
}
