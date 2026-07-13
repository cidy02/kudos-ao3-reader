import Foundation
import SwiftSoup

// The signed-in user's AO3 Inbox (`/users/<name>/inbox`) — AO3's own feed of
// comment notifications (new comments on the user's works, replies to comments
// they posted). Selectors mirror otwarchive's
// `app/views/inbox/show.html.erb` + `_inbox_comment_contents.html.erb`:
// items are `li#feedback_comment_<id>` (classed read/unread) inside
// `ol.comment.index.group`, each with an `h4.heading.byline` (commenter link +
// commentable link + `span.posted.datetime`), a `div.icon` avatar, and a
// `blockquote.userstuff` body.
extension AO3Client {

    /// The URL of a user's AO3 Inbox, paginated. Always the signed-in user's own —
    /// fetch it only with an authenticated request.
    static func inboxURL(username: String, page: Int) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/inbox"
        if page > 1 { components?.queryItems = [URLQueryItem(name: "page", value: String(page))] }
        return components?.url
    }

    /// Parses an Inbox page into notification entries + pagination + the heading's
    /// exact totals. An inbox with no comments is a recognized-empty page (the
    /// heading/filter form still render); a page with neither items nor those
    /// landmarks is parser drift and throws `AO3Error.parse` — never a fabricated
    /// empty inbox.
    static func parseInboxPage(_ html: String, page: Int) throws -> AO3InboxPage {
        let doc = try SwiftSoup.parse(html)

        let itemElements = try doc.select("li[id^=feedback_comment_]").array()
        if itemElements.isEmpty {
            // Distinguish "genuinely empty inbox" from "unrecognized markup".
            let heading = (try? doc.select("h2.heading").first()?.text()) ?? ""
            let hasFilters = (try? doc.select("form#inbox-filters").first()) != nil
            guard heading.localizedCaseInsensitiveContains("inbox") || hasFilters else {
                throw AO3Error.parse
            }
        }

        // Skip a malformed entry rather than failing the page (same convention as
        // the works-list parsers).
        let items = itemElements.compactMap { try? Self.parseInboxItem($0) }
        // The display page is still useful if AO3 changes an optional management
        // form, but native controls must fail closed rather than inventing fields.
        let bulkForm = Self.parseInboxBulkForm(in: doc, items: items)
        let filterForm = Self.parseInboxFilterForm(in: doc)

        var totalPages = page
        for li in try doc.select("ol.pagination li").array() {
            if let value = try Int((li.text()).trimmingCharacters(in: .whitespaces)), value > totalPages {
                totalPages = value
            }
        }

        // "My Inbox (12 comments, 3 unread)" — take the first two integers in the
        // heading. Absent/unreadable counts stay nil (they're a bonus, not load-bearing).
        var totalComments: Int?
        var unreadCount: Int?
        if let heading = try doc.select("h2.heading").first()?.text() {
            let numbers = Self.integers(in: heading)
            if numbers.count >= 2 {
                totalComments = numbers[0]
                unreadCount = numbers[1]
            }
        }

        return AO3InboxPage(
            items: items,
            currentPage: page,
            totalPages: totalPages,
            totalComments: totalComments,
            unreadCount: unreadCount,
            bulkForm: bulkForm,
            filterForm: filterForm
        )
    }

    private static func parseInboxItem(_ li: Element) throws -> AO3InboxItem {
        guard let id = Int(li.id().replacingOccurrences(of: "feedback_comment_", with: "")),
              let byline = try li.select("h4.heading.byline").first()
        else { throw AO3Error.parse }

        // The commentable ("on …") link is the byline link whose path carries
        // /comments/ (work_comment_path & friends); the commenter link, when the
        // commenter is registered, is the remaining /users/ link.
        var subjectTitle = ""
        var subjectURL: URL?
        var workID: Int?
        var commenterIdentity: AO3AuthorIdentity?
        var commenterName = ""

        for link in try byline.select("a").array() {
            let href = try link.attr("href")
            if href.contains("/comments/") {
                subjectTitle = try link.text()
                subjectURL = URL(string: href, relativeTo: URL(string: "https://archiveofourown.org"))?
                    .absoluteURL
                workID = Self.workID(inPath: href)
            } else if href.contains("/users/"), commenterIdentity == nil {
                let name = try link.text()
                commenterIdentity = AO3AuthorIdentity(displayName: name, href: href)
                commenterName = name
            }
        }

        // Guest comments render the name as a plain span with a "(Guest)" role
        // suffix; anonymous-creator entries have no commenter link either.
        var isGuest = false
        var isAnonymousCreator = false
        if commenterIdentity == nil {
            let role = (try? byline.select("span.role").first()?.text()) ?? ""
            isGuest = role.localizedCaseInsensitiveContains("guest")
            // First direct span that isn't the role/status/datetime is the name.
            for span in try byline.select("span").array() {
                let classNames = (try? span.className()) ?? ""
                if classNames.contains("role") || classNames.contains("status")
                    || classNames.contains("datetime") { continue }
                let text = try span.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    commenterName = text
                    break
                }
            }
            if commenterName.isEmpty {
                // "Anonymous Creator on <work>" puts the name in the byline's own
                // text rather than a child element.
                let full = try byline.text()
                if full.localizedCaseInsensitiveContains("anonymous creator") {
                    commenterName = "Anonymous Creator"
                    isAnonymousCreator = true
                }
            }
        }
        if commenterName.isEmpty { commenterName = "Unknown" }

        let postedAgo = (try? li.select("span.posted.datetime").first()?.text()) ?? ""
        let excerpt = (try? li.select("blockquote.userstuff").first()?.text())?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var avatarURL: URL?
        if let src = try li.select("div.icon img").first()?.attr("src"), !src.isEmpty {
            avatarURL = URL(string: src, relativeTo: URL(string: "https://archiveofourown.org"))?
                .absoluteURL
        }

        let isUnread = li.hasClass("unread")
        let isReplied = (try? li.select("ul.actions span.replied").first()) != nil
        let canReply = ((try? li.select("ul.actions a").array()) ?? []).contains { link in
            let label = ((try? link.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return label.localizedCaseInsensitiveCompare("Reply") == .orderedSame
        }
        let bulkSelectionField: AO3FormField?
        if let checkbox = try li.select("input[type=checkbox][name][value]").first(),
           let name = try? checkbox.attr("name"), !name.isEmpty,
           let value = try? checkbox.attr("value"), !value.isEmpty {
            bulkSelectionField = AO3FormField(name: name, value: value)
        } else {
            bulkSelectionField = nil
        }

        return AO3InboxItem(
            id: id,
            commenterName: commenterName,
            isGuest: isGuest,
            isAnonymousCreator: isAnonymousCreator,
            commenterIdentity: commenterIdentity,
            avatarURL: avatarURL,
            subjectTitle: subjectTitle,
            subjectURL: subjectURL,
            workID: workID,
            excerpt: excerpt,
            postedAgo: postedAgo,
            isUnread: isUnread,
            isReplied: isReplied,
            canReply: canReply,
            bulkSelectionField: bulkSelectionField
        )
    }

    /// Parses AO3's mass-edit form exactly as rendered. A partial/malformed form
    /// returns nil so the UI stays read-only instead of guessing a write request.
    private static func parseInboxBulkForm(
        in doc: Document,
        items: [AO3InboxItem]
    ) -> AO3InboxBulkForm? {
        guard let form = try? doc.select("form#inbox-form").first(),
              let action = try? form.attr("action"),
              let actionURL = inboxAbsoluteURL(action)
        else { return nil }

        let htmlMethod = ((try? form.attr("method")) ?? "").lowercased()
        guard htmlMethod == "post" else { return nil }

        let hiddenFields = inboxHiddenFields(in: form)
        guard let csrfToken = hiddenFields.first(where: { $0.name == "authenticity_token" })?.value,
              !csrfToken.isEmpty,
              let checkboxFieldName = items.compactMap(\.bulkSelectionField).first?.name,
              !checkboxFieldName.isEmpty
        else { return nil }

        var actionFields: [AO3InboxBulkAction: AO3FormField] = [:]
        for input in (try? form.select("input[type=submit][name][value]").array()) ?? [] {
            guard let name = try? input.attr("name"), !name.isEmpty,
                  let value = try? input.attr("value"), !value.isEmpty
            else { continue }
            let action: AO3InboxBulkAction?
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "mark read": action = .markRead
            case "mark unread": action = .markUnread
            case "delete from inbox": action = .delete
            default: action = nil
            }
            if let action, actionFields[action] == nil {
                actionFields[action] = AO3FormField(name: name, value: value)
            }
        }
        guard AO3InboxBulkAction.allCases.allSatisfy({ actionFields[$0] != nil }) else {
            return nil
        }

        return AO3InboxBulkForm(
            actionURL: actionURL,
            htmlMethod: htmlMethod,
            httpMethodOverride: hiddenFields.first(where: { $0.name == "_method" })?.value,
            csrfToken: csrfToken,
            hiddenFields: hiddenFields,
            checkboxFieldName: checkboxFieldName,
            actionFields: actionFields
        )
    }

    /// Parses AO3's GET filter form into its actual field names, values, and
    /// checked state. Unknown radio groups remain present with a neutral title,
    /// keeping the parser forward-compatible without fabricating a request.
    private static func parseInboxFilterForm(in doc: Document) -> AO3InboxFilterForm? {
        guard let form = try? doc.select("form#inbox-filters").first(),
              let action = try? form.attr("action"),
              let actionURL = inboxAbsoluteURL(action)
        else { return nil }

        let method = ((try? form.attr("method")) ?? "get").lowercased()
        guard method == "get" else { return nil }

        var names: [String] = []
        var inputsByName: [String: [Element]] = [:]
        for input in (try? form.select("input[type=radio][name][value]").array()) ?? [] {
            guard let name = try? input.attr("name"), !name.isEmpty else { continue }
            if inputsByName[name] == nil { names.append(name) }
            inputsByName[name, default: []].append(input)
        }

        let fields = names.compactMap { name -> AO3InboxFilterField? in
            guard let inputs = inputsByName[name] else { return nil }
            let options = inputs.compactMap { input -> AO3InboxFilterOption? in
                guard let value = try? input.attr("value"), !value.isEmpty else { return nil }
                let inputID = input.id()
                let label = if !inputID.isEmpty {
                    (try? form.select("label[for='\(inputID)']").first()?.text()) ?? value
                } else {
                    value
                }
                return AO3InboxFilterOption(
                    value: value,
                    label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                    isSelected: input.hasAttr("checked")
                )
            }
            guard !options.isEmpty else { return nil }
            return AO3InboxFilterField(
                name: name,
                title: inboxFilterTitle(for: options),
                options: options
            )
        }
        guard !fields.isEmpty else { return nil }

        return AO3InboxFilterForm(
            actionURL: actionURL,
            hiddenFields: inboxHiddenFields(in: form),
            fields: fields
        )
    }

    private static func inboxHiddenFields(in form: Element) -> [AO3FormField] {
        ((try? form.select("input[type=hidden][name]").array()) ?? []).compactMap { input in
            guard let name = try? input.attr("name"), !name.isEmpty,
                  let value = try? input.attr("value")
            else { return nil }
            return AO3FormField(name: name, value: value)
        }
    }

    private static func inboxAbsoluteURL(_ value: String) -> URL? {
        let base = URL(string: "https://archiveofourown.org")!
        return URL(string: value, relativeTo: base)?.absoluteURL
    }

    private static func inboxFilterTitle(for options: [AO3InboxFilterOption]) -> String {
        let labels = options.map { $0.label.lowercased() }
        if labels.contains(where: { $0.contains("newest first") || $0.contains("oldest first") }) {
            return "Sort by Date"
        }
        if labels.contains(where: { $0.contains("without replies") || $0.contains("replied") }) {
            return "Replied To"
        }
        if labels.contains(where: { $0.contains("unread") || $0.contains("show read") }) {
            return "Read"
        }
        return "Filter"
    }

    /// The numeric work id in a `/works/<id>/…` path, if any.
    private static func workID(inPath path: String) -> Int? {
        guard let range = path.range(of: "/works/") else { return nil }
        return Int(path[range.upperBound...].prefix { $0.isNumber })
    }

    /// Every integer in the text, in order, commas tolerated ("1,234").
    private static func integers(in text: String) -> [Int] {
        var results: [Int] = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if character == ",", !current.isEmpty {
                continue
            } else if !current.isEmpty {
                if let value = Int(current) { results.append(value) }
                current = ""
            }
        }
        if !current.isEmpty, let value = Int(current) { results.append(value) }
        return results
    }
}
