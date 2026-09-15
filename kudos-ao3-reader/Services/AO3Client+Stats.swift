import Foundation
import SwiftSoup

/// A user's career totals from `/users/:id/stats` — artboard **1u**'s hero line
/// ("12 works · 248,400 words · 3,812 kudos").
///
/// Every field is optional because AO3 renders a different template
/// (`stats/no_stats`) for an account with no posted works, and because a figure
/// this screen cannot read is dropped rather than shown as zero.
nonisolated struct AO3UserStats: Equatable, Sendable {
    var wordCount: Int?
    var kudos: Int?
    var hits: Int?
    var bookmarks: Int?
    var commentThreads: Int?
    var subscriptions: Int?
    var userSubscriptions: Int?

    var isEmpty: Bool {
        self == AO3UserStats()
    }
}

extension AO3Client {
    /// `/users/:id/stats`.
    ///
    /// **Own account only.** otwarchive's `StatsController` sets
    /// `@user = current_user` behind `users_only` and `check_ownership`, so there
    /// is no such page for anyone else — this must never be fetched for another
    /// author's profile.
    ///
    /// No `year` parameter: `@current_year` falls back to "All Years" when none
    /// is given, which is the career total 1u's hero wants. Passing a year would
    /// silently turn it into one year's figures.
    static func userStatsURL(username: String) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/stats"
        return components?.url
    }

    /// Parse the Totals block.
    ///
    /// Scoped to `dl.statistics.meta` and never to the page at large: the same
    /// `dd.kudos` / `dd.bookmarks` classes repeat on every work in the listing
    /// below, so an unscoped `.first()` would read one work's kudos and call it
    /// the career total.
    ///
    /// Class names come from otwarchive's `stat.to_s.humanize.downcase`, which
    /// is why `:word_count` is `words` (it is special-cased in the template) and
    /// why `:user_subscriptions` renders as the two classes `user subscriptions`
    /// — meaning a bare `.subscriptions` selector matches that row too. Both are
    /// read by matching the full class list rather than a single token.
    static func parseUserStats(from html: String) throws -> AO3UserStats {
        let doc = try SwiftSoup.parse(html)
        guard let totals = try doc.select("dl.statistics.meta").first() else {
            // `stats/no_stats` renders no totals block at all. An account with
            // no posted works is not a parse failure.
            return AO3UserStats()
        }
        var byClass: [String: Int] = [:]
        for element in try totals.select("dd").array() {
            let classes = try element.classNames().sorted().joined(separator: " ")
            guard let value = statsNumber(try element.text()) else { continue }
            byClass[classes] = value
        }
        return AO3UserStats(
            wordCount: byClass["words"],
            kudos: byClass["kudos"],
            hits: byClass["hits"],
            bookmarks: byClass["bookmarks"],
            commentThreads: byClass["comment count thread"],
            subscriptions: byClass["subscriptions"],
            userSubscriptions: byClass["subscriptions user"]
        )
    }

    /// `number_with_delimiter` writes "248,400". Strip anything that is not a
    /// digit rather than trusting one locale's separator.
    private static func statsNumber(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}
