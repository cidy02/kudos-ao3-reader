import Foundation
import Testing
@testable import Kudos

/// The merged 1v sheet must ask AO3 for the same parameters the sort sheet
/// asked for. Refine facets ride in the same sheet and stay off the URL —
/// they narrow blurbs already parsed. A merge that appended
/// `AO3Client.workSearchQueryItems` would change this index.
struct WorksSortFilterSheetTests {
    private func loadedFilters() -> AO3SearchFilters {
        var filters = AO3SearchFilters()
        filters.rating = .teen
        filters.warnings = [.violence]
        filters.crossover = .exclude
        filters.completion = .complete
        filters.chapterCount = .singleChapter
        filters.wordsFrom = "1000"
        filters.wordsTo = "5000"
        filters.fandom = "Naruto"
        filters.language = AO3SearchFilters.Language(id: "en")
        filters.sort = .bookmarks
        filters.sortDirection = .ascending
        return filters
    }

    private func route() throws -> AO3AuthorRoute {
        try #require(AO3AuthorRoute(username: "tester"))
    }

    private func params(_ url: URL) throws -> [String: [String]] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return (components.queryItems ?? []).reduce(into: [:]) { result, item in
            result[item.name, default: []].append(item.value ?? "")
        }
    }

    /// The URL the two controls produced before they shared a sheet: the page
    /// plus `sort.queryItems` only. Deliberately not `appending` /
    /// `indexQueryItems`, so a merge that starts sending refine facets cannot
    /// satisfy this by construction.
    private func preMergeURL(
        _ content: AO3AuthorRoute.Content = .works,
        page: Int = 1,
        sort: AO3WorksSort
    ) throws -> URL {
        let plain = try route().contentURL(content, page: page)
        let items = sort.queryItems
        guard !items.isEmpty,
              var components = URLComponents(url: plain, resolvingAgainstBaseURL: false)
        else { return plain }
        components.queryItems = (components.queryItems ?? []) + items
        return try #require(components.url)
    }

    @Test func fieldsHintCountsTheColumns() {
        #expect(AO3WorksSort.fieldsHint == "9 fields")
        #expect(AO3WorksSort.fieldsHint == "\(AO3WorksSort.allColumns.count) fields")
    }

    @Test func defaultSortWithEveryRefineFacetStaysThePlainPage() throws {
        let filters = loadedFilters()
        let url = try route().contentURL(.works, sort: .default, filters: filters)
        #expect(url == (try preMergeURL(sort: .default)))
        #expect(url.absoluteString == "https://archiveofourown.org/users/tester/works")
        let values = try params(url)
        #expect(values.keys.filter { $0.hasPrefix("work_search") }.isEmpty)
    }

    @Test func kudosAndIncompleteKeepOnlyThoseParameters() throws {
        var sort = AO3WorksSort.default
        sort.select(.kudos)
        sort.completion = .incomplete
        let filters = loadedFilters()
        let url = try route().contentURL(.works, page: 3, sort: sort, filters: filters)
        #expect(url == (try preMergeURL(page: 3, sort: sort)))
        let values = try params(url)
        #expect(values["page"] == ["3"])
        #expect(values["work_search[sort_column]"] == ["kudos_count"])
        #expect(values["work_search[complete]"] == ["F"])
        // Descending is kudos' own default, so it is still not restated.
        #expect(values["work_search[sort_direction]"] == nil)
        #expect(values["work_search[rating_ids]"] == nil)
        #expect(values["work_search[archive_warning_ids][]"] == nil)
        #expect(values["work_search[crossover]"] == nil)
        #expect(values["work_search[word_count]"] == nil)
        #expect(values["work_search[fandom_names]"] == nil)
        #expect(values["work_search[language_id]"] == nil)
        #expect(values["work_search[single_chapter]"] == nil)
        // The filter sheet's own sort must not replace, or join, the works sort.
        #expect(values["work_search[sort_column]"] != ["bookmarks_count"])
    }

    /// The refine panel's completion and the sort's completion share a name
    /// and not a request. Only the sort's value is posted.
    @Test func localCompletionDoesNotReplaceTheSortsCompletion() throws {
        var sort = AO3WorksSort.default
        sort.select(.title)
        sort.direction = .descending
        sort.completion = .incomplete
        var filters = loadedFilters()
        filters.completion = .complete
        let url = try route().contentURL(.collectedWorks, sort: sort, filters: filters)
        #expect(url == (try preMergeURL(.collectedWorks, sort: sort)))
        let values = try params(url)
        #expect(values["work_search[sort_column]"] == ["title_to_sort_on"])
        #expect(values["work_search[sort_direction]"] == ["desc"])
        #expect(values["work_search[complete]"] == ["F"])
    }

    @Test func anInvertedDefaultColumnSendsOnlyTheDirection() throws {
        var sort = AO3WorksSort.default
        sort.direction = .ascending
        sort.completion = .complete
        let url = try route().contentURL(.works, sort: sort, filters: loadedFilters())
        #expect(url == (try preMergeURL(sort: sort)))
        let values = try params(url)
        #expect(values["work_search[sort_column]"] == nil)
        #expect(values["work_search[sort_direction]"] == ["asc"])
        #expect(values["work_search[complete]"] == ["T"])
    }

    @Test func aFandomURLGainsTheSortAndNothingFromTheFacets() throws {
        var sort = AO3WorksSort.default
        sort.select(.hits)
        let base = try #require(
            URL(string: "https://archiveofourown.org/tags/Naruto/works?page=2")
        )
        let url = AO3WorksSort.appending(sort, filters: loadedFilters(), to: base)
        var components = try #require(URLComponents(url: base, resolvingAgainstBaseURL: false))
        components.queryItems = (components.queryItems ?? []) + sort.queryItems
        #expect(url == components.url)
        let values = try params(url)
        #expect(values["page"] == ["2"])
        #expect(values["work_search[sort_column]"] == ["hits"])
        #expect(values["work_search[fandom_names]"] == nil)
        #expect(values["work_search[language_id]"] == nil)
    }

    @Test func indexesThatIgnoreWorkSearchStillIgnoreTheMergedSheet() throws {
        var sort = AO3WorksSort.default
        sort.select(.hits)
        sort.completion = .complete
        let author = try route()
        for content in [AO3AuthorRoute.Content.bookmarks, .series, .gifts] {
            let merged = author.contentURL(content, sort: sort, filters: loadedFilters())
            #expect(merged == author.contentURL(content))
        }
    }
}
