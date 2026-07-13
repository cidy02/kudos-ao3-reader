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

    /// Which page verification must authoritatively fetch to check `context`.
    /// Pure so the endpoint choice — for a reply, always the exact parent
    /// thread, never a guessed work-comments page — is provable without live
    /// network.
    enum CommentVerificationPlan: Equatable {
        /// Reply: AO3's standalone `/comments/<parentCommentID>` view, which
        /// renders the parent and every one of its current direct replies
        /// regardless of which work-comments page the parent itself sits on.
        case standaloneThread(parentCommentID: Int)
        /// Top-level: the work's comments, page 1 then (if multi-page) the
        /// last page — AO3 orders oldest-first, so a fresh top-level comment
        /// always lands on the last page.
        case workComments(workID: Int)
    }

    /// Pure endpoint selection (unit-tested): a reply always resolves to its
    /// own parent thread, never to a work/chapter pagination guess.
    static func verificationPlan(for context: AO3CommentContext) -> CommentVerificationPlan {
        if let parentID = context.parentCommentID {
            return .standaloneThread(parentCommentID: parentID)
        }
        return .workComments(workID: context.workID)
    }

    /// After an ambiguous POST result (e.g. timeout once the request was already
    /// on the wire), checks whether the comment actually landed. Conservative by
    /// design — reads only, never a re-POST.
    ///
    /// A **reply** is checked against its own parent's standalone thread
    /// (`verificationPlan`), not a work-comments page guess: the parent thread
    /// renders wherever the parent already lives, not necessarily the page the
    /// composer happened to be showing, so a guessed page can miss it and
    /// false-negative into `.absent` — which is exactly the double-post path
    /// this exists to prevent. `submittedAt` (when the original POST attempt
    /// was made) lets the match require a plausibly-recent reply, so a
    /// coincidental older reply with the same author/text/parent cannot be
    /// mistaken for proof this attempt landed.
    func verifyCommentPosted(
        context: AO3CommentContext, body: String, submittedAt: Date? = nil
    ) async -> CommentVerification {
        guard let username else { return .unknown }
        let normalized = CommentSubmissionKey.normalize(body)
        do {
            let page: AO3CommentsPage
            switch Self.verificationPlan(for: context) {
            case let .standaloneThread(parentID):
                let request = try? authenticatedRequest(
                    for: AO3Client.commentThreadURL(commentID: parentID)
                )
                page = try await AO3Client.shared.commentThreadPage(
                    commentID: parentID, request: request
                )
            case let .workComments(workID):
                let request = try? authenticatedRequest(
                    for: AO3Client.commentsPageURL(workID: workID)
                )
                let first = try await AO3Client.shared.commentsPage(
                    workID: workID, page: 1, request: request
                )
                page = first.totalPages > 1
                    ? try await AO3Client.shared.commentsPage(
                        workID: workID, page: first.totalPages, request: request
                    )
                    : first
            }
            let found = Self.containsComment(
                in: page, author: username, normalizedBody: normalized,
                parentID: context.parentCommentID, postedAfter: submittedAt
            )
            return found ? .found : .absent
        } catch {
            // Offline / rate-limited / parse failure: we genuinely don't know.
            return .unknown
        }
    }

    /// Generous clock-skew/rounding allowance for the `postedAfter` timing
    /// check below — AO3 timestamps are minute-granularity and the device and
    /// AO3 server clocks aren't synchronized. Wide enough that a genuine match
    /// is never false-negatived; tight enough to exclude a pre-existing,
    /// unrelated comment left over from well before this attempt.
    private static let verificationTimingTolerance: TimeInterval = 600

    /// Pure matcher (unit-tested): does the page contain a comment by `author`
    /// whose normalized body equals `normalizedBody` — under the right parent
    /// when the submission was a reply, and (when `postedAfter` is supplied)
    /// posted no earlier than that attempt started, within tolerance?
    static func containsComment(
        in page: AO3CommentsPage, author: String, normalizedBody: String, parentID: Int?,
        postedAfter: Date? = nil
    ) -> Bool {
        func matches(_ comment: AO3Comment) -> Bool {
            guard comment.author.caseInsensitiveCompare(author) == .orderedSame,
                  CommentSubmissionKey.normalize(comment.bodyText) == normalizedBody
            else { return false }
            guard let postedAfter, let postedAt = comment.postedAt else { return true }
            return postedAt >= postedAfter.addingTimeInterval(-verificationTimingTolerance)
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
