import Foundation

/// One native author destination. AO3 work bylines point at pseuds, while the
/// account dashboard uses the username alone; retaining both prevents a tapped
/// pseud from silently collapsing to the account's default name.
nonisolated struct AO3AuthorRoute: Hashable, Sendable, Codable, Identifiable {
    enum Content: String, Hashable, Sendable, Codable {
        case works
        case series
        case bookmarks
    }

    let username: String
    let pseud: String?

    var id: String {
        [username, pseud ?? "*"].joined(separator: "|")
    }

    init?(username: String, pseud: String? = nil) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pseud = pseud?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, pseud?.isEmpty != true else { return nil }
        self.username = username
        self.pseud = pseud
    }

    init?(url: URL) {
        guard Self.isAO3URL(url) else { return nil }
        let parts = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.removingPercentEncoding ?? $0 }
        guard parts.count >= 2, parts[0] == "users" else { return nil }

        let username = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let reserved = ["login", "logout", "new", "password"]
        guard !username.isEmpty, !reserved.contains(username.lowercased()) else { return nil }

        if parts.count == 2 {
            self.init(username: username)
            return
        }

        if parts[2] == "pseuds" {
            if parts.count == 3 {
                self.init(username: username)
            } else if parts.count == 4
                        || (parts.count == 5
                            && ["works", "series", "bookmarks"].contains(parts[4])) {
                self.init(username: username, pseud: parts[3])
            } else {
                return nil
            }
            return
        }

        // Only routes that are genuinely author/profile destinations should be
        // captured centrally. Account-private pages such as readings/preferences
        // keep their existing web handling.
        guard parts.count == 3,
              ["profile", "works", "series", "bookmarks"].contains(parts[2]) else {
            return nil
        }
        self.init(username: username)
    }

    init?(path: String) {
        guard let url = URL(string: path, relativeTo: Self.siteURL)?.absoluteURL else {
            return nil
        }
        self.init(url: url)
    }

    var displayName: String {
        pseud ?? username
    }

    var isOrphanAccount: Bool {
        username.caseInsensitiveCompare("orphan_account") == .orderedSame
    }

    var userURL: URL {
        Self.makeURL(segments: ["users", username])
    }

    var pseudURL: URL? {
        pseud.map { Self.makeURL(segments: ["users", username, "pseuds", $0]) }
    }

    var dashboardURL: URL {
        pseudURL ?? userURL
    }

    var profileURL: URL {
        Self.makeURL(segments: ["users", username, "profile"])
    }

    func contentURL(_ content: Content, page: Int = 1) -> URL {
        var segments = ["users", username]
        if let pseud {
            segments += ["pseuds", pseud]
        }
        segments.append(content.rawValue)
        return Self.makeURL(
            segments: segments,
            queryItems: page > 1 ? [URLQueryItem(name: "page", value: String(page))] : []
        )
    }

    static func isAO3URL(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased()
        else { return false }
        return host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org")
    }

    private static let siteURL = URL(string: "https://archiveofourown.org")!

    private static func makeURL(
        segments: [String],
        queryItems: [URLQueryItem] = []
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "archiveofourown.org"
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        components.percentEncodedPath = "/" + segments.map {
            $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0
        }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url ?? siteURL
    }
}

/// Verified creator identity parsed from an AO3 author link. Plain display strings
/// are deliberately not accepted as enough information to construct a profile URL.
nonisolated struct AO3AuthorIdentity: Hashable, Sendable, Codable, Identifiable {
    enum Kind: String, Hashable, Sendable, Codable {
        case registered
        case orphaned
        case anonymous
        case deleted
    }

    let username: String?
    let pseud: String?
    let displayName: String
    let userURL: URL?
    let pseudURL: URL?
    var avatarURL: URL?
    var userID: Int?
    let kind: Kind

    var id: String {
        route?.id ?? "\(kind.rawValue)|\(displayName)"
    }

    var route: AO3AuthorRoute? {
        guard kind == .registered || kind == .orphaned, let username else { return nil }
        return AO3AuthorRoute(username: username, pseud: pseud)
    }

    var isNavigable: Bool {
        route != nil
    }

    init(
        route: AO3AuthorRoute,
        displayName: String? = nil,
        avatarURL: URL? = nil,
        userID: Int? = nil
    ) {
        username = route.username
        pseud = route.pseud
        self.displayName = displayName ?? route.displayName
        userURL = route.userURL
        pseudURL = route.pseudURL
        self.avatarURL = avatarURL
        self.userID = userID
        kind = route.isOrphanAccount ? .orphaned : .registered
    }

    init?(displayName: String, href: String) {
        guard let route = AO3AuthorRoute(path: href) else { return nil }
        self.init(route: route, displayName: displayName)
    }

    static func nonNavigable(_ displayName: String, kind: Kind) -> Self {
        Self(
            username: nil,
            pseud: nil,
            displayName: displayName,
            userURL: nil,
            pseudURL: nil,
            avatarURL: nil,
            userID: nil,
            kind: kind
        )
    }

    private init(
        username: String?, pseud: String?, displayName: String,
        userURL: URL?, pseudURL: URL?, avatarURL: URL?, userID: Int?, kind: Kind
    ) {
        self.username = username
        self.pseud = pseud
        self.displayName = displayName
        self.userURL = userURL
        self.pseudURL = pseudURL
        self.avatarURL = avatarURL
        self.userID = userID
        self.kind = kind
    }
}

nonisolated enum AO3AuthorIdentityCodec {
    static func encode(_ identities: [AO3AuthorIdentity]) -> String {
        guard !identities.isEmpty,
              let data = try? JSONEncoder().encode(identities)
        else { return "" }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    static func decode(_ value: String) -> [AO3AuthorIdentity] {
        guard let data = value.data(using: .utf8), !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([AO3AuthorIdentity].self, from: data)) ?? []
    }
}

nonisolated enum AO3AuthorProfileTab: String, CaseIterable, Hashable, Identifiable {
    case works = "Works"
    case series = "Series"
    case bookmarks = "Bookmarks"
    case about = "About"

    var id: String { rawValue }
}

nonisolated struct AO3AuthorPseud: Identifiable, Hashable {
    let name: String
    let route: AO3AuthorRoute
    var avatarURL: URL?

    var id: String { route.id }
}

nonisolated struct AO3AuthorFandom: Identifiable, Hashable {
    let name: String
    let workCount: Int?
    let url: URL?

    var id: String { name }
}

nonisolated struct AO3AuthorWebAction: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case block
        case mute
        case profile
        case pseuds
        case works
        case preferences
        case dashboard
        case other
    }

    let label: String
    let url: URL
    let kind: Kind

    var id: String { "\(kind.rawValue)|\(url.absoluteString)" }
}

nonisolated struct AO3FormField: Hashable {
    let name: String
    let value: String
}

nonisolated struct AO3AuthorSubscriptionForm: Hashable {
    let label: String
    let actionURL: URL
    let fields: [AO3FormField]
    let csrfToken: String
    let referer: URL

    var isSubscribed: Bool {
        label.localizedCaseInsensitiveContains("unsubscribe")
            || fields.contains { $0.name == "_method" && $0.value.lowercased() == "delete" }
    }
}

/// Block / mute kind inferred from the confirm form (same role as
/// `AO3AuthorSubscriptionForm.isSubscribed` for subscribe/unsubscribe).
nonisolated enum AO3AuthorModerationKind: String, Hashable, Sendable {
    case block
    case unblock
    case mute
    case unmute

    init?(webAction: AO3AuthorWebAction.Kind, isUndo: Bool) {
        switch (webAction, isUndo) {
        case (.block, false): self = .block
        case (.block, true): self = .unblock
        case (.mute, false): self = .mute
        case (.mute, true): self = .unmute
        default: return nil
        }
    }

    var isUndo: Bool {
        switch self {
        case .unblock, .unmute: true
        case .block, .mute: false
        }
    }

    var successMessage: String {
        switch self {
        case .block: "Blocked."
        case .unblock: "Unblocked."
        case .mute: "Muted."
        case .unmute: "Unmuted."
        }
    }

    var systemImage: String {
        switch self {
        case .block: "hand.raised"
        case .unblock: "hand.raised.slash"
        case .mute: "speaker.slash"
        case .unmute: "speaker.wave.2"
        }
    }
}

/// Scraped block/mute confirm form — same shape as `AO3AuthorSubscriptionForm`
/// (action URL, hidden fields, CSRF, referer) plus alert title/message text.
nonisolated struct AO3AuthorModerationForm: Hashable, Identifiable, Sendable {
    let kind: AO3AuthorModerationKind
    let targetUsername: String
    let title: String
    /// AO3 caution notice as plain alert text (paragraphs + "• " bullets).
    let message: String
    let submitLabel: String
    let cancelLabel: String
    let actionURL: URL
    let fields: [AO3FormField]
    let csrfToken: String
    let referer: URL

    var id: String {
        "\(kind.rawValue)|\(targetUsername)|\(actionURL.absoluteString)"
    }
}

nonisolated struct AO3AuthorHeader: Hashable {
    var identity: AO3AuthorIdentity
    var pseuds: [AO3AuthorPseud]
    var fandoms: [AO3AuthorFandom]
    var subscriptionForm: AO3AuthorSubscriptionForm?
    var actions: [AO3AuthorWebAction]
}

nonisolated struct AO3RichText: Hashable {
    struct Block: Hashable, Identifiable {
        enum Kind: Hashable { case paragraph, listItem }

        let kind: Kind
        let runs: [Run]
        var id: Int
    }

    struct Run: Hashable {
        let text: String
        let isBold: Bool
        let isItalic: Bool
        let link: URL?
    }

    var blocks: [Block] = []

    var isEmpty: Bool {
        blocks.allSatisfy { block in
            block.runs.allSatisfy {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
}

nonisolated struct AO3AuthorAbout: Hashable {
    var profileTitle: String = ""
    var bio = AO3RichText()
    var pseuds: [AO3AuthorPseud] = []
    var joinedDate: String = ""
    var userID: Int?
    var actions: [AO3AuthorWebAction] = []
}

nonisolated struct AO3SeriesSummary: Identifiable, Hashable {
    let id: Int
    var title: String
    var creatorNames: [String]
    var creatorIdentities: [AO3AuthorIdentity]
    var fandoms: [String]
    var summary: String
    var words: Int?
    var workCount: Int?
    var dateUpdated: String
    var isComplete: Bool?
    var url: URL
}

nonisolated struct AO3SeriesPage {
    var series: [AO3SeriesSummary]
    var currentPage: Int
    var totalPages: Int
}

nonisolated struct AO3AuthorBookmark: Identifiable, Hashable {
    let id: Int
    var work: AO3WorkSummary
    var notes: AO3RichText
    var tags: [String]
    var collections: [String]
    var isRecommendation: Bool
    var isPrivate: Bool
    var date: String
}

nonisolated struct AO3AuthorBookmarksPage {
    var bookmarks: [AO3AuthorBookmark]
    var currentPage: Int
    var totalPages: Int
}
