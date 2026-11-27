import Foundation

/// Writing Studio's Comments filters.
///
/// Needs Reply is an inbox row on one of your works that you have not answered.
/// otwarchive master `452391b6` (2026-11-01) renders that state in
/// `app/views/inbox/show.html.erb`: `span.replied` when `inbox_comment.replied_to?`,
/// and a Reply link only from `can_reply_to_comment?`. Replying sets both
/// `replied_to` and `read` (`Comment#notify_parent_comment_owner` in
/// `app/models/comment.rb`). Mark Read (`InboxController#update`) sets `read`
/// only, so a read comment can still need a reply. The existing inbox parser
/// already records both flags (`AO3InboxItem.isReplied`, `canReply`).
enum StudioCommentsChip: String, CaseIterable, Identifiable, Sendable {
    case needsReply
    case unread
    case all
    case byWork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsReply: "Needs Reply"
        case .unread: "Unread"
        case .all: "All"
        case .byWork: "By Work"
        }
    }
}

/// One work's inbox comments, in the order the inbox listed them.
struct StudioCommentWorkGroup: Identifiable, Equatable, Sendable {
    let workID: Int
    let title: String
    let comments: [AO3InboxItem]

    var id: Int { workID }
}

/// Which inbox rows Writing Studio's Comments section shows.
///
/// Tag and admin-post notifications have no work id, so they stay in the full
/// AO3 Inbox ("Everything else") rather than under a work heading.
enum StudioCommentsBoard {
    static func isOnYourWork(_ item: AO3InboxItem) -> Bool {
        item.workID != nil && !item.isUnavailable
    }

    /// Answerable and not yet answered. A replied row can still show a Reply
    /// link (the template prints them independently); `isReplied` is what
    /// takes it out of Needs Reply.
    static func needsReply(_ item: AO3InboxItem) -> Bool {
        isOnYourWork(item) && item.canReply && !item.isReplied
    }

    static func needsReplyCount(_ items: [AO3InboxItem]) -> Int {
        items.count(where: needsReply)
    }

    static func unreadCount(_ items: [AO3InboxItem]) -> Int {
        items.count(where: { isOnYourWork($0) && $0.isUnread })
    }

    static func allWorkCommentsCount(_ items: [AO3InboxItem]) -> Int {
        items.count(where: isOnYourWork)
    }

    static func comments(_ items: [AO3InboxItem], chip: StudioCommentsChip) -> [AO3InboxItem] {
        let works = items.filter(isOnYourWork)
        switch chip {
        case .needsReply:
            return works.filter(needsReply)
        case .unread:
            return works.filter(\.isUnread)
        case .all, .byWork:
            return works
        }
    }

    /// Groups `items` by work, first-seen order. Callers pass the By Work set.
    static func groups(_ items: [AO3InboxItem]) -> [StudioCommentWorkGroup] {
        var order: [Int] = []
        var buckets: [Int: [AO3InboxItem]] = [:]
        var titles: [Int: String] = [:]
        for item in items {
            guard let workID = item.workID else { continue }
            if buckets[workID] == nil {
                order.append(workID)
                let title = item.workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                titles[workID] = title.isEmpty ? "Work \(workID)" : title
            }
            buckets[workID, default: []].append(item)
        }
        return order.map { workID in
            StudioCommentWorkGroup(
                workID: workID,
                title: titles[workID] ?? "Work \(workID)",
                comments: buckets[workID] ?? []
            )
        }
    }

    static func emptyMessage(chip: StudioCommentsChip, totalPages: Int) -> String {
        switch (chip, totalPages > 1) {
        case (.needsReply, true): "No comments waiting for a reply on this page."
        case (.needsReply, false): "No comments waiting for a reply."
        case (.unread, true): "No unread comments on this page."
        case (.unread, false): "No unread comments."
        case (_, true): "No comments on your works on this page."
        case (_, false): "No comments on your works."
        }
    }

    static func pageNote(currentPage: Int, totalPages: Int) -> String? {
        guard totalPages > 1 else { return nil }
        return "Page \(currentPage.formatted()) of \(totalPages.formatted()) · counts are for this page"
    }

    /// Surfaces a non-default read/replied filter left on the shared AO3 Inbox
    /// model, so Needs Reply does not quietly report 0 while the server page is
    /// filtered to Replied or Unread. Never triggers a fetch on its own.
    static func activeInboxFilterNotice(in values: [String: String]) -> String? {
        let read = values[AO3InboxPill.readField]
        let replied = values[AO3InboxPill.repliedField]
        let readFiltered = read != nil && read != "all"
        let repliedFiltered = replied != nil && replied != "all"
        guard readFiltered || repliedFiltered else { return nil }
        if let pill = AO3InboxPill.selected(in: values), pill != .all {
            return "AO3 Inbox is filtered to \(pill.title)."
        }
        return "AO3 Inbox filters are active."
    }
}

/// Pushes inside the Writing tab's stack. Owned here so Comments never adds a
/// case to a shared route enum.
enum StudioCommentsRoute: Hashable, Sendable {
    case thread(Int)
    case inbox
}
