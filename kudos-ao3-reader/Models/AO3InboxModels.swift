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
    /// AO3 explicitly rendered `Anonymous Creator`, distinct from a guest who
    /// happens to type those words as their display name.
    var isAnonymousCreator = false
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
    /// True only when AO3 rendered a Reply action for this notification.
    var canReply: Bool
    /// The exact checkbox AO3 renders inside this inbox row. Its value is the
    /// InboxComment record id, which is distinct from the feedback-comment id
    /// above on real AO3 pages; bulk writes must submit this field verbatim.
    var bulkSelectionField: AO3FormField?

    /// Strictly parsed from AO3's own "Chapter N of Work" label. This is only
    /// presentation/routing intent; the exact chapter id is resolved from the
    /// user-triggered standalone thread response rather than guessed here.
    var chapterPosition: Int? {
        guard subjectTitle.hasPrefix("Chapter "),
              let separator = subjectTitle.range(of: " of ")
        else { return nil }
        let numberStart = subjectTitle.index(subjectTitle.startIndex, offsetBy: "Chapter ".count)
        return Int(subjectTitle[numberStart..<separator.lowerBound])
    }

    var chapterIndicatorTitle: String? {
        chapterPosition.map { "Chapter \($0)" }
    }

    var workTitle: String {
        guard chapterPosition != nil, let separator = subjectTitle.range(of: " of ") else {
            return subjectTitle
        }
        return String(subjectTitle[separator.upperBound...])
    }

    func participantRole(
        workAuthors: [String],
        workAuthorIdentities: [AO3AuthorIdentity] = [],
        currentUsername: String? = nil
    ) -> AO3CommentParticipantRole {
        AO3CommentParticipantRole.resolve(
            name: commenterName,
            isGuest: isGuest,
            isAnonymousCreator: isAnonymousCreator,
            commenterUsername: commenterIdentity?.username,
            currentUsername: currentUsername,
            workAuthors: workAuthors,
            workAuthorUsernames: workAuthorIdentities.compactMap(\.username)
        )
    }
}

/// One of AO3's own inbox mass-edit submit buttons. The field name and value are
/// parsed from the loaded form; this enum only gives the native UI stable intent.
nonisolated enum AO3InboxBulkAction: String, CaseIterable, Hashable, Sendable {
    case markRead
    case markUnread
    case delete

    var label: String {
        switch self {
        case .markRead: "Mark Read"
        case .markUnread: "Mark Unread"
        case .delete: "Delete From Inbox"
        }
    }

    var successMessage: String {
        switch self {
        case .markRead: "Marked as read."
        case .markUnread: "Marked as unread."
        case .delete: "Removed from your AO3 inbox."
        }
    }
}

/// AO3's `form#inbox-form`, parsed rather than reconstructed. Hidden inputs
/// include Rails' method override and any server-side values the form requires.
nonisolated struct AO3InboxBulkForm: Hashable {
    let actionURL: URL
    let htmlMethod: String
    let httpMethodOverride: String?
    let csrfToken: String
    let hiddenFields: [AO3FormField]
    let checkboxFieldName: String
    let actionFields: [AO3InboxBulkAction: AO3FormField]

    /// Produces the exact form body for a current-page selection. nil means the
    /// loaded page did not provide every required field, so the caller must not
    /// guess or submit a partial action.
    func parameters(
        for items: [AO3InboxItem],
        action: AO3InboxBulkAction
    ) -> [(String, String)]? {
        guard let actionField = actionFields[action], !items.isEmpty else { return nil }
        let selections = items.compactMap(\.bulkSelectionField)
        guard selections.count == items.count,
              selections.allSatisfy({ $0.name == checkboxFieldName })
        else { return nil }

        var fields = hiddenFields.map { ($0.name, $0.value) }
        if !fields.contains(where: { $0.0 == "authenticity_token" }) {
            fields.insert(("authenticity_token", csrfToken), at: 0)
        }
        fields.append(contentsOf: selections.map { ($0.name, $0.value) })
        fields.append((actionField.name, actionField.value))
        return fields
    }
}

/// One option rendered by AO3's Inbox filter form. Both label and value come
/// directly from the loaded radio input and its associated label.
nonisolated struct AO3InboxFilterOption: Identifiable, Hashable, Sendable {
    let value: String
    let label: String
    let isSelected: Bool

    var id: String { value }
}

/// A radio-input group from AO3's Inbox filter form (read, replied-to, or date).
nonisolated struct AO3InboxFilterField: Identifiable, Hashable, Sendable {
    let name: String
    let title: String
    let options: [AO3InboxFilterOption]

    var id: String { name }

    var selectedValue: String? {
        options.first(where: \.isSelected)?.value ?? options.first?.value
    }
}

/// AO3's GET filter form. Query names and allowed values are scraped from the
/// form, so a markup change fails closed instead of creating guessed queries.
nonisolated struct AO3InboxFilterForm: Hashable {
    let actionURL: URL
    let hiddenFields: [AO3FormField]
    let fields: [AO3InboxFilterField]

    var selectedValues: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.compactMap { field in
            field.selectedValue.map { (field.name, $0) }
        })
    }

    /// Builds AO3's own GET URL for the selected filters and requested page.
    /// Page 1 omits `page`, matching the archive's paginator URLs.
    func url(values: [String: String], page: Int) -> URL? {
        guard var components = URLComponents(url: actionURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let fieldNames = Set(fields.map(\.name))
        let removedNames = fieldNames.union(["page"])
        var queryItems = (components.queryItems ?? []).filter { !removedNames.contains($0.name) }
        queryItems.append(contentsOf: hiddenFields
            .filter { $0.name != "page" }
            .map { URLQueryItem(name: $0.name, value: $0.value) })
        for field in fields {
            if let value = values[field.name] ?? field.selectedValue {
                queryItems.append(URLQueryItem(name: field.name, value: value))
            }
        }
        if page > 1 {
            queryItems.append(URLQueryItem(name: "page", value: String(page)))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }
}

/// One page of the AO3 Inbox, plus the exact totals AO3 prints in the page
/// heading ("My Inbox (12 comments, 3 unread)") when they could be read.
nonisolated struct AO3InboxPage {
    var items: [AO3InboxItem]
    var currentPage: Int
    var totalPages: Int
    var totalComments: Int?
    var unreadCount: Int?
    /// nil when the page still renders notifications but AO3's bulk form is
    /// incomplete or unrecognized; native writes then remain unavailable.
    var bulkForm: AO3InboxBulkForm?
    /// nil when AO3's filter form cannot be parsed without guessing its fields.
    var filterForm: AO3InboxFilterForm?
}
