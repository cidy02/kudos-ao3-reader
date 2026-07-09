import Foundation

/// The AO3 work context shown atop the Comments screen: title, author, fandom,
/// rating, chapters — the same fields Work Detail's own overview card shows.
/// Deliberately no cover thumbnail: most AO3 works don't have one, and Work
/// Detail's card omits it too, so this reuses that pattern rather than adding a
/// new one. Convenience inits mirror WorkDetailView's local-vs-remote sourcing
/// so every call site can build one from whatever it already has on hand.
struct AO3CommentsWorkContext: Equatable, Sendable {
    var title: String
    var authors: [String]
    var fandoms: [String] = []
    var rating: String = ""
    var chapters: String = ""

    init(
        title: String, authors: [String], fandoms: [String] = [],
        rating: String = "", chapters: String = ""
    ) {
        self.title = title
        self.authors = authors
        self.fandoms = fandoms
        self.rating = rating
        self.chapters = chapters
    }

    init(savedWork: SavedWork) {
        self.init(
            title: savedWork.title,
            authors: savedWork.author.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            fandoms: savedWork.workFandoms,
            rating: savedWork.rating,
            chapters: savedWork.chapters
        )
    }

    init(remote: AO3WorkSummary) {
        self.init(
            title: remote.title, authors: remote.authors,
            fandoms: remote.fandoms, rating: remote.rating, chapters: remote.chapters
        )
    }
}

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
    var replies: [AO3Comment] = []

    /// Permanent link to this comment's thread page on AO3.
    var threadURL: URL? {
        URL(string: "https://archiveofourown.org/comments/\(id)")
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

    /// This comment plus all descendants, depth-first (for flat rendering/search).
    var flattened: [AO3Comment] {
        [self] + replies.flatMap(\.flattened)
    }

    var descendantCount: Int {
        1 + replies.reduce(0) { $0 + $1.descendantCount }
    }
}

/// A shallow, stable-ID row used by the lazy comments list. Keeping descendants
/// out of each row prevents one visible parent from eagerly constructing and
/// diffing its entire reply tree whenever sheet/menu state changes.
struct AO3CommentRow: Identifiable, Equatable, Sendable {
    private struct ProjectionContext {
        let hasNextSibling: Bool
        let continuingAncestorDepths: [Int]
    }

    let comment: AO3Comment
    let depth: Int
    let threadRootID: Int
    /// Whether this comment has at least one direct reply. Lets the view extend
    /// the connector below this avatar without retaining the reply subtree.
    let hasReplies: Bool
    /// Whether another comment follows beside this one under the same parent.
    /// The parent connector stays open through this row when true.
    let hasNextSibling: Bool
    /// Logical ancestor depths whose lines must pass through this row to reach
    /// a later sibling. Small value-only metadata preserves branched hierarchy
    /// without putting descendant comments back into the lazy row payload.
    let continuingAncestorDepths: [Int]
    /// The final row of its top-level thread group — the card-within-a-card
    /// rendering closes the shared thread card after this row.
    var isLastInThread = false

    var id: Int { comment.id }

    static func flatten(_ comments: [AO3Comment]) -> [AO3CommentRow] {
        var result: [AO3CommentRow] = []
        for comment in comments {
            append(
                comment,
                depth: 0,
                threadRootID: comment.id,
                context: ProjectionContext(
                    hasNextSibling: false,
                    continuingAncestorDepths: []
                ),
                to: &result
            )
            if !result.isEmpty { result[result.count - 1].isLastInThread = true }
        }
        return result
    }

    private static func append(
        _ comment: AO3Comment,
        depth: Int,
        threadRootID: Int,
        context: ProjectionContext,
        to result: inout [AO3CommentRow]
    ) {
        let hasReplies = !comment.replies.isEmpty
        var shallow = comment
        shallow.replies = []
        result.append(AO3CommentRow(
            comment: shallow,
            depth: depth,
            threadRootID: threadRootID,
            hasReplies: hasReplies,
            hasNextSibling: context.hasNextSibling,
            continuingAncestorDepths: context.continuingAncestorDepths
        ))
        for (index, reply) in comment.replies.enumerated() {
            var childContinuations = context.continuingAncestorDepths
            if context.hasNextSibling, depth > 0 {
                childContinuations.append(depth - 1)
            }
            append(
                reply,
                depth: depth + 1,
                threadRootID: threadRootID,
                context: ProjectionContext(
                    hasNextSibling: index < comment.replies.count - 1,
                    continuingAncestorDepths: childContinuations
                ),
                to: &result
            )
        }
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

    var totalOnPage: Int { comments.reduce(0) { $0 + $1.descendantCount } }
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
