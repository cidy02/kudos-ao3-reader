import Foundation
import SwiftSoup

/// The signed-in user's `/users/:id/stats` page: its totals, year choices, and
/// per-work figures. AO3 exposes no history or trend data on this page.
///
/// Every field is optional because AO3 renders a different template
/// (`stats/no_stats`) for an account with no posted works, and because a figure
/// this screen cannot read is dropped rather than shown as zero.
nonisolated struct AO3UserStats: Equatable, Sendable {
    struct Work: Identifiable, Equatable, Sendable {
        let id: Int
        let title: String
        var fandoms: [String]
        let wordCount: Int?
        let hits: Int?
        let kudos: Int?
        let commentThreads: Int?
        let bookmarks: Int?
        let subscriptions: Int
        let sourceOrder: Int
    }

    struct FandomGroup: Identifiable, Equatable, Sendable {
        var id: String { name }
        let name: String
        let works: [Work]
    }

    enum Grouping: String, CaseIterable, Hashable, Sendable {
        case byFandom = "By Fandom"
        case flat = "Flat"
    }

    enum Sort: String, CaseIterable, Hashable, Sendable {
        case date = "Date"
        case wordCount = "Word Count"
        case hits = "Hits"
        case kudos = "Kudos"
        case commentThreads = "Comment Threads"
        case bookmarks = "Bookmarks"
        case subscriptions = "Subscriptions"

        func value(for work: Work) -> Int? {
            switch self {
            case .date: nil
            case .wordCount: work.wordCount
            case .hits: work.hits
            case .kudos: work.kudos
            case .commentThreads: work.commentThreads
            case .bookmarks: work.bookmarks
            case .subscriptions: work.subscriptions
            }
        }
    }

    var wordCount: Int?
    var kudos: Int?
    var hits: Int?
    var bookmarks: Int?
    var commentThreads: Int?
    var subscriptions: Int?
    var userSubscriptions: Int?
    var availableYears: [Int] = []
    var selectedYear: Int?
    var fandomGroups: [FandomGroup] = []

    var isEmpty: Bool {
        wordCount == nil && kudos == nil && hits == nil && bookmarks == nil
            && commentThreads == nil && subscriptions == nil && userSubscriptions == nil
            && fandomGroups.isEmpty
    }

    func sections(grouping: Grouping, sortedBy sort: Sort) -> [FandomGroup] {
        switch grouping {
        case .byFandom:
            return fandomGroups.map {
                FandomGroup(name: $0.name, works: sorted($0.works, by: sort))
            }
        case .flat:
            return [FandomGroup(name: "", works: sorted(flatWorks, by: sort))]
        }
    }

    private var flatWorks: [Work] {
        var merged: [Work] = []
        var indexByID: [Int: Int] = [:]
        for group in fandomGroups {
            for work in group.works {
                if let index = indexByID[work.id] {
                    for fandom in work.fandoms where !merged[index].fandoms.contains(fandom) {
                        merged[index].fandoms.append(fandom)
                    }
                } else {
                    indexByID[work.id] = merged.count
                    merged.append(work)
                }
            }
        }
        return merged
    }

    private func sorted(_ works: [Work], by sort: Sort) -> [Work] {
        works.sorted { lhs, rhs in
            if sort == .date { return lhs.sourceOrder < rhs.sourceOrder }
            let left = sort.value(for: lhs) ?? Int.min
            let right = sort.value(for: rhs) ?? Int.min
            if left != right { return left > right }
            return lhs.sourceOrder < rhs.sourceOrder
        }
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
    /// With no `year`, `@current_year` is "All Years". The date sort gives the
    /// client a stable source order for its Date chip; every other sort is local.
    static func userStatsURL(username: String, year: Int? = nil) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/stats"
        components?.queryItems = [
            URLQueryItem(name: "sort_column", value: "date"),
            URLQueryItem(name: "sort_direction", value: "DESC")
        ]
        if let year {
            components?.queryItems?.append(URLQueryItem(name: "year", value: String(year)))
        }
        return components?.url
    }

    /// Parse the Totals block, year choices, fandom groups, and work rows.
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
        let yearSelection = try parseStatsYears(in: doc)
        let fandomGroups = try parseStatsWorks(in: doc)
        return AO3UserStats(
            wordCount: byClass["words"],
            kudos: byClass["kudos"],
            hits: byClass["hits"],
            bookmarks: byClass["bookmarks"],
            commentThreads: byClass["comment count thread"],
            subscriptions: byClass["subscriptions"],
            userSubscriptions: byClass["subscriptions user"],
            availableYears: yearSelection.years,
            selectedYear: yearSelection.selected,
            fandomGroups: fandomGroups
        )
    }

    private static func parseStatsYears(in doc: Document) throws -> (years: [Int], selected: Int?) {
        var years: [Int] = []
        var selected: Int?
        for item in try doc.select("ol.year.actions > li").array() {
            if let current = try item.select("span.current").first(),
               let year = Int(try current.text()) {
                selected = year
                years.append(year)
            }
            if let link = try item.select("a").first(), let year = Int(try link.text()) {
                years.append(year)
            }
        }
        return (years.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }, selected)
    }

    private static func parseStatsWorks(in doc: Document) throws -> [AO3UserStats.FandomGroup] {
        var groups: [AO3UserStats.FandomGroup] = []
        var sourceOrder = 0
        for element in try doc.select("ul.statistics.index.group > li.fandom.listbox.group").array() {
            guard let heading = try element.select("h5.heading").first() else { continue }
            let fandom = try heading.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fandom.isEmpty,
                  let list = element.children().array().first(where: {
                      $0.tagName() == "ul" && ((try? $0.classNames()) ?? []).contains("index")
                  })
            else { continue }

            var works: [AO3UserStats.Work] = []
            for item in list.children().array() where item.tagName() == "li" {
                guard let row = item.children().array().first(where: { $0.tagName() == "dl" }),
                      let titleRow = row.children().array().first(where: { $0.tagName() == "dt" }),
                      let link = try titleRow.select("a[href]").first(),
                      let id = workIDFromPath(try link.attr("href"))
                else { continue }
                let stats = try row.select("dd > dl.stats").first()
                works.append(AO3UserStats.Work(
                    id: id,
                    title: try link.text(),
                    fandoms: [fandom],
                    wordCount: statsNumber(try titleRow.select("span.words").first()?.text() ?? ""),
                    hits: try statsValue("hits", in: stats),
                    kudos: try statsValue("kudos", in: stats),
                    commentThreads: try statsValue("comments", in: stats),
                    bookmarks: try statsValue("bookmarks", in: stats),
                    // AO3 omits this row only when the count is zero.
                    subscriptions: try statsValue("subscriptions", in: stats) ?? 0,
                    sourceOrder: sourceOrder
                ))
                sourceOrder += 1
            }
            if !works.isEmpty {
                groups.append(AO3UserStats.FandomGroup(name: fandom, works: works))
            }
        }
        return groups
    }

    private static func statsValue(_ name: String, in stats: Element?) throws -> Int? {
        guard let stats, let value = try stats.select("dd.\(name)").first() else { return nil }
        return statsNumber(try value.text())
    }

    /// `number_with_delimiter` writes "248,400". Strip anything that is not a
    /// digit rather than trusting one locale's separator.
    private static func statsNumber(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}

extension AO3AuthService {
    /// One cancellable, foreground read of the signed-in account's stats page.
    func loadUserStats(year: Int? = nil) async throws -> AO3UserStats {
        guard isLoggedIn, let username,
              let url = AO3Client.userStatsURL(username: username, year: year)
        else { throw AO3Error.authenticationRequired }
        let generation = sessionGeneration
        let request = try authenticatedRequest(for: url)
        let html = try await AO3RequestCoordinator.shared.withSlot {
            try await AO3Client.shared.authenticatedPageHTML(for: request)
        }
        try Task.checkCancellation()
        guard generation == sessionGeneration else { throw CancellationError() }
        return try AO3Client.parseUserStats(from: html)
    }
}
