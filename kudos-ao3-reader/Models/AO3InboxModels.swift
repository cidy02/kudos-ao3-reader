import Foundation

/// One entry in the signed-in user's AO3 Inbox — a comment notification (a new
/// comment on the user's work, or a reply to a comment they posted). Flatter than
/// `AO3Comment` by design: the inbox lists notification summaries, not threads.
nonisolated struct AO3InboxItem: Identifiable, Hashable {
    /// AO3's feedback-comment id (the `feedback_comment_<id>` DOM id) — also the
    /// id of the comment itself, so it can anchor a thread jump.
    let id: Int
    var commenterName: String
    /// True for guest comments (a plain name, no account).
    var isGuest: Bool
    /// Navigable identity when the commenter is a registered pseud.
    var commenterIdentity: AO3AuthorIdentity?
    var avatarURL: URL?
    /// What was commented on, as AO3 titled it (e.g. "Work Title" or
    /// "Chapter 3 of Work Title" — or a tag/admin-post name).
    var subjectTitle: String
    /// AO3's own link for the entry (`/works/<id>/comments/<id>`, or the tag /
    /// admin-post equivalent) — the web fallback when there's no work to open.
    var subjectURL: URL?
    /// Parsed from `subjectURL` when the comment is on a work; nil for tag and
    /// admin-post comments (those fall back to the website).
    var workID: Int?
    /// Plain-text excerpt of the comment body.
    var excerpt: String
    /// AO3's relative timestamp text, as rendered ("3 days ago").
    var postedAgo: String
    var isUnread: Bool
    /// True when AO3 marks the comment as already replied to.
    var isReplied: Bool
}

/// One page of the AO3 Inbox, plus the exact totals AO3 prints in the page
/// heading ("My Inbox (12 comments, 3 unread)") when they could be read.
nonisolated struct AO3InboxPage {
    var items: [AO3InboxItem]
    var currentPage: Int
    var totalPages: Int
    var totalComments: Int?
    var unreadCount: Int?
}
