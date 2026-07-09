import Foundation

/// One AO3 comment, with its replies nested (AO3 renders threads as nested
/// `ol.thread` lists; see `docs/ai/COMMENTS_HANDOFF.md` for the observed markup).
/// Value type — the comments UI is read-mostly and pages are re-fetched, not
/// mutated in place.
struct AO3Comment: Identifiable, Equatable, Sendable {
    let id: Int
    var author: String
    var isGuest: Bool
    /// Site-relative profile path (`/users/<name>/pseuds/<pseud>`) for registered
    /// commenters; nil for guests.
    var userPath: String?
    /// AO3's posted timestamp, flattened to a display string ("Wed 08 Jul 2026
    /// 02:38PM UTC"). Kept as text — AO3 renders it pre-localized to UTC and the
    /// UI shows it verbatim rather than pretending to a parsed precision.
    var postedText: String = ""
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
    var replies: [AO3Comment] = []

    /// Permanent link to this comment's thread page on AO3.
    var threadURL: URL? {
        URL(string: "https://archiveofourown.org/comments/\(id)")
    }

    /// This comment plus all descendants, depth-first (for flat rendering/search).
    var flattened: [AO3Comment] {
        [self] + replies.flatMap(\.flattened)
    }
}

/// One fetched page of a work's (or chapter's) comments.
struct AO3CommentsPage: Equatable, Sendable {
    var comments: [AO3Comment] = []
    var currentPage = 1
    var totalPages = 1
    /// The work-level total from the page's stats, when present. Opportunistic —
    /// used to label chapters/counts without extra requests.
    var totalComments: Int?
    /// When this page was fetched (drives the cache TTL + offline staleness label).
    var fetchedAt = Date()

    var totalOnPage: Int { comments.reduce(0) { $0 + $1.flattened.count } }
}

/// One chapter from a work's `/navigate` index — the AO3 chapter id is what the
/// per-chapter comments URL needs (EPUB TOCs don't carry it).
struct AO3ChapterRef: Identifiable, Equatable, Sendable {
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
struct AO3CommentContext: Equatable, Hashable, Sendable {
    var workID: Int
    var chapterID: Int?
    var parentCommentID: Int?

    var isReply: Bool { parentCommentID != nil }
}
