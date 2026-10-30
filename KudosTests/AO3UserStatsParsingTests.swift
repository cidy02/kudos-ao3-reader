import Foundation
import Testing
@testable import Kudos

/// 1u's hero totals, pinned to otwarchive's `stats/index.html.erb` and
/// `StatsController`. The fixture mirrors that template, including the per-work
/// listing below the Totals block — which is the whole point of the first test.
struct AO3UserStatsParsingTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle(for: BundleToken.self)
            .url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The Totals block and every work in the listing below it both use
    /// `dd.kudos` and `dd.bookmarks`. An unscoped `.first()` would read one
    /// work's kudos (1,204) and present it as the career total (3,812).
    @Test func totalsComeFromTheTotalsBlockNotTheFirstWork() throws {
        let stats = try AO3Client.parseUserStats(from: fixture("ao3_user_stats"))
        #expect(stats.kudos == 3812)
        #expect(stats.kudos != 1204, "read a single work's kudos as the career total")
        #expect(stats.bookmarks == 96)
    }

    @Test func readsWordCountAndTheRestOfTheTotals() throws {
        let stats = try AO3Client.parseUserStats(from: fixture("ao3_user_stats"))
        // `:word_count` is special-cased to the class "words" in the template.
        #expect(stats.wordCount == 248_400)
        #expect(stats.hits == 28900)
        #expect(stats.commentThreads == 214)
        #expect(!stats.isEmpty)
    }

    /// `user_subscriptions` humanizes to the TWO classes "user subscriptions",
    /// so a bare `.subscriptions` selector matches it as well as the real
    /// subscriptions row. They must not be confused for one another.
    @Test func userSubscriptionsIsNotMistakenForSubscriptions() throws {
        let stats = try AO3Client.parseUserStats(from: fixture("ao3_user_stats"))
        #expect(stats.subscriptions == 128)
        #expect(stats.userSubscriptions == 57)
    }

    @Test func readsYearChoicesAndPerWorkFiguresWithinEachRow() throws {
        let stats = try AO3Client.parseUserStats(from: fixture("ao3_user_stats"))
        #expect(stats.availableYears == [2025, 2024])
        #expect(stats.selectedYear == nil)
        #expect(stats.fandomGroups.map(\.name) == ["Jujutsu Kaisen", "Original Work"])

        let first = try #require(stats.fandomGroups.first?.works.first)
        #expect(first.id == 11)
        #expect(first.title == "The Weight of Water")
        #expect(first.wordCount == 84_200)
        #expect(first.hits == 28_900)
        #expect(first.kudos == 1204)
        #expect(first.commentThreads == 318)
        #expect(first.bookmarks == 96)
        #expect(first.subscriptions == 44)

        // The template omits the subscriptions row when the count is zero.
        let unsubscribed = try #require(stats.fandomGroups.first?.works.last)
        #expect(unsubscribed.id == 22)
        #expect(unsubscribed.subscriptions == 0)
    }

    @Test func flatViewDeduplicatesMultifandomWorksAndSortsMeasuresDescending() throws {
        let stats = try AO3Client.parseUserStats(from: fixture("ao3_user_stats"))
        let works = try #require(stats.sections(grouping: .flat, sortedBy: .kudos).first?.works)

        #expect(works.map(\.id) == [22, 11])
        #expect(works.first?.fandoms == ["Jujutsu Kaisen", "Original Work"])
        let dateGroups = stats.sections(grouping: .byFandom, sortedBy: .date)
        #expect(dateGroups.count == 2)
        #expect(dateGroups.first?.works.map(\.id) == [11, 22])
    }

    /// otwarchive renders `stats/no_stats` when a user has no posted works. That
    /// page carries no totals block and is not a parse failure.
    @Test func anAccountWithNoWorksParsesEmptyRatherThanThrowing() throws {
        let stats = try AO3Client.parseUserStats(from: fixture("ao3_user_stats_none"))
        #expect(stats.isEmpty)
        #expect(stats.wordCount == nil)
        #expect(stats.kudos == nil)
    }

    /// No `year` parameter means All Years; a selected year is AO3's own filter.
    @Test func statsURLBuildsAllYearsAndYearSpecificRequests() throws {
        let url = try #require(AO3Client.userStatsURL(username: "tester"))
        let allYears = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(allYears.path == "/users/tester/stats")
        #expect(allYears.queryItems?.first(where: { $0.name == "year" }) == nil)
        #expect(allYears.queryItems?.first(where: { $0.name == "sort_column" })?.value == "date")
        #expect(allYears.queryItems?.first(where: { $0.name == "sort_direction" })?.value == "DESC")

        let yearURL = try #require(AO3Client.userStatsURL(username: "tester", year: 2024))
        let oneYear = try #require(URLComponents(url: yearURL, resolvingAgainstBaseURL: false))
        #expect(oneYear.queryItems?.first(where: { $0.name == "year" })?.value == "2024")
        #expect(AO3Client.userStatsURL(username: "  ") == nil)
    }
}

private final class BundleToken {}
