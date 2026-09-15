import Foundation
import Testing
@testable import Kudos

/// 1v's sort, pinned to otwarchive's `WorkSearchForm`. These are not opinions —
/// each expectation names the rule in that file it encodes, so a future change
/// has to disagree with AO3 out loud rather than by accident.
struct AO3WorksSortTests {
    /// `sort_options` returns `SORT_OPTIONS[1..-1]` for a faceted or collected
    /// index, dropping "Best Match". A user's works page is faceted, and 1v's
    /// own note says "the nine sort fields".
    @Test func offersNineColumnsAndNotBestMatch() {
        #expect(AO3WorksSort.allColumns.count == 9)
        #expect(!AO3WorksSort.allColumns.map(\.rawValue).contains("_score"))
        #expect(AO3WorksSort.allColumns.map(\.rawValue) == [
            "authors_to_sort_on", "title_to_sort_on", "created_at", "revised_at",
            "word_count", "hits", "kudos_count", "comments_count", "bookmarks_count"
        ])
    }

    /// `default_sort_column` is `revised_at` when faceted/collected.
    @Test func defaultsToDateUpdatedDescending() {
        #expect(AO3WorksSort.default.column == .dateUpdated)
        #expect(AO3WorksSort.default.direction == .descending)
        #expect(AO3WorksSort.default.completion == .any)
        #expect(AO3WorksSort.default.isDefault)
        #expect(AO3WorksSort.default.activeCount == 0)
    }

    /// `default_sort_direction`: the two alphabetical columns ascend, the rest
    /// descend. Backwards here would put the least-read work first.
    @Test func alphabeticalColumnsAscendAndTheRestDescend() {
        #expect(AO3WorksSortColumn.creator.defaultDirection == .ascending)
        #expect(AO3WorksSortColumn.title.defaultDirection == .ascending)
        for column in AO3WorksSort.allColumns where column != .creator && column != .title {
            #expect(column.defaultDirection == .descending, "\(column.rawValue)")
        }
    }

    /// Choosing a column adopts that column's own default direction, so moving
    /// from Kudos to Title does not leave you reading Z to A.
    @Test func selectingAColumnAdoptsItsOwnDirection() {
        var sort = AO3WorksSort.default
        sort.select(.title)
        #expect(sort.direction == .ascending)
        sort.select(.kudos)
        #expect(sort.direction == .descending)
    }

    /// An untouched sheet must add nothing, so the URL stays the plain page URL
    /// and the existing page cache keeps hitting.
    @Test func defaultSortAddsNoQueryItems() throws {
        #expect(AO3WorksSort.default.queryItems.isEmpty)
        let route = try #require(AO3AuthorRoute(username: "tester"))
        let plain = route.contentURL(.works)
        #expect(route.contentURL(.works, sort: .default) == plain)
        #expect(plain.absoluteString == "https://archiveofourown.org/users/tester/works")
    }

    @Test func nonDefaultSortCarriesAO3sOwnParameterNames() throws {
        var sort = AO3WorksSort.default
        sort.select(.kudos)
        sort.completion = .incomplete
        let route = try #require(AO3AuthorRoute(username: "tester"))
        let query = route.contentURL(.works, page: 3, sort: sort).query ?? ""
        #expect(query.contains("page=3"))
        #expect(query.contains("work_search%5Bsort_column%5D=kudos_count"))
        #expect(query.contains("work_search%5Bcomplete%5D=F"))
        // Descending is kudos_count's own default, so it is not restated.
        #expect(!query.contains("sort_direction"))
        #expect(sort.activeCount == 2)
    }

    /// A direction that differs from the column's default must be sent, or the
    /// server silently applies its own and the control lies.
    @Test func explicitlyInvertedDirectionIsSent() throws {
        var sort = AO3WorksSort.default
        sort.select(.kudos)
        sort.direction = .ascending
        let query = try #require(AO3AuthorRoute(username: "tester"))
            .contentURL(.works, sort: sort).query ?? ""
        #expect(query.contains("work_search%5Bsort_direction%5D=asc"))
    }

    /// Bookmarks use a `bookmark_search` form and the series index has no sort
    /// form, so a works sort must not be smuggled onto either.
    @Test func sortAppliesToWorksOnly() throws {
        var sort = AO3WorksSort.default
        sort.select(.hits)
        let route = try #require(AO3AuthorRoute(username: "tester"))
        #expect(route.contentURL(.bookmarks, sort: sort) == route.contentURL(.bookmarks))
        #expect(route.contentURL(.series, sort: sort) == route.contentURL(.series))
        #expect(route.contentURL(.works, sort: sort) != route.contentURL(.works))
    }
}
