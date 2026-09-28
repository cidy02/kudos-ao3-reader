import Foundation
import SwiftSoup

/// 1p.4's Works / Series / Authors pills. Each one is `type=` on the same
/// subscriptions index (otwarchive `subscriptions_controller.rb:15-22`), so
/// each is its own fetch and its own pagination. Works keeps the work rows it
/// always had; Series and Authors are name rows.
nonisolated enum AO3SubscriptionsScope: String, CaseIterable, Identifiable, Sendable {
    case works
    case series
    case users

    var id: String { rawValue }

    var title: String {
        switch self {
        case .works: "Works"
        case .series: "Series"
        case .users: "Authors"
        }
    }
}

/// One series or user subscription. The index prints a link to the item,
/// a byline for a series, and the unsubscribe form in the next `<dd>`.
/// Nothing else — no stats, no summary.
nonisolated struct AO3NamedSubscription: Identifiable, Hashable, Sendable {
    /// The subscribed item's own path: `/series/<id>` or `/users/<login>`.
    let path: String
    let name: String
    /// A series' byline pseuds. Empty for a user row.
    let creators: [AO3AuthorIdentity]
    let unsubscribePath: String?

    var id: String { path }

    var seriesID: Int? {
        let parts = path.split(separator: "/")
        guard parts.count == 2, parts[0] == "series" else { return nil }
        return Int(parts[1])
    }

    var authorRoute: AO3AuthorRoute? {
        seriesID == nil ? AO3AuthorRoute(path: path) : nil
    }

    /// Enough for `AO3SeriesDetailView`, which fetches the series' works from
    /// `url`. The index has none of the other fields.
    /// ponytail: the detail header draws this value, so a series opened from
    /// here shows title and byline only (no fandoms, counts or lock). Parse the
    /// series page's own meta if that header needs to be full.
    var seriesSummary: AO3SeriesSummary? {
        guard let seriesID, let url = AO3SitePath.absolute(path) else { return nil }
        return AO3SeriesSummary(
            id: seriesID, title: name,
            creatorNames: creators.map(\.displayName), creatorIdentities: creators,
            fandoms: [], summary: "", words: nil, workCount: nil, bookmarkCount: nil,
            dateUpdated: "", isComplete: nil, isRestricted: false, url: url
        )
    }
}

nonisolated struct AO3NamedSubscriptionsPage: Sendable {
    var rows: [AO3NamedSubscription]
    var currentPage: Int
    var totalPages: Int
}

private nonisolated enum AO3SitePath {
    static func absolute(_ path: String) -> URL? {
        URL(string: path, relativeTo: URL(string: "https://archiveofourown.org"))?.absoluteURL
    }
}

extension AO3Client {
    /// The rows of one named scope. A row is kept when its first link is that
    /// scope's own path. A series byline links `/users/…/pseuds/…` too, which
    /// is why the first link decides and the rest are the byline.
    static func parseNamedSubscriptions(
        _ html: String, scope: AO3SubscriptionsScope, page: Int
    ) throws -> AO3NamedSubscriptionsPage {
        let doc = try SwiftSoup.parse(html)
        var rows: [AO3NamedSubscription] = []
        var seen = Set<String>()
        for heading in try doc.select("dl.subscription dt").array() {
            let links = try heading.select("a[href]").array()
            guard let first = links.first,
                  let path = AO3SitePath.absolute(try first.attr("href"))?.path,
                  namedScope(ofPath: path) == scope,
                  seen.insert(path).inserted
            else { continue }
            // The byline is AO3's `rel="author"` links. One that does not
            // parse is skipped, not the whole page.
            let creators = scope == .series
                ? links.dropFirst().filter { (try? $0.attr("rel")) == "author" }.compactMap { link in
                    AO3AuthorIdentity(displayName: (try? link.text()) ?? "", href: (try? link.attr("href")) ?? "")
                }
                : []
            rows.append(AO3NamedSubscription(
                path: path,
                name: try first.text(),
                creators: creators,
                unsubscribePath: try unsubscribeAction(after: heading)
            ))
        }
        return AO3NamedSubscriptionsPage(
            rows: rows,
            currentPage: page,
            totalPages: try paginationTotal(in: doc, currentPage: page)
        )
    }

    /// `/series/<id>` or `/users/<login>`. A work path, or anything deeper
    /// (a pseud, a user's works), is neither.
    static func namedScope(ofPath path: String) -> AO3SubscriptionsScope? {
        let parts = path.split(separator: "/")
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "series": return Int(parts[1]) == nil ? nil : .series
        case "users": return .users
        default: return nil
        }
    }
}

extension AO3AuthService {
    /// One page of the signed-in user's series or user subscriptions. Nil when
    /// signed out; throws on a fetch or parse failure.
    func accountNamedSubscriptions(
        scope: AO3SubscriptionsScope, page: Int
    ) async throws -> AO3NamedSubscriptionsPage? {
        guard isLoggedIn, let username,
              let url = AO3Client.subscriptionsURL(username: username, page: page, type: scope.rawValue)
        else { return nil }
        let request = try authenticatedRequest(for: url)
        return try await AO3Client.shared.namedSubscriptions(for: request, scope: scope, page: page)
    }
}
