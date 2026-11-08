import Foundation
import SwiftSoup

extension AO3Client {
    /// One page of the signed-in user's series or user subscriptions.
    ///
    /// Grounded in otwarchive `452391b6` (master, 2026-11-01):
    /// `app/controllers/subscriptions_controller.rb` (`index`, `load_subscribable_type`),
    /// `app/views/subscriptions/index.html.erb`, `app/models/subscription.rb` (`name`),
    /// `app/helpers/byline_helper.rb`, `lib/pagination_list_link_renderer.rb`,
    /// `config/locales/views/en.yml` (`subscriptions.index`),
    /// `config/locales/models/en.yml` (`subscriptions.deleted`).
    /// A missing `dl.subscription.index.group` is `AO3Error.parse`, not an empty follow list.
    static func parseSubscriptionIndex(
        _ html: String,
        page: Int,
        type: AO3SubscriptionListType
    ) throws -> AO3SubscriptionIndexPage {
        guard type == .series || type == .users else { throw AO3Error.parse }
        let doc = try SwiftSoup.parse(html)
        guard try doc.select("dl.subscription.index.group").first() != nil else {
            throw AO3Error.parse
        }

        var series: [AO3FollowedSeries] = []
        var authors: [AO3FollowedAuthor] = []
        for dt in try doc.select("dl.subscription.index.group dt").array() {
            guard let dd = try dt.nextElementSibling(), dd.tagName() == "dd" else {
                throw AO3Error.parse
            }
            let subscriptionID = try subscriptionID(in: dd)
            let anchors = try dt.select("a").array()
            if anchors.isEmpty {
                let name = try dt.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw AO3Error.parse }
                switch type {
                case .series:
                    series.append(AO3FollowedSeries(
                        subscriptionID: subscriptionID,
                        title: name,
                        creatorNames: [],
                        creatorIdentities: [],
                        seriesID: nil,
                        url: nil
                    ))
                case .users:
                    authors.append(AO3FollowedAuthor(
                        subscriptionID: subscriptionID,
                        name: name,
                        route: nil
                    ))
                case .works:
                    throw AO3Error.parse
                }
                continue
            }

            let href = try anchors[0].attr("href")
            switch type {
            case .series:
                guard let seriesID = seriesID(in: href),
                      let url = absoluteSubscriptionURL(href) else { throw AO3Error.parse }
                let title = try anchors[0].text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { throw AO3Error.parse }
                let creators = try creatorLinks(Array(anchors.dropFirst()), fallback: byline(in: dt, title: title))
                series.append(AO3FollowedSeries(
                    subscriptionID: subscriptionID,
                    title: title,
                    creatorNames: creators.names,
                    creatorIdentities: creators.identities,
                    seriesID: seriesID,
                    url: url
                ))
            case .users:
                // The user row is a single link to `/users/<login>`. A byline-shaped
                // row (extra links) is the wrong list.
                guard anchors.count == 1,
                      let route = subscribedUserRoute(in: href) else { throw AO3Error.parse }
                let name = try anchors[0].text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw AO3Error.parse }
                authors.append(AO3FollowedAuthor(
                    subscriptionID: subscriptionID,
                    name: name,
                    route: route
                ))
            case .works:
                throw AO3Error.parse
            }
        }

        return AO3SubscriptionIndexPage(
            series: series,
            authors: authors,
            currentPage: page,
            totalPages: try totalPages(in: doc, current: page)
        )
    }

    /// The index always renders a delete form for each row (`form_for` with
    /// `html: { method: :delete }`), including rows whose subscribable is gone.
    private static func subscriptionID(in dd: Element) throws -> Int {
        guard let form = try dd.select("form").first() else { throw AO3Error.parse }
        let method = (try form.select("input[name=_method]").first()?.attr("value"))?
            .lowercased() ?? ""
        guard method == "delete" else { throw AO3Error.parse }
        guard let id = subscriptionID(in: try form.attr("action")) else { throw AO3Error.parse }
        return id
    }

    private static func subscriptionID(in action: String) -> Int? {
        guard let url = absoluteSubscriptionURL(action) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[parts.count - 2] == "subscriptions" else { return nil }
        return Int(parts[parts.count - 1])
    }

    /// Item link on a series row is exactly `/series/<id>`. Byline links come after it.
    private static func seriesID(in href: String) -> Int? {
        guard let url = absoluteSubscriptionURL(href) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "series" else { return nil }
        return Int(parts[1])
    }

    /// Item link on a user row is exactly `/users/<login>`, the polymorphic user path.
    private static func subscribedUserRoute(in href: String) -> AO3AuthorRoute? {
        guard let url = absoluteSubscriptionURL(href) else { return nil }
        let parts = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.removingPercentEncoding ?? $0 }
        guard parts.count == 2, parts[0] == "users" else { return nil }
        return AO3AuthorRoute(username: parts[1])
    }

    private static func creatorLinks(
        _ anchors: [Element],
        fallback: String
    ) throws -> (names: [String], identities: [AO3AuthorIdentity]) {
        if anchors.isEmpty {
            guard !fallback.isEmpty else { return ([], []) }
            if fallback.caseInsensitiveCompare("Anonymous") == .orderedSame {
                return ([fallback], [.nonNavigable(fallback, kind: .anonymous)])
            }
            return ([fallback], [])
        }
        var names: [String] = []
        var identities: [AO3AuthorIdentity] = []
        for link in anchors {
            let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            names.append(name)
            if let identity = try AO3AuthorIdentity(displayName: name, href: link.attr("href")) {
                identities.append(identity)
            }
        }
        return (names, identities)
    }

    /// Text after the series title. The template's byline is `by %{creators}`.
    private static func byline(in dt: Element, title: String) throws -> String {
        let full = try dt.text()
        guard let range = full.range(of: title) else { return "" }
        var rest = full[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "by "
        if rest.lowercased().hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return rest
    }

    private static func totalPages(in doc: Document, current: Int) throws -> Int {
        var total = current
        for li in try doc.select("ol.pagination li").array() {
            if let value = try Int(li.text().trimmingCharacters(in: .whitespacesAndNewlines)), value > total {
                total = value
            }
        }
        return total
    }

    private static func absoluteSubscriptionURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed, relativeTo: URL(string: "https://archiveofourown.org"))?.absoluteURL,
              AO3AuthorRoute.isAO3URL(url)
        else { return nil }
        return url
    }
}
