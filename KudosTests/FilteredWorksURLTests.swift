import Foundation
import Testing
@testable import Kudos

/// Pins the tag drill-down's endpoint — the URL built when a tag tapped inside a
/// work is filtered.
///
/// That screen used to sift the fetched page in memory. It now asks AO3, because
/// `/tags/<t>/works` honours every `work_search[...]` parameter `/works/search`
/// does (23 of 23 measured live — `docs/reports/filter-parity-2026-08-07.md`).
/// Unlike `fandomWorksURL`, the base here is *whatever URL was tapped*, so the
/// merge has to survive a URL that already carries query items.
struct FilteredWorksURLTests {
    private func url(
        _ string: String,
        _ filters: AO3SearchFilters = AO3SearchFilters(),
        page: Int = 1
    ) throws -> URL {
        AO3Client.filteredWorksURL(try #require(URL(string: string)), filters: filters, page: page)
    }

    private func params(_ url: URL) throws -> [String: [String]] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return (components.queryItems ?? []).reduce(into: [:]) { result, item in
            result[item.name, default: []].append(item.value ?? "")
        }
    }

    private let tagURL = "https://archiveofourown.org/tags/Fluff/works"

    @Test func theTagsOwnPathIsUntouched() throws {
        let url = try url(tagURL)
        #expect(url.path == "/tags/Fluff/works")
        #expect(url.host == "archiveofourown.org")
    }

    @Test func filtersReachAO3RatherThanBeingAppliedHere() throws {
        var filters = AO3SearchFilters()
        filters.rating = .explicit
        // Explicit *plus* Not Rated is two ratings, and AO3's structured field
        // holds one — so that combination travels in `query` instead. Turning it
        // off is what puts the rating in `rating_ids`, and both are asserted below
        // rather than picking whichever one made the test pass.
        filters.includeNotRated = false
        filters.completion = .complete
        filters.kudosFrom = "500"
        filters.sort = .kudos

        let values = try params(try url(tagURL, filters))
        #expect(values["work_search[rating_ids]"] == ["13"])
        #expect(values["work_search[complete]"] == ["T"])
        #expect(values["work_search[kudos_count]"] == ["> 500"])
        #expect(values["work_search[sort_column]"] == ["kudos_count"])
    }

    /// The other half of the rating contract, on this path too: with Not Rated
    /// left on, the rating is a `query` clause and `rating_ids` is absent.
    @Test func aTwoRatingSelectionTravelsInTheQueryInstead() throws {
        var filters = AO3SearchFilters()
        filters.rating = .explicit
        let values = try params(try url(tagURL, filters))
        #expect(values["work_search[rating_ids]"] == nil)
        #expect(values["work_search[query]"]?.first?.contains("rating_ids") == true)
    }

    /// The whole reason this needs its own builder: the tapped URL is arbitrary.
    @Test func aTappedURLsOwnParametersSurvive() throws {
        let values = try params(try url("\(tagURL)?utf8=%E2%9C%93&commit=Sort%20and%20Filter"))
        #expect(values["utf8"] == ["✓"])
        #expect(values["commit"] == ["Sort and Filter"])
    }

    /// A tag link copied out of AO3's own sorted listing already carries
    /// `work_search[...]`. Left in place, the panel's value would be *appended*
    /// beside it and AO3 would be sent two conflicting sorts for one request.
    @Test func theTappedURLsOwnFilterParametersAreReplacedNotDuplicated() throws {
        var filters = AO3SearchFilters()
        filters.sort = .kudos
        let stale = "\(tagURL)?work_search%5Bsort_column%5D=word_count&work_search%5Bcomplete%5D=F"

        let values = try params(try url(stale, filters))
        #expect(values["work_search[sort_column]"] == ["kudos_count"])
        // The stale `complete=F` is gone rather than surviving as a filter the
        // panel never showed and the reader could not clear.
        #expect(values["work_search[complete]"] == nil)
    }

    @Test func pageIsTheOneTheCallerAskedFor() throws {
        #expect(try params(try url("\(tagURL)?page=9", page: 2))["page"] == ["2"])
    }

    /// Unlike `/works/search`, keeping `view_adult` here is free — `/tags/<t>/works`
    /// answered `no-cache, public` with or without it, so it costs no cache hit.
    /// The unfiltered `worksPage(at:page:)` sends it for the same reason.
    @Test func viewAdultIsSentExactlyOnce() throws {
        #expect(try params(try url("\(tagURL)?view_adult=true"))["view_adult"] == ["true"])
    }
}
