import Foundation

/// Comment write actions beyond the existing top-level `postComment`: replies,
/// and edit/delete for the session's own comments. Same discipline as
/// `AO3WriteActions`: one polite GET for the CSRF token, then a **single**
/// authenticated POST that is never retried or coalesced. Endpoints were
/// verified against AO3's no-JS forms (`docs/ai/COMMENTS_HANDOFF.md`).
extension AO3AuthService {

    /// Posts a reply to a comment (`POST /comments/<parent>/comments`, per AO3's
    /// no-JS reply form). CSRF + default pseud come from the parent's thread page.
    func postCommentReply(parentCommentID: Int, content: String) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AO3WriteError.emptyComment }

        let threadURL = Self.commentThreadURL(parentCommentID)
        let pageRequest = try authenticatedRequest(for: threadURL)
        let html = try await AO3Client.shared.authenticatedPageHTML(for: pageRequest)
        guard let token = AO3Client.parseCSRFToken(from: html) else {
            throw AO3WriteError.noCSRFToken
        }

        var params: [(String, String)] = [
            ("authenticity_token", token),
            ("comment[comment_content]", text)
        ]
        // The chosen "Posting As" pseud when this form offers it, else the form's
        // own default (see resolvedPostingPseudID).
        if let pseud = resolvedPostingPseudID(from: html) {
            params.append(("comment[pseud_id]", pseud))
        }
        let request = try writeRequest(
            to: Self.commentReplyEndpoint(parentCommentID: parentCommentID),
            body: Self.formEncoded(params), csrf: token, referer: threadURL, ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        if (200 ... 399).contains(status), AO3Client.writeErrorMessage(in: responseBody) == nil {
            return "Reply posted."
        }
        throw AO3WriteError.rejected(
            AO3Client.writeErrorMessage(in: responseBody) ?? "AO3 couldn't post the reply."
        )
    }

    /// Deletes one of the session's own comments. Only callable when AO3 itself
    /// rendered a Delete action for it (`AO3Comment.deletePath` parsed from the
    /// page) — the app never synthesizes the capability.
    func deleteComment(commentID: Int) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        let threadURL = Self.commentThreadURL(commentID)
        let token = try await commentPageCSRF(at: threadURL)
        // Rails destroy: POST to the comment resource with _method=delete.
        let body = Self.formEncoded([("_method", "delete"), ("authenticity_token", token)])
        let request = try writeRequest(
            to: threadURL, body: body, csrf: token, referer: threadURL, ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        if (200 ... 399).contains(status) { return "Comment deleted." }
        throw AO3WriteError.rejected(
            AO3Client.writeErrorMessage(in: responseBody) ?? "AO3 couldn't delete the comment."
        )
    }

    /// Edits one of the session's own comments (`PUT /comments/<id>` via
    /// `_method=put`, per Rails update). Gated the same way as delete.
    func editComment(commentID: Int, content: String) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AO3WriteError.emptyComment }

        let editURL = Self.commentEditURL(commentID)
        let token = try await commentPageCSRF(at: editURL)
        let body = Self.formEncoded([
            ("_method", "put"),
            ("authenticity_token", token),
            ("comment[comment_content]", text)
        ])
        let request = try writeRequest(
            to: Self.commentThreadURL(commentID),
            body: body, csrf: token, referer: editURL, ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        if (200 ... 399).contains(status), AO3Client.writeErrorMessage(in: responseBody) == nil {
            return "Comment updated."
        }
        throw AO3WriteError.rejected(
            AO3Client.writeErrorMessage(in: responseBody) ?? "AO3 couldn't update the comment."
        )
    }

    // MARK: Ambiguous-submit verification

    /// Outcome of a post-verification check. `unknown` (couldn't reach/parse AO3)
    /// must never be treated as "absent" — that's the double-post path.
    enum CommentVerification {
        case found
        case absent
        case unknown
    }

    /// After an ambiguous POST result (e.g. timeout once the request was already
    /// on the wire), checks whether the comment actually landed. Conservative by
    /// design — reads only, never a re-POST.
    ///
    /// A fresh **top-level** comment always lands on the work's LAST page (AO3
    /// orders oldest-first), work-level regardless of the composer's chapter
    /// scope — `postComment` posts to the work, and the work-level list contains
    /// replies too.
    ///
    /// A **reply**'s parent thread renders wherever it already was — not
    /// necessarily the last page — so guessing between page 1 and the last page
    /// would false-negative on any multi-page work and unblock a real duplicate
    /// POST. `knownPage` is the page (and, via `context.chapterID`, the chapter
    /// scope) the caller was actually viewing when the parent comment was on
    /// screen; re-fetching exactly that page is known-correct rather than a guess.
    func verifyCommentPosted(
        context: AO3CommentContext, body: String, knownPage: Int? = nil
    ) async -> CommentVerification {
        guard let username else { return .unknown }
        let normalized = CommentSubmissionKey.normalize(body)
        do {
            let page: AO3CommentsPage
            if context.parentCommentID != nil {
                let request = try? authenticatedRequest(
                    for: AO3Client.commentsPageURL(workID: context.workID, chapterID: context.chapterID)
                )
                page = try await AO3Client.shared.commentsPage(
                    workID: context.workID, chapterID: context.chapterID,
                    page: knownPage ?? 1, request: request
                )
            } else {
                let request = try? authenticatedRequest(
                    for: AO3Client.commentsPageURL(workID: context.workID)
                )
                let first = try await AO3Client.shared.commentsPage(
                    workID: context.workID, page: 1, request: request
                )
                page = first.totalPages > 1
                    ? try await AO3Client.shared.commentsPage(
                        workID: context.workID, page: first.totalPages, request: request
                    )
                    : first
            }
            let found = Self.containsComment(
                in: page, author: username, normalizedBody: normalized,
                parentID: context.parentCommentID
            )
            return found ? .found : .absent
        } catch {
            // Offline / rate-limited / parse failure: we genuinely don't know.
            return .unknown
        }
    }

    /// Pure matcher (unit-tested): does the page contain a comment by `author`
    /// whose normalized body equals `normalizedBody` — under the right parent
    /// when the submission was a reply?
    static func containsComment(
        in page: AO3CommentsPage, author: String, normalizedBody: String, parentID: Int?
    ) -> Bool {
        func matches(_ comment: AO3Comment) -> Bool {
            comment.author.caseInsensitiveCompare(author) == .orderedSame
                && CommentSubmissionKey.normalize(comment.bodyText) == normalizedBody
        }
        if let parentID {
            let parents = page.comments.flatMap(\.flattened).filter { $0.id == parentID }
            return parents.contains { $0.replies.contains(where: matches) }
        }
        return page.comments.flatMap(\.flattened).contains(where: matches)
    }

    // MARK: Helpers

    private func commentPageCSRF(at url: URL) async throws -> String {
        let request = try authenticatedRequest(for: url)
        let html = try await AO3Client.shared.authenticatedPageHTML(for: request)
        guard let token = AO3Client.parseCSRFToken(from: html) else {
            throw AO3WriteError.noCSRFToken
        }
        return token
    }

    static func commentThreadURL(_ commentID: Int) -> URL {
        URL(string: "https://archiveofourown.org/comments/\(commentID)")!
    }

    static func commentEditURL(_ commentID: Int) -> URL {
        URL(string: "https://archiveofourown.org/comments/\(commentID)/edit")!
    }

    static func commentReplyEndpoint(parentCommentID: Int) -> URL {
        URL(string: "https://archiveofourown.org/comments/\(parentCommentID)/comments")!
    }
}
