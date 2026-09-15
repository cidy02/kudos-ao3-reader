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

    /// otwarchive renders `stats/no_stats` when a user has no posted works. That
    /// page carries no totals block and is not a parse failure.
    @Test func anAccountWithNoWorksParsesEmptyRatherThanThrowing() throws {
        let stats = try AO3Client.parseUserStats(from: fixture("ao3_user_stats_none"))
        #expect(stats.isEmpty)
        #expect(stats.wordCount == nil)
        #expect(stats.kudos == nil)
    }

    /// No `year` parameter: `@current_year` falls back to "All Years", which is
    /// the career total. Sending a year would quietly scope the hero to it.
    @Test func statsURLAsksForAllYears() throws {
        let url = try #require(AO3Client.userStatsURL(username: "tester"))
        #expect(url.absoluteString == "https://archiveofourown.org/users/tester/stats")
        #expect(url.query == nil)
        #expect(AO3Client.userStatsURL(username: "  ") == nil)
    }
}

private final class BundleToken {}
