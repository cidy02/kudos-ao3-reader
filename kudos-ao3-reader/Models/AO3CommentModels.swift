import Foundation

/// The role chip shown beside a commenter's name across Comments and Inbox.
/// "Author" means the creator of the work being discussed; "User" is any
/// other registered AO3 account, and "Guest" is an unregistered commenter.
nonisolated enum AO3CommentParticipantRole: String, Equatable, Sendable {
    case me = "Me"
    case author = "Author"
    case user = "User"
    case guest = "Guest"

    static func resolve(
        name: String,
        isGuest: Bool,
        isAnonymousCreator: Bool = false,
        commenterUsername: String? = nil,
        currentUsername: String? = nil,
        workAuthors: [String],
        workAuthorUsernames: [String] = []
    ) -> AO3CommentParticipantRole {
        // Compare AO3 account usernames, not display pseud names: a user may
        // comment under any of their pseuds. "Me" intentionally wins over
        // "Author" when the signed-in creator is viewing their own comment.
        if let commenterUsername = normalized(commenterUsername),
           let currentUsername = normalized(currentUsername),
           commenterUsername.localizedCaseInsensitiveCompare(currentUsername) == .orderedSame {
            return .me
        }
        // AO3 only emits this state when the work creator commented
        // anonymously, so it remains an author even though no profile resolves.
        if isAnonymousCreator { return .author }
        // Guest display names and registered pseud names are not globally
        // unique. A guest can never become Author via name-only fallback.
        if isGuest { return .guest }
        // When both sides expose canonical account identities, they are
        // authoritative: two different accounts may use the same pseud name.
        if let commenterUsername = normalized(commenterUsername),
           !workAuthorUsernames.isEmpty {
            return workAuthorUsernames.contains(where: {
                $0.localizedCaseInsensitiveCompare(commenterUsername) == .orderedSame
            }) ? .author : .user
        }
        if workAuthors.contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(
                        name.trimmingCharacters(in: .whitespacesAndNewlines)
                    ) == .orderedSame
            }) {
            return .author
        }
        return .user
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

/// The AO3 work context shown atop the Comments screen: title, author, fandom,
/// rating, chapters — the same fields Work Detail's own overview card shows.
/// Deliberately no cover thumbnail: most AO3 works don't have one, and Work
/// Detail's card omits it too, so this reuses that pattern rather than adding a
/// new one. Convenience inits mirror WorkDetailView's local-vs-remote sourcing
/// so every call site can build one from whatever it already has on hand.
nonisolated struct AO3CommentsWorkContext: Hashable, Sendable {
    var title: String
    var authors: [String]
    var authorIdentities: [AO3AuthorIdentity]
    var fandoms: [String] = []
    var rating: String = ""
    var chapters: String = ""

    init(
        title: String, authors: [String], authorIdentities: [AO3AuthorIdentity] = [],
        fandoms: [String] = [],
        rating: String = "", chapters: String = ""
    ) {
        self.title = title
        self.authors = authors
        self.authorIdentities = authorIdentities
        self.fandoms = fandoms
        self.rating = rating
        self.chapters = chapters
    }

    init(savedWork: SavedWork) {
        self.init(
            title: savedWork.title,
            // Falls back to splitting the comma-joined `author` string (as every
            // caller did before verifiedAuthorIdentities existed) whenever that
            // enrichment hasn't landed yet — a freshly-imported EPUB, or a work AO3
            // stopped returning tag groups for. Without the split, a co-author's own
            // comment stops matching `isByWorkAuthor`'s per-name comparison and
            // silently loses its "Author" badge.
            authors: savedWork.verifiedAuthorIdentities.isEmpty
                ? savedWork.author.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                : savedWork.verifiedAuthorIdentities.map(\.displayName),
            authorIdentities: savedWork.verifiedAuthorIdentities,
            fandoms: savedWork.workFandoms,
            rating: savedWork.rating,
            chapters: savedWork.chapters
        )
    }

    init(remote: AO3WorkSummary) {
        self.init(
            title: remote.title,
            authors: remote.authors,
            authorIdentities: remote.authorIdentities,
            fandoms: remote.fandoms, rating: remote.rating, chapters: remote.chapters
        )
    }

    init(metadata: AO3WorkMetadata) {
        self.init(
            title: metadata.title,
            authors: metadata.authors.isEmpty
                ? metadata.authorIdentities.map(\.displayName) : metadata.authors,
            authorIdentities: metadata.authorIdentities,
            fandoms: metadata.fandoms,
            rating: metadata.rating,
            chapters: metadata.chapters
        )
    }

    /// Keeps already-known fields when an authenticated work response is sparse
    /// (for example a restricted work AO3 no longer exposes to this session).
    /// Creator identity follows the same rule as the visible summary fields so a
    /// failed optional enrichment can never make an existing Author badge worse.
    func merging(_ newer: AO3CommentsWorkContext) -> AO3CommentsWorkContext {
        AO3CommentsWorkContext(
            title: newer.title.isEmpty ? title : newer.title,
            authors: newer.authors.isEmpty ? authors : newer.authors,
            authorIdentities: newer.authorIdentities.isEmpty
                ? authorIdentities : newer.authorIdentities,
            fandoms: newer.fandoms.isEmpty ? fandoms : newer.fandoms,
            rating: newer.rating.isEmpty ? rating : newer.rating,
            chapters: newer.chapters.isEmpty ? chapters : newer.chapters
        )
    }

    /// The work-summary card's canonical fields. Creator-only cache entries are
    /// useful for badges but still need one work-page enrichment before the card
    /// can accurately show the same rating/fandom/chapter metadata as Work Detail.
    var needsSummaryEnrichment: Bool {
        let hasCreator = !authors.isEmpty || !authorIdentities.isEmpty
        return title.isEmpty || !hasCreator || fandoms.isEmpty || rating.isEmpty || chapters.isEmpty
    }
}

/// One AO3 comment, with its replies nested (AO3 renders threads as nested
/// `ol.thread` lists; see `docs/ai/COMMENTS_HANDOFF.md` for the observed markup).
/// Value type — the comments UI is read-mostly and pages are re-fetched, not
/// mutated in place.
nonisolated struct AO3Comment: Identifiable, Equatable, Sendable {
    let id: Int
    var author: String
    var isGuest: Bool
    /// AO3 explicitly rendered its protected anonymous-creator identity. This
    /// must not be inferred from a guest choosing the same display string.
    var isAnonymousCreator = false
    /// Site-relative profile path (`/users/<name>/pseuds/<pseud>`) for registered
    /// commenters; nil for guests.
    var userPath: String?
    /// User icon URL already present in the fetched comment markup. The comments
    /// UI never visits a profile page to discover one.
    var avatarURL: URL?
    /// AO3's posted timestamp, flattened to a display string ("Wed 08 Jul 2026
    /// 02:38PM UTC"). Kept as a fallback if Foundation cannot parse an
    /// unexpected AO3 timestamp shape.
    var postedText: String = ""
    /// Parsed instant for relative/local display. This is presentation-only
    /// data from the same fetched markup; it does not trigger another request.
    var postedAt: Date?
    /// The chapter this comment was left on, when AO3 shows one (multichapter
    /// works viewed whole; single-chapter works omit it).
    var chapterID: Int?
    var chapterLabel: String?
    /// Plain-text body; paragraphs joined with blank lines. AO3 allows limited
    /// HTML in comments — v1 renders text only (links/emphasis flattened).
    var bodyText: String = ""
    /// AO3 exposed a Reply action for this comment in this session.
    var canReply: Bool = false
    /// Present only when AO3 rendered an Edit/Delete action for this session
    /// (i.e. the viewer's own comment). Site-relative, straight from the page —
    /// the UI must never synthesize these.
    var editPath: String?
    var deletePath: String?
    /// AO3-rendered thread actions. Kept parse-gated so the UI never invents an
    /// action AO3 did not expose for this comment/context.
    var threadPath: String?
    var parentThreadPath: String?
    /// A deleted comment whose replies AO3 kept: the placeholder `li` renders
    /// only "(Previous comment deleted.)" — no byline, body, or actions — but
    /// must stay in the tree so its surviving replies hang under the right
    /// parent instead of grafting onto a sibling.
    var isDeleted = false
    var replies: [AO3Comment] = []

    /// Permanent link to this comment's thread page on AO3.
    var threadURL: URL? {
        URL(string: "https://archiveofourown.org/comments/\(id)")
    }

    /// Native profile route for this comment's author when navigable — registered
    /// (or orphan) account with a resolvable `userPath`, not a guest, and not a
    /// deleted tombstone. Single source of truth for avatar + byline entry points.
    var profileRoute: AO3AuthorRoute? {
        guard !isDeleted, !isGuest,
              let path = userPath,
              let identity = AO3AuthorIdentity(displayName: author, href: path)
        else { return nil }
        return identity.route
    }

    var threadActionURL: URL? { Self.ao3URL(for: threadPath) }
    var parentThreadURL: URL? { Self.ao3URL(for: parentThreadPath) }

    /// The immediate parent's id, parsed from AO3's own "Parent Thread" link —
    /// nil for a top-level comment, or when AO3 didn't render the link. Drives
    /// scrolling to the parent natively (`CommentsView`'s focus-thread action)
    /// rather than opening AO3's page for it.
    var parentCommentID: Int? {
        guard let path = parentThreadPath, let last = path.split(separator: "/").last else { return nil }
        return Int(last)
    }

    nonisolated static func ao3URL(for path: String?) -> URL? {
        guard let path, !path.isEmpty,
              let base = URL(string: "https://archiveofourown.org") else {
            return nil
        }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    /// AO3's own bundled skin artwork, served as the icon for any account that
    /// hasn't uploaded one. It's the AO3 logo — a trademark we must not present as
    /// someone's profile picture. Uploaded icons come from Rails ActiveStorage or
    /// the OTW icon bucket; nothing under `/images/skins/` is ever a user's own.
    nonisolated static func isDefaultAO3Icon(_ url: URL) -> Bool {
        guard let host = url.host(),
              host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org") else {
            return false
        }
        return url.path().hasPrefix("/images/skins/")
    }

    /// The user icon AO3 rendered, or nil when AO3 fell back to its own default —
    /// callers then show the app's generic placeholder instead of the AO3 logo.
    nonisolated static func avatarURL(forIconSource source: String?) -> URL? {
        guard let url = ao3URL(for: source), !isDefaultAO3Icon(url) else { return nil }
        return url
    }

    /// This comment plus all descendants, depth-first (for flat rendering/search).
    /// Iterative: AO3 doesn't cap reply nesting, so a recursive walk costs one stack
    /// frame per level, and `[self] + replies.flatMap(...)` recopied the growing
    /// tail at every level (O(depth²) on a long reply-to-reply chain).
    var flattened: [AO3Comment] {
        var result: [AO3Comment] = []
        var stack: [AO3Comment] = [self]
        while let node = stack.popLast() {
            result.append(node)
            stack.append(contentsOf: node.replies.reversed())
        }
        return result
    }

    /// True when `commentID` is this comment or any descendant. Short-circuits and
    /// builds no result array, unlike scanning `flattened`.
    func contains(commentID: Int) -> Bool {
        var stack: [AO3Comment] = [self]
        while let node = stack.popLast() {
            if node.id == commentID { return true }
            stack.append(contentsOf: node.replies)
        }
        return false
    }

    var descendantCount: Int {
        var count = 0
        var stack: [AO3Comment] = [self]
        while let node = stack.popLast() {
            count += 1
            stack.append(contentsOf: node.replies)
        }
        return count
    }
}

/// One fetched page of a work's (or chapter's) comments.
nonisolated struct AO3CommentsPage: Equatable, Sendable {
    var comments: [AO3Comment] = []
    var currentPage = 1
    var totalPages = 1
    /// The work-level total from the page's stats, when present. Opportunistic —
    /// used to label chapters/counts without extra requests.
    var totalComments: Int?
    /// Canonical work creators parsed from the work/chapter page surrounding the
    /// comments. Standalone `/comments/<id>` pages omit this byline.
    var workAuthors: [String] = []
    var workAuthorIdentities: [AO3AuthorIdentity] = []
    /// When this page was fetched (drives the cache TTL + offline staleness label).
    var fetchedAt = Date()

    var totalOnPage: Int { comments.reduce(0) { $0 + $1.descendantCount } }
}

/// One chapter from a work's `/navigate` index — the AO3 chapter id is what the
/// per-chapter comments URL needs (EPUB TOCs don't carry it).
nonisolated struct AO3ChapterRef: Identifiable, Equatable, Sendable {
    /// AO3's chapter id (`/works/<wid>/chapters/<id>`).
    let id: Int
    /// 1-based position in the work.
    var position: Int
    var title: String
    var dateText: String = ""

    /// "Chapter 3 · Title" (or just "Chapter 3" when AO3's default title repeats).
    var displayName: String {
        let generic = "Chapter \(position)"
        if title.isEmpty || title == generic { return generic }
        return "\(generic) · \(title)"
    }
}

/// Where a comment is being written: which work, optionally which chapter, and
/// (for replies) which parent comment. This is the identity the duplicate-post
/// guard keys on, alongside the normalized body.
nonisolated struct AO3CommentContext: Equatable, Hashable, Sendable {
    var workID: Int
    var chapterID: Int?
    var parentCommentID: Int?

    var isReply: Bool { parentCommentID != nil }
}
