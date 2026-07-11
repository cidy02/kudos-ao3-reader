import Foundation
import SwiftSoup

extension AO3Client {
    static func parseAuthorWorksPage(_ html: String, page: Int) throws -> AO3SearchPage {
        let doc = try SwiftSoup.parse(html)
        let blurbs = try doc.select("li.work.blurb").array()
        let result = try parseSearchPage(html, page: page)
        if blurbs.isEmpty {
            let recognizedPage = try doc.select("ol.work.index, h2.heading, p.message, .flash").first() != nil
            guard recognizedPage else { throw AO3Error.parse }
        } else if result.works.isEmpty {
            throw AO3Error.parse
        }
        return result
    }

    static func parseAuthorDashboard(
        _ html: String,
        route: AO3AuthorRoute
    ) throws -> AO3AuthorHeader {
        let doc = try SwiftSoup.parse(html)
        guard try doc.select("div.user.home, div.user.pseud.home").first() != nil,
              try doc.select("div.primary.header.module").first() != nil
        else { throw AO3Error.parse }

        let avatarURL = try doc.select("div.primary.header.module .icon img").first()
            .flatMap { try absoluteAO3URL($0.attr("src")) }
        var identity = AO3AuthorIdentity(
            route: route,
            displayName: route.displayName,
            avatarURL: avatarURL
        )

        var pseuds = try parsePseuds(
            from: doc.select("#dashboard a[href*='/pseuds/'], dd.pseuds a[href*='/pseuds/']"),
            username: route.username
        )
        if let selected = route.pseud,
           !pseuds.contains(where: { $0.route.pseud == selected }),
           let selectedRoute = AO3AuthorRoute(username: route.username, pseud: selected) {
            pseuds.append(AO3AuthorPseud(name: selected, route: selectedRoute, avatarURL: avatarURL))
        }
        if let selected = route.pseud,
           let index = pseuds.firstIndex(where: { $0.route.pseud == selected }) {
            pseuds[index].avatarURL = avatarURL
        }
        pseuds.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let fandoms = try doc.select("#user-fandoms li").array().compactMap { item -> AO3AuthorFandom? in
            guard let link = try item.select("a").first() else { return nil }
            let name = try clean(link.text())
            guard !name.isEmpty else { return nil }
            let itemText = try item.text()
            let count = trailingCount(in: itemText)
            guard let url = try absoluteAO3URL(link.attr("href")) else { return nil }
            return AO3AuthorFandom(
                name: name,
                workCount: count,
                url: url
            )
        }

        let subscription = try parseAuthorSubscriptionForm(doc, referer: route.dashboardURL)
        let actions = try parseAuthorActions(
            doc.select("div.primary.header.module ul.navigation.actions a, #dashboard a"),
            username: route.username
        )
        if let userID = parseUserID(from: doc) {
            identity.userID = userID
        }
        return AO3AuthorHeader(
            identity: identity,
            pseuds: uniquePseuds(pseuds),
            fandoms: fandoms,
            subscriptionForm: subscription,
            actions: actions
        )
    }

    static func parseAuthorAbout(
        _ html: String,
        route: AO3AuthorRoute
    ) throws -> AO3AuthorAbout {
        let doc = try SwiftSoup.parse(html)
        guard try doc.select("div.user.home.profile").first() != nil else {
            throw AO3Error.parse
        }

        let title = try clean(doc.select("div.user.home.profile > h3.heading").first()?.text())
        let bioElement = try doc.select("div.bio blockquote.userstuff").first()
        let bio = try bioElement.map(parseRichText) ?? AO3RichText()
        let pseuds = try parsePseuds(
            from: doc.select("dl.meta dd.pseuds a[href*='/pseuds/']"),
            username: route.username
        )
        let actions = try parseAuthorActions(
            doc.select("div.user.home.profile ul.navigation.actions a"),
            username: route.username
        )

        return AO3AuthorAbout(
            profileTitle: title,
            bio: bio,
            pseuds: uniquePseuds(pseuds),
            joinedDate: metadataValue(in: doc, labelContaining: "joined"),
            userID: parseUserID(from: doc),
            actions: actions
        )
    }

    static func parseAuthorSeriesPage(_ html: String, page: Int) throws -> AO3SeriesPage {
        let doc = try SwiftSoup.parse(html)
        let blurbs = try doc.select("li.series").array()
        let series = blurbs.compactMap { try? parseSeriesBlurb($0) }
        if blurbs.isEmpty {
            let recognizedPage = try doc.select("ul.series.index, h2.heading, p.message, .flash").first() != nil
            guard recognizedPage else { throw AO3Error.parse }
        } else if series.isEmpty {
            throw AO3Error.parse
        }
        return AO3SeriesPage(
            series: series,
            currentPage: page,
            totalPages: try paginationTotal(in: doc, currentPage: page)
        )
    }

    static func parseAuthorBookmarksPage(
        _ html: String,
        page: Int
    ) throws -> AO3AuthorBookmarksPage {
        let doc = try SwiftSoup.parse(html)
        let blurbs = try doc.select("li.bookmark.blurb").array()
        let bookmarks = blurbs.compactMap { try? parseAuthorBookmark($0) }
        if blurbs.isEmpty {
            let recognizedPage = try doc.select("ol.bookmark.index, h2.heading, p.message, .flash").first() != nil
            guard recognizedPage else { throw AO3Error.parse }
        } else if bookmarks.isEmpty {
            throw AO3Error.parse
        }
        return AO3AuthorBookmarksPage(
            bookmarks: bookmarks,
            currentPage: page,
            totalPages: try paginationTotal(in: doc, currentPage: page)
        )
    }

    static func parseRichText(_ root: Element) throws -> AO3RichText {
        var blockElements: [(Element, AO3RichText.Block.Kind)] = []

        func collectBlocks(_ element: Element) throws {
            for child in element.children().array() {
                switch child.tagName().lowercased() {
                case "p", "div", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6":
                    blockElements.append((child, .paragraph))
                case "li":
                    blockElements.append((child, .listItem))
                default:
                    try collectBlocks(child)
                }
            }
        }
        try collectBlocks(root)
        if blockElements.isEmpty { blockElements = [(root, .paragraph)] }

        var blocks: [AO3RichText.Block] = []
        for (index, pair) in blockElements.enumerated() {
            var runs: [AO3RichText.Run] = []
            try appendRuns(from: pair.0, bold: false, italic: false, link: nil, to: &runs)
            runs = normalizedRuns(runs)
            if !runs.isEmpty {
                blocks.append(AO3RichText.Block(kind: pair.1, runs: runs, id: index))
            }
        }
        return AO3RichText(blocks: blocks)
    }

    private static func parseSeriesBlurb(_ element: Element) throws -> AO3SeriesSummary {
        guard let titleLink = try element.select("h4.heading a[href*='/series/']").first(),
              let url = try absoluteAO3URL(titleLink.attr("href")),
              let id = seriesID(from: url)
        else { throw AO3Error.parse }

        let authorLinks = try element.select("h4.heading a[rel=author], h4.heading a[href*='/pseuds/']").array()
        var creatorNames = try authorLinks.map { try clean($0.text()) }.filter { !$0.isEmpty }
        let hasAnonymousHeader = try element.select("div.header.module.anonymous").first() != nil
        if creatorNames.isEmpty, element.hasClass("anonymous") || hasAnonymousHeader {
            creatorNames = ["Anonymous"]
        }
        let identities = try authorLinks.compactMap {
            try AO3AuthorIdentity(displayName: $0.text(), href: $0.attr("href"))
        }
        let status = try element.select("ul.required-tags .iswip .text").first()?.text() ?? ""
        return AO3SeriesSummary(
            id: id,
            title: try clean(titleLink.text()),
            creatorNames: creatorNames,
            creatorIdentities: creatorNames == ["Anonymous"]
                ? [.nonNavigable("Anonymous", kind: .anonymous)]
                : identities,
            fandoms: try element.select("h5.fandoms a.tag").array().map { try clean($0.text()) },
            summary: try clean(element.select("blockquote.userstuff.summary").first()?.text()),
            words: statInt("words", in: element),
            workCount: statInt("works", in: element),
            dateUpdated: try clean(element.select("p.datetime").first()?.text()),
            isComplete: seriesCompletion(from: status),
            url: url
        )
    }

    private static func parseAuthorBookmark(_ element: Element) throws -> AO3AuthorBookmark {
        let identifier = element.id().replacingOccurrences(of: "bookmark_", with: "")
        guard let id = Int(identifier) else { throw AO3Error.parse }
        let work = try parseBlurb(element)
        let notesElement = try element.select("div.user.module blockquote.userstuff.notes").first()
        let statusMarkup = try element.select("p.status").first()?.outerHtml().lowercased() ?? ""
        return AO3AuthorBookmark(
            id: id,
            work: work,
            notes: try notesElement.map(parseRichText) ?? AO3RichText(),
            tags: try element.select("div.user.module ul.meta.tags a.tag").array().map { try clean($0.text()) },
            collections: try element.select("div.user.module a[href*='/collections/']").array()
                .map { try clean($0.text()) },
            isRecommendation: element.hasClass("rec") || statusMarkup.contains("recommend"),
            isPrivate: element.hasClass("private") || statusMarkup.contains("private"),
            date: try clean(element.select("div.user.module p.datetime").first()?.text())
        )
    }

    private static func parsePseuds(
        from elements: Elements,
        username: String
    ) throws -> [AO3AuthorPseud] {
        try elements.array().compactMap { link in
            let name = try clean(link.text())
            let href = try link.attr("href")
            guard let route = AO3AuthorRoute(path: href),
                  route.username.localizedCaseInsensitiveCompare(username) == .orderedSame,
                  route.pseud != nil, !name.isEmpty else { return nil }
            return AO3AuthorPseud(name: name, route: route, avatarURL: nil)
        }
    }

    private static func uniquePseuds(_ values: [AO3AuthorPseud]) -> [AO3AuthorPseud] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.route.id).inserted }
    }

    private static func parseAuthorSubscriptionForm(
        _ doc: Document,
        referer: URL
    ) throws -> AO3AuthorSubscriptionForm? {
        let csrf = parseCSRFToken(from: try doc.html())
        for form in try doc.select("form").array() {
            let type = try form.select("input[name='subscription[subscribable_type]']").first()?
                .attr("value") ?? ""
            guard type == "User", let csrf else { continue }
            let submit = try form.select("input[type=submit], button[type=submit]").first()
            let valueLabel = try submit?.attr("value") ?? ""
            let textLabel = try submit?.text() ?? ""
            let label = clean(valueLabel.isEmpty ? textLabel : valueLabel)
            guard let action = try absoluteAO3URL(form.attr("action")) else { continue }
            let fields = try form.select("input[name]").array().compactMap { input -> AO3FormField? in
                let name = try input.attr("name")
                guard !name.isEmpty else { return nil }
                return AO3FormField(name: name, value: try input.attr("value"))
            }
            return AO3AuthorSubscriptionForm(
                label: label,
                actionURL: action,
                fields: fields,
                csrfToken: csrf,
                referer: referer
            )
        }
        return nil
    }

    private static func parseAuthorActions(
        _ links: Elements,
        username: String
    ) throws -> [AO3AuthorWebAction] {
        var seen = Set<String>()
        return try links.array().compactMap { link in
            let label = try clean(link.text())
            guard !label.isEmpty, let url = try absoluteAO3URL(link.attr("href")),
                  seen.insert(url.absoluteString).inserted else { return nil }
            let lowerLabel = label.lowercased()
            let path = url.path.lowercased()
            let usernamePath = "/users/\(username.lowercased())"
            let kind: AO3AuthorWebAction.Kind
            if lowerLabel.contains("block") || path.contains("blocked") {
                kind = .block
            } else if lowerLabel.contains("mute") || path.contains("muted") {
                kind = .mute
            } else if path == "\(usernamePath)/profile"
                        || path == "\(usernamePath)/profile/edit" {
                kind = .profile
            } else if path == "\(usernamePath)/pseuds"
                        || path == "\(usernamePath)/profile/pseuds" {
                kind = .pseuds
            } else if path.contains("/works") {
                kind = .works
            } else if path.contains("/preferences") {
                kind = .preferences
            } else if path == usernamePath {
                kind = .dashboard
            } else {
                kind = .other
            }
            return AO3AuthorWebAction(label: label, url: url, kind: kind)
        }
    }

    private static func metadataValue(in doc: Document, labelContaining needle: String) -> String {
        guard let labels = try? doc.select("dl.meta dt").array() else { return "" }
        for label in labels {
            let text = ((try? label.text()) ?? "").lowercased()
            if text.contains(needle), let value = try? label.nextElementSibling()?.text() {
                return clean(value)
            }
        }
        return ""
    }

    private static func parseUserID(from doc: Document) -> Int? {
        let value = metadataValue(in: doc, labelContaining: "user id")
        return Int(value.filter(\.isNumber))
    }

    private static func appendRuns(
        from node: Node,
        bold: Bool,
        italic: Bool,
        link: URL?,
        to runs: inout [AO3RichText.Run]
    ) throws {
        if let text = node as? TextNode {
            runs.append(AO3RichText.Run(
                text: text.getWholeText(),
                isBold: bold,
                isItalic: italic,
                link: link
            ))
            return
        }
        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()
        if tag == "br" {
            runs.append(AO3RichText.Run(text: "\n", isBold: bold, isItalic: italic, link: link))
            return
        }
        let nextBold = bold || tag == "strong" || tag == "b"
        let nextItalic = italic || tag == "em" || tag == "i"
        var nextLink = link
        if tag == "a", let candidate = try safeRichTextURL(element.attr("href")) {
            nextLink = candidate
        }
        for child in element.getChildNodes() {
            try appendRuns(
                from: child,
                bold: nextBold,
                italic: nextItalic,
                link: nextLink,
                to: &runs
            )
        }
    }

    private static func normalizedRuns(_ runs: [AO3RichText.Run]) -> [AO3RichText.Run] {
        var result: [AO3RichText.Run] = []
        for run in runs {
            let text = run.text.replacingOccurrences(
                of: "[\\t\\r ]+",
                with: " ",
                options: .regularExpression
            )
            guard !text.isEmpty else { continue }
            if let last = result.last,
               last.isBold == run.isBold,
               last.isItalic == run.isItalic,
               last.link == run.link {
                result[result.count - 1] = AO3RichText.Run(
                    text: last.text + text,
                    isBold: last.isBold,
                    isItalic: last.isItalic,
                    link: last.link
                )
            } else {
                result.append(AO3RichText.Run(
                    text: text,
                    isBold: run.isBold,
                    isItalic: run.isItalic,
                    link: run.link
                ))
            }
        }
        return result
    }

    private static func paginationTotal(in doc: Document, currentPage: Int) throws -> Int {
        var total = currentPage
        for element in try doc.select("ol.pagination li, nav.pagination a, .pagination li").array() {
            let digits = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if let page = Int(digits), page > total { total = page }
        }
        return total
    }

    private static func statInt(_ kind: String, in element: Element) -> Int? {
        let text = (try? element.select("dl.stats dd.\(kind)").first()?.text()) ?? ""
        return Int(text.filter(\.isNumber))
    }

    private static func seriesCompletion(from text: String) -> Bool? {
        let value = text.lowercased()
        if value.range(of: #"\byes\b"#, options: .regularExpression) != nil { return true }
        if value.range(of: #"\bno\b"#, options: .regularExpression) != nil { return false }
        if value.contains("in progress") || value.contains("incomplete") { return false }
        return value.contains("complete") ? true : nil
    }

    private static func seriesID(from url: URL) -> Int? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(of: "series"), index + 1 < parts.count else { return nil }
        return Int(parts[index + 1])
    }

    private static func trailingCount(in text: String) -> Int? {
        guard let range = text.range(of: #"\(([\d,]+)\)\s*$"#, options: .regularExpression) else {
            return nil
        }
        return Int(text[range].filter(\.isNumber))
    }

    private static func absoluteAO3URL(_ value: String) throws -> URL? {
        let value = clean(value)
        guard !value.isEmpty,
              let url = URL(string: value, relativeTo: URL(string: "https://archiveofourown.org"))?.absoluteURL,
              AO3AuthorRoute.isAO3URL(url)
        else { return nil }
        return url
    }

    private static func safeRichTextURL(_ value: String) throws -> URL? {
        let value = clean(value)
        guard !value.isEmpty,
              let url = URL(
                string: value,
                relativeTo: URL(string: "https://archiveofourown.org")
              )?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    private static func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Short-lived HTML cache for author pages. Authentication scope is part of the
/// key, so private/restricted markup fetched with one session cannot be served to
/// a signed-out view or another account after a session change.
actor AO3AuthorPageCache {
    struct Key: Hashable, Sendable {
        let url: URL
        let authenticationScope: String
    }

    private struct Entry {
        let html: String
        let expiresAt: Date
        let staleUntil: Date
    }

    static let shared = AO3AuthorPageCache()
    private let ttl: TimeInterval
    private let staleTTL: TimeInterval
    private let maxEntries: Int
    private var entries: [Key: Entry] = [:]

    init(
        ttl: TimeInterval = 5 * 60,
        staleTTL: TimeInterval = 24 * 60 * 60,
        maxEntries: Int = 128
    ) {
        self.ttl = ttl
        self.staleTTL = max(ttl, staleTTL)
        self.maxEntries = max(1, maxEntries)
    }

    func value(for key: Key, now: Date = Date()) -> String? {
        guard let entry = entries[key] else { return nil }
        if entry.staleUntil <= now {
            entries.removeValue(forKey: key)
            return nil
        }
        guard entry.expiresAt > now else { return nil }
        return entry.html
    }

    func staleValue(for key: Key, now: Date = Date()) -> String? {
        guard let entry = entries[key] else { return nil }
        guard entry.staleUntil > now else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.html
    }

    func insert(_ html: String, for key: Key, now: Date = Date()) {
        entries = entries.filter { $0.value.staleUntil > now }
        if entries[key] == nil, entries.count >= maxEntries,
           let oldest = entries.min(by: { $0.value.staleUntil < $1.value.staleUntil })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[key] = Entry(
            html: html,
            expiresAt: now.addingTimeInterval(ttl),
            staleUntil: now.addingTimeInterval(staleTTL)
        )
    }

    func removeValue(for key: Key) {
        entries.removeValue(forKey: key)
    }

    func removeAuthorDashboards(username: String, authenticationScope: String) {
        entries = entries.filter { key, _ in
            guard key.authenticationScope == authenticationScope,
                  let route = AO3AuthorRoute(url: key.url),
                  route.username.localizedCaseInsensitiveCompare(username) == .orderedSame,
                  key.url.path == route.dashboardURL.path
            else { return true }
            return false
        }
    }
}
