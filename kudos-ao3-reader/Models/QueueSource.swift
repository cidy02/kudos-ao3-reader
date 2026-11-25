import Foundation
import SwiftData

/// Result of an anonymous page-1 queue-source fetch, holding both the parsed
/// work summaries (for counting and tag/search reuse) and raw HTML (for author
/// and series page reuse on Find More).
nonisolated struct QueueSourceFetchedPage: Sendable {
    let url: URL
    let page: AO3SearchPage
    let html: String
    /// When the anonymous fetch finished. Find More reuses a page only while
    /// it is younger than `QueueSourceChecks.cooldown`.
    var fetchedAt: Date = Date()
}

/// The four queue source kinds this build understands. Unknown raw strings from
/// future builds are stored verbatim on `QueueSavedSearchLink.sourceKindRaw` and
/// round-trip through backup and Folder Sync without being fetched or dropped.
nonisolated enum QueueSourceKind: String, CaseIterable, Codable, Sendable, Hashable {
    case savedSearch
    case author
    case series
    case tag

    var symbolName: String {
        switch self {
        case .savedSearch: "magnifyingglass"
        case .author: "person"
        case .series: "square.stack"
        case .tag: "tag"
        }
    }

    var kindLabel: String {
        switch self {
        case .savedSearch: "Saved search"
        case .author: "Author"
        case .series: "Series"
        case .tag: "Tag"
        }
    }
}

/// Value-type draft for adding or editing a non-search queue source (author,
/// series, or tag) before committing it to SwiftData.
nonisolated struct QueueSourceDraft: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: QueueSourceKind
    var targetKey: String
    var displayName: String
    var subtitle: String?
    var authorUsername: String?
    var authorPseud: String?
    var ao3SeriesID: Int?
    var tagName: String?
    var tagCategoryRaw: String?
    var urlString: String?

    var dedupKey: String {
        Self.dedupKey(kindRaw: kind.rawValue, targetKey: targetKey, fallbackID: id)
    }

    static func dedupKey(kindRaw: String, targetKey: String?, fallbackID: UUID) -> String {
        let normalizedKind = kindRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTarget = (targetKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalizedTarget.isEmpty {
            return "\(normalizedKind)|\(normalizedTarget)"
        }
        return "\(normalizedKind)|\(fallbackID.uuidString.lowercased())"
    }

    /// The identity key rebuilt from a row's own fields, for a restored row
    /// that arrived without `targetKey`. `nil` when the fields say nothing.
    static func derivedTargetKey(
        kindRaw: String?, authorUsername: String?, authorPseud: String?,
        ao3SeriesID: Int?, tagName: String?
    ) -> String? {
        switch kindRaw.flatMap(QueueSourceKind.init(rawValue:)) {
        case .author:
            guard let user = authorUsername, !user.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return authorTargetKey(username: user, pseud: authorPseud)
        case .series:
            return ao3SeriesID.flatMap { $0 > 0 ? seriesTargetKey(id: $0) : nil }
        case .tag:
            guard let name = tagName, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return tagTargetKey(name: name)
        case .savedSearch, nil:
            return nil
        }
    }

    /// A stored tag URL is reusable only when it is exactly AO3's works listing
    /// for a tag (`/tags/<name>/works`) on the default port; a tag info page,
    /// a work, or another port is never fetched under the counts feature.
    static func isTagWorksURL(_ url: URL) -> Bool {
        guard AO3RequestDefaults.isTrustedURL(url), url.port == nil else { return false }
        let parts = url.pathComponents
        return parts.count == 4 && parts[1] == "tags" && parts[3] == "works"
    }

    static func authorTargetKey(username: String, pseud: String?) -> String {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let pseud = pseud?.trimmingCharacters(in: .whitespacesAndNewlines), !pseud.isEmpty {
            return "user:\(user)/pseud:\(pseud.lowercased())"
        }
        return "user:\(user)"
    }

    static func seriesTargetKey(id: Int) -> String {
        "series:\(id)"
    }

    static func tagTargetKey(name: String) -> String {
        "tag:\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    static func author(
        username rawUsername: String,
        pseud rawPseud: String? = nil,
        displayName rawDisplayName: String? = nil,
        subtitle rawSubtitle: String? = nil
    ) -> QueueSourceDraft? {
        let trimmedPseud = rawPseud?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPseud = (trimmedPseud?.isEmpty == false) ? trimmedPseud : nil
        guard let route = AO3AuthorRoute(username: rawUsername, pseud: normalizedPseud) else { return nil }
        let label = rawDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let label, !label.isEmpty {
            title = label
        } else if let pseud = route.pseud,
                  pseud.localizedCaseInsensitiveCompare(route.username) != .orderedSame {
            title = "\(pseud) (\(route.username))"
        } else {
            title = route.username
        }
        let defaultSub = route.pseud != nil ? "Pseud of \(route.username)" : "Author"
        return QueueSourceDraft(
            kind: .author,
            targetKey: authorTargetKey(username: route.username, pseud: route.pseud),
            displayName: title,
            subtitle: rawSubtitle ?? defaultSub,
            authorUsername: route.username,
            authorPseud: route.pseud,
            urlString: route.contentURL(.works).absoluteString
        )
    }

    static func series(
        id: Int,
        title rawTitle: String,
        subtitle rawSubtitle: String? = nil
    ) -> QueueSourceDraft? {
        guard id > 0 else { return nil }
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Series \(id)" : trimmed
        let urlString = "https://archiveofourown.org/series/\(id)"
        return QueueSourceDraft(
            kind: .series,
            targetKey: seriesTargetKey(id: id),
            displayName: title,
            subtitle: rawSubtitle ?? "Series",
            ao3SeriesID: id,
            urlString: urlString
        )
    }

    static func tag(
        name rawName: String,
        category rawCategory: String? = nil,
        url existingURL: URL? = nil
    ) -> QueueSourceDraft? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let canonicalURL: URL?
        if let existingURL, isTagWorksURL(existingURL) {
            canonicalURL = existingURL
        } else {
            canonicalURL = AO3Client.tagWorksURL(tagName: name)
        }
        guard let resolvedURL = canonicalURL else { return nil }
        let trimmedCategory = rawCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = (trimmedCategory?.isEmpty == false) ? trimmedCategory : nil
        return QueueSourceDraft(
            kind: .tag,
            targetKey: tagTargetKey(name: name),
            displayName: name,
            subtitle: category,
            tagName: name,
            tagCategoryRaw: category,
            urlString: resolvedURL.absoluteString
        )
    }

    /// True when the typed text is meant as a link rather than a name.
    static func isURLInput(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.contains("://") || ["ao3.org/", "archiveofourown.org/", "www.archiveofourown.org/"]
            .contains(where: text.hasPrefix)
    }

    /// Parses a pasted AO3 author works, series, or tag link (http or https,
    /// ao3.org or archiveofourown.org, default port, with or without a scheme)
    /// into a draft. Everything else (bookmarks, an author's series list,
    /// profiles, other hosts) is `nil`.
    static func fromAO3URL(_ raw: String, fallbackTitle: String? = nil) -> QueueSourceDraft? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed) else { return nil }
        switch AO3Link(url).kind {
        case let .series(id):
            return .series(id: id, title: fallbackTitle ?? "Series \(id)")
        case let .tag(tagName):
            return .tag(name: tagName, url: AO3Client.tagWorksURL(tagName: tagName))
        case let .user(username, pseud):
            return .author(username: username, pseud: pseud, displayName: fallbackTitle)
        case .otherAO3:
            // AO3Link has no kind for an author's works listing; match it here.
            let parts = url.path(percentEncoded: true).split(separator: "/")
                .map { String($0).removingPercentEncoding ?? String($0) }
            guard parts.first == "users", parts.count == 3 || parts.count == 5,
                  !["login", "logout", "new", "password"].contains(parts[1])
            else { return nil }
            if parts.count == 3, parts[2] == "works" {
                return .author(username: parts[1], displayName: fallbackTitle)
            }
            if parts.count == 5, parts[2] == "pseuds", parts[4] == "works" {
                return .author(username: parts[1], pseud: parts[3], displayName: fallbackTitle)
            }
            return nil
        default:
            return nil
        }
    }
}

extension QueueSavedSearchLink {
    /// True for legacy saved-search links (`sourceKindRaw == nil`) and explicit
    /// `"savedSearch"` rows.
    var isSavedSearchSource: Bool {
        sourceKindRaw == nil || sourceKindRaw == QueueSourceKind.savedSearch.rawValue
    }

    var effectiveSourceKindRaw: String {
        sourceKindRaw ?? QueueSourceKind.savedSearch.rawValue
    }

    /// `nil` for unknown future source kinds so UI and networking ignore them
    /// while SwiftData and backup keep them intact.
    var knownSourceKind: QueueSourceKind? {
        if isSavedSearchSource { return .savedSearch }
        return sourceKindRaw.flatMap { QueueSourceKind(rawValue: $0) }
    }

    var isKnownSource: Bool {
        knownSourceKind != nil
    }

    var dedupKey: String {
        if isSavedSearchSource {
            let searchID = search?.id.uuidString.lowercased() ?? id.uuidString.lowercased()
            return "\(QueueSourceKind.savedSearch.rawValue)|\(searchID)"
        }
        return QueueSourceDraft.dedupKey(
            kindRaw: effectiveSourceKindRaw,
            targetKey: effectiveTargetKey,
            fallbackID: id
        )
    }

    /// `targetKey`, or the key rebuilt from the row's own fields when a
    /// restored row arrived without one.
    var effectiveTargetKey: String? {
        if let key = targetKey, !key.isEmpty { return key }
        return QueueSourceDraft.derivedTargetKey(
            kindRaw: sourceKindRaw, authorUsername: authorUsername, authorPseud: authorPseud,
            ao3SeriesID: ao3SeriesID, tagName: tagName
        )
    }

    var effectiveDisplayName: String {
        if isSavedSearchSource {
            return search?.name ?? displayName ?? ""
        }
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        switch knownSourceKind {
        case .author:
            return authorRoute?.displayName ?? authorUsername ?? ""
        case .series:
            return ao3SeriesID.map { "Series \($0)" } ?? ""
        case .tag:
            return tagName ?? ""
        case .savedSearch, nil:
            return targetKey ?? ""
        }
    }

    var effectiveSubtitle: String? {
        guard let kind = knownSourceKind else { return subtitle }
        switch kind {
        case .savedSearch:
            guard let search else { return nil }
            let labels = search.filters.summaryLabels()
            if !labels.isEmpty {
                return labels.prefix(3).map(\.text).joined(separator: " · ")
            }
            return search.filters.sort.title
        case .author:
            if let sub = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
                return sub
            }
            if let pseud = authorPseud, !pseud.isEmpty, let username = authorUsername, !username.isEmpty {
                return "Pseud of \(username)"
            }
            return "Author"
        case .series:
            if let sub = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
                return sub
            }
            return "Series"
        case .tag:
            let cat = tagCategoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cat, !cat.isEmpty {
                return "\(cat) · newest first"
            }
            return "Tag · newest first"
        }
    }

    var effectiveLastOpenedAt: Date? {
        if isSavedSearchSource { return search?.lastOpenedAt }
        return lastOpenedAt
    }

    var authorRoute: AO3AuthorRoute? {
        guard knownSourceKind == .author else { return nil }
        if let username = authorUsername,
           let route = AO3AuthorRoute(username: username, pseud: authorPseud) {
            return route
        }
        if let urlString, let url = URL(string: urlString) {
            return AO3AuthorRoute(url: url)
        }
        return nil
    }

    var seriesSummary: AO3SeriesSummary? {
        guard knownSourceKind == .series, let seriesID = ao3SeriesID, seriesID > 0,
              let url = URL(string: "https://archiveofourown.org/series/\(seriesID)")
        else { return nil }
        return AO3SeriesSummary(
            id: seriesID,
            title: effectiveDisplayName,
            creatorNames: [],
            creatorIdentities: [],
            fandoms: [],
            summary: "",
            words: nil,
            workCount: nil,
            bookmarkCount: nil,
            dateUpdated: "",
            isComplete: nil,
            isRestricted: false,
            url: url
        )
    }

    var tagWorksRequest: AO3TagWorksRequest? {
        guard knownSourceKind == .tag else { return nil }
        let name = (tagName ?? displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let resolvedURL: URL?
        if let urlString, let parsed = URL(string: urlString), QueueSourceDraft.isTagWorksURL(parsed) {
            resolvedURL = parsed
        } else {
            resolvedURL = AO3Client.tagWorksURL(tagName: name)
        }
        guard let url = resolvedURL else { return nil }
        return AO3TagWorksRequest(url: url, title: name)
    }

    /// Exact page-1 AO3 listing URL that both counting and Find More open.
    var listingURL: URL? {
        guard let kind = knownSourceKind else { return nil }
        switch kind {
        case .savedSearch:
            guard let search else { return nil }
            return AO3Client.searchURL(filters: search.filters, page: 1)
        case .author:
            return authorRoute?.contentURL(.works)
        case .series:
            guard let seriesID = ao3SeriesID, seriesID > 0,
                  let base = URL(string: "https://archiveofourown.org/series/\(seriesID)")
            else { return nil }
            return AO3Client.seriesPageURL(base, page: 1)
        case .tag:
            guard let request = tagWorksRequest else { return nil }
            return AO3Client.filteredWorksURL(
                request.url,
                filters: QueueSourceChecks.tagBaselineFilters,
                page: 1
            )
        }
    }

    /// Whether this source participates in new-result counting.
    var countsNewResults: Bool {
        guard let kind = knownSourceKind else { return false }
        switch kind {
        case .savedSearch:
            return search.map { QueueSourceChecks.countsNewResults($0.filters) } ?? false
        case .author:
            return authorRoute != nil
        case .series:
            return (ao3SeriesID ?? 0) > 0
        case .tag:
            return tagWorksRequest != nil
        }
    }

    var displayedNewCount: Int? {
        guard countsNewResults else { return nil }
        guard let count = newResultCount, count > 0 else { return nil }
        return count
    }

    var sourceDraft: QueueSourceDraft? {
        guard let kind = knownSourceKind, kind != .savedSearch else { return nil }
        guard let key = effectiveTargetKey else { return nil }
        return QueueSourceDraft(
            id: id,
            kind: kind,
            targetKey: key,
            displayName: effectiveDisplayName,
            subtitle: subtitle,
            authorUsername: authorUsername,
            authorPseud: authorPseud,
            ao3SeriesID: ao3SeriesID,
            tagName: tagName,
            tagCategoryRaw: tagCategoryRaw,
            urlString: urlString
        )
    }

    func apply(_ draft: QueueSourceDraft) {
        sourceKindRaw = draft.kind.rawValue
        targetKey = draft.targetKey
        displayName = draft.displayName
        subtitle = draft.subtitle
        authorUsername = draft.authorUsername
        authorPseud = draft.authorPseud
        ao3SeriesID = draft.ao3SeriesID
        tagName = draft.tagName
        tagCategoryRaw = draft.tagCategoryRaw
        urlString = draft.urlString
    }
}

extension ReadingQueue {
    /// Linked saved searches, sorted by display name.
    var savedSearchLinks: [QueueSavedSearchLink] {
        guard kind != .smart else { return [] }
        return searchLinks
            .filter { $0.isSavedSearchSource && $0.search != nil }
            .sorted { $0.effectiveDisplayName.localizedStandardCompare($1.effectiveDisplayName) == .orderedAscending }
    }

    /// All non-search sources stored on this queue, including unknown future kinds.
    var nonSearchSources: [QueueSavedSearchLink] {
        guard kind != .smart else { return [] }
        return searchLinks.filter { !$0.isSavedSearchSource }
    }

    /// Known non-search sources (author, series, tag) visible in the UI.
    var visibleNonSearchSources: [QueueSavedSearchLink] {
        nonSearchSources.filter(\.isKnownSource)
    }

    var authorAndSeriesSources: [QueueSavedSearchLink] {
        visibleNonSearchSources
            .filter { $0.knownSourceKind == .author || $0.knownSourceKind == .series }
            .sorted { $0.effectiveDisplayName.localizedStandardCompare($1.effectiveDisplayName) == .orderedAscending }
    }

    var tagSources: [QueueSavedSearchLink] {
        visibleNonSearchSources
            .filter { $0.knownSourceKind == .tag }
            .sorted { $0.effectiveDisplayName.localizedStandardCompare($1.effectiveDisplayName) == .orderedAscending }
    }

    /// All visible sources in the board's group order: searches, authors & series, tags.
    var allVisibleSources: [QueueSavedSearchLink] {
        savedSearchLinks + authorAndSeriesSources + tagSources
    }

    /// All visible sources eligible to count new works on queue open.
    var countableSources: [QueueSavedSearchLink] {
        allVisibleSources.filter(\.countsNewResults)
    }

    var hasVisibleSources: Bool {
        !allVisibleSources.isEmpty
    }
}
