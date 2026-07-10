import Foundation
import SwiftSoup

/// Comment reading: URL builders, fetchers, and SwiftSoup parsers for AO3's
/// comment threads. Markup ground truth (verified live 2026-07-09) is documented
/// in `docs/ai/COMMENTS_HANDOFF.md`; every selector below traces to it.
///
/// Networking respect: fetches ride the client's existing paced/coalesced/
/// retried GET pipeline (`getHTML`) or the authenticated equivalent — one page
/// per explicit user action, no background refresh, no per-chapter fan-out.
extension AO3Client {

    // MARK: URLs

    /// The comments page for a whole work (AO3's "Entire Work + comments" view;
    /// multichapter works 302 to chapter 1 without `view_full_work=true`) or, when
    /// `chapterID` is given, for that single chapter. `view_adult` mirrors the
    /// existing works loaders so adult works resolve without the interstitial.
    static func commentsPageURL(workID: Int, chapterID: Int? = nil, page: Int = 1) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "archiveofourown.org"
        if let chapterID {
            components.path = "/works/\(workID)/chapters/\(chapterID)"
        } else {
            components.path = "/works/\(workID)"
        }
        var items = [
            URLQueryItem(name: "show_comments", value: "true"),
            URLQueryItem(name: "view_adult", value: "true")
        ]
        if chapterID == nil {
            items.append(URLQueryItem(name: "view_full_work", value: "true"))
        }
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        components.queryItems = items
        return components.url!
    }

    static func chapterIndexURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/navigate")!
    }

    // MARK: Fetchers

    /// One page of comments. Pass an authenticated `request` (built by
    /// `AO3AuthService.authenticatedRequest`) when signed in so AO3 renders the
    /// session's own Edit/Delete actions and restricted works resolve; the plain
    /// URL path serves signed-out browsing of public works.
    func commentsPage(
        workID: Int, chapterID: Int? = nil, page: Int = 1, request: URLRequest? = nil
    ) async throws -> AO3CommentsPage {
        let url = Self.commentsPageURL(workID: workID, chapterID: chapterID, page: page)
        let html: String
        if var request {
            request.url = url
            html = try await authenticatedPageHTML(for: request)
        } else {
            html = try await getHTML(url)
        }
        return try Self.parseCommentsPage(html, page: page)
    }

    /// The work's chapter index (one small `/navigate` page; cache at the caller).
    func chapterIndex(workID: Int, request: URLRequest? = nil) async throws -> [AO3ChapterRef] {
        let url = Self.chapterIndexURL(workID: workID)
        let html: String
        if var request {
            request.url = url
            html = try await authenticatedPageHTML(for: request)
        } else {
            html = try await getHTML(url)
        }
        return try Self.parseChapterIndex(html)
    }

    // MARK: Parsers

    /// Parses a `show_comments=true` page: the thread list inside
    /// `#comments_placeholder`, its pagination, and (opportunistically) the work's
    /// total comment count from the stats block.
    static func parseCommentsPage(_ html: String, page: Int) throws -> AO3CommentsPage {
        let doc = try SwiftSoup.parse(html)
        var result = AO3CommentsPage(currentPage: page, totalPages: page)

        guard let placeholder = try doc.select("#comments_placeholder").first() else {
            // Not an error: works with zero comments render no placeholder threads,
            // and a missing region on a real page should read as "no comments"
            // rather than crash — the caller surfaces counts/staleness honestly.
            result.totalComments = try? parseTotalComments(doc)
            return result
        }

        // The first ol.thread in document order is the top-level one — nested
        // reply threads always come later inside it.
        if let topThread = try placeholder.select("ol.thread").first() {
            result.comments = try parseThread(topThread)
        }

        // Pagination footer inside the comments region (same markup as search).
        for li in try placeholder.select("ol.pagination li").array() {
            if let value = try? Int(li.text().trimmingCharacters(in: .whitespaces)),
               value > result.totalPages {
                result.totalPages = value
            }
        }

        result.totalComments = try? parseTotalComments(doc)
        return result
    }

    /// The work-level comment total from the page's stats (`dl.stats dd.comments`).
    private static func parseTotalComments(_ doc: Document) throws -> Int? {
        guard let dd = try doc.select("dl.stats dd.comments").first() else { return nil }
        let digits = try dd.text().filter(\.isNumber)
        return Int(digits)
    }

    /// Walks one `ol.thread`. AO3's structure: a comment `li` (`li.comment` with
    /// `id=comment_<id>`), then — when it has replies — a *sibling* wrapper `li`
    /// (no id) containing a nested `ol.thread`. So a wrapper's parsed comments
    /// attach as replies of the immediately preceding comment.
    private static func parseThread(_ thread: Element) throws -> [AO3Comment] {
        var comments: [AO3Comment] = []
        for li in thread.children().array() where li.tagName() == "li" {
            if li.hasClass("comment"), let comment = try parseComment(li) {
                comments.append(comment)
            } else if let nested = try li.select("ol.thread").first(), !comments.isEmpty {
                comments[comments.count - 1].replies += try parseThread(nested)
            }
        }
        return comments
    }

    /// One `li.comment`. Returns nil when the `li` carries no parseable id —
    /// deleted-comment placeholders and future markup drift degrade to "skipped",
    /// never to a crash.
    private static func parseComment(_ li: Element) throws -> AO3Comment? {
        let idAttr = li.id() // "comment_1252794206"
        guard idAttr.hasPrefix("comment_"), let id = Int(idAttr.dropFirst("comment_".count)) else {
            return nil
        }
        var comment = AO3Comment(id: id, author: "", isGuest: false)

        if let byline = try li.select("h4.heading.byline").first() {
            if let userLink = try byline.select("a[href^=/users/]").first() {
                comment.author = try userLink.text()
                comment.userPath = try userLink.attr("href")
            } else {
                // Guest byline: `<span>Name</span><span class="role"> (Guest)</span>`.
                comment.isGuest = true
                comment.author = try byline.children().array()
                    .first(where: { $0.tagName() == "span" && !$0.hasClass("role")
                        && !$0.hasClass("parent") && !$0.hasClass("posted") })
                    .map { try $0.text() } ?? "Guest"
            }
            if let chapterLink = try byline.select("span.parent a[href*=/chapters/]").first() {
                comment.chapterLabel = try chapterLink.text()
                let href = try chapterLink.attr("href")
                if let last = href.split(separator: "/").last { comment.chapterID = Int(last) }
            }
            if let posted = try byline.select("span.posted.datetime").first() {
                comment.postedText = try posted.text()
                comment.postedAt = AO3CommentTimestamp.parse(comment.postedText)
            }
        }
        // AO3 includes the user icon in the comment itself. Use only that URL —
        // never follow the profile link or issue a separate discovery request.
        if !comment.isGuest, let icon = try li.select("div.icon img.icon[src]").first() {
            comment.avatarURL = AO3Comment.ao3URL(for: try icon.attr("src"))
        }

        // Body: this comment's own blockquote. Replies are structurally siblings
        // (not descendants), so the direct child is unambiguous.
        if let body = li.children().array().first(where: { $0.tagName() == "blockquote" }) {
            let paragraphs = try body.select("p").array()
            if paragraphs.isEmpty {
                comment.bodyText = try body.text()
            } else {
                comment.bodyText = try paragraphs.map { try $0.text() }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            }
        }

        // Actions: expose exactly what AO3 rendered for this session, nothing
        // more. Replies are siblings (not descendants), so the only ul.actions
        // inside this li is this comment's own.
        if let actions = try li.select("ul.actions").first() {
            for link in try actions.select("a").array() {
                let label = try link.text().lowercased()
                let href = try link.attr("href")
                applyAction(label: label, href: href, to: &comment)
            }
        }

        return comment
    }

    private static func applyAction(label: String, href: String, to comment: inout AO3Comment) {
        switch label {
        case "reply": comment.canReply = true
        case "edit": comment.editPath = href
        case "delete": comment.deletePath = href
        case "thread": comment.threadPath = href
        case "parent thread": comment.parentThreadPath = href
        default: break
        }
    }

    /// Parses `/works/<id>/navigate`: `ol.chapter.index.group > li > a` with the
    /// text "N. Title" and the chapter id in the href.
    static func parseChapterIndex(_ html: String) throws -> [AO3ChapterRef] {
        let doc = try SwiftSoup.parse(html)
        var chapters: [AO3ChapterRef] = []
        for li in try doc.select("ol.chapter.index li").array() {
            guard let link = try li.select("a[href*=/chapters/]").first() else { continue }
            let href = try link.attr("href")
            guard let last = href.split(separator: "/").last, let id = Int(last) else { continue }

            let text = try link.text()
            var position = chapters.count + 1
            var title = text
            if let dot = text.firstIndex(of: "."), let number = Int(text[text.startIndex..<dot]) {
                position = number
                title = text[text.index(dot, offsetBy: 1)...]
                    .trimmingCharacters(in: .whitespaces)
            }
            var chapter = AO3ChapterRef(id: id, position: position, title: title)
            if let date = try li.select("span.datetime").first() {
                chapter.dateText = try date.text()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            }
            chapters.append(chapter)
        }
        return chapters
    }
}
