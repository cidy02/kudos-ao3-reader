import Foundation

/// Native AO3 *write* actions (kudos, comments). Each fetches the work page once for
/// its Rails CSRF `authenticity_token`, then submits a **single** authenticated POST
/// (never retried — a replayed write would double-post). Failures are surfaced
/// honestly; nothing is ever faked as success.
///
/// Endpoints/params mirror AO3's own forms. They can only be confirmed against a live
/// signed-in session, so they're kept as named constants here for easy adjustment.
extension AO3AuthService {

    /// Leaves kudos on a work. Returns a short user-facing message on success (incl.
    /// the benign "already left kudos" case); throws `AO3WriteError`/`AO3Error` on
    /// failure (rate-limited, signed-out, rejected, …).
    func giveKudos(workID: Int) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        let workURL = Self.workURL(workID)
        let (_, token) = try await fetchCSRFPage(at: workURL)

        let body = Self.formEncoded([
            ("authenticity_token", token),
            ("kudo[commentable_id]", String(workID)),
            ("kudo[commentable_type]", "Work")
        ])
        let request = try writeRequest(
            to: Self.kudosEndpoint, body: body, csrf: token, referer: workURL, ajax: true
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        switch status {
        case 200 ... 299:
            return "Kudos left."
        case 422 where responseBody.localizedCaseInsensitiveContains("already left kudos"):
            return "You've already left kudos here."
        default:
            throw AO3WriteError.rejected(
                AO3Client.writeErrorMessage(in: responseBody) ?? "AO3 didn't accept the kudos."
            )
        }
    }

    /// Posts a comment on a work under the resolved posting pseud. The caller must
    /// have confirmed the user's intent. Returns a success message; throws on failure.
    func postComment(
        workID: Int,
        content: String,
        expectedGeneration: Int,
        onFormPrepared: (Bool) -> Void = { _ in }
    ) async throws -> String {
        try requireSessionGeneration(expectedGeneration)
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AO3WriteError.emptyComment }

        // One GET serves the CSRF token and the pseud control. `view_adult=true`
        // because the adult interstitial page still carries the CSRF meta but not
        // the comment form — without it, an adult work's top-level comment would
        // POST pseud-less and be rejected (CAA-1).
        let formURL = Self.commentFormURL(workID: workID)
        let (html, token) = try await fetchCSRFPage(at: formURL)
        try requireSessionGeneration(expectedGeneration)

        let pseud = try requiredCommentPseudID(from: html)
        // Preserve this exact form-page evidence if the POST outcome becomes
        // ambiguous. Verification must not call an intentionally hidden,
        // unreviewed comment "absent" and release the duplicate-post guard.
        onFormPrepared(AO3Client.commentFormMayHidePostedComment(html, commentableID: workID))
        let params: [(String, String)] = [
            ("authenticity_token", token),
            ("comment[comment_content]", text),
            ("comment[pseud_id]", pseud)
        ]
        let request = try writeRequest(
            to: Self.commentsEndpoint(workID: workID),
            body: Self.formEncoded(params), csrf: token, referer: formURL, ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        return try commentWriteResult(
            status: status, body: responseBody,
            onSuccess: "Comment posted.",
            rejectionFallback: "AO3 couldn't post the comment."
        )
    }

    /// Subscribes to (or, if already subscribed, unsubscribes from) a work. Reads the
    /// work page once for the CSRF token + current subscription state, then POSTs the
    /// matching action. Returns a message describing what happened.
    func toggleSubscribe(workID: Int) async throws -> String {
        guard isLoggedIn, let username else { throw AO3WriteError.notSignedIn }
        let workURL = Self.workURL(workID)
        let (html, token) = try await fetchCSRFPage(at: workURL)

        let state = AO3Client.parseSubscription(from: html)
        if state.isSubscribed, let path = state.unsubscribePath, let url = Self.absoluteURL(path) {
            // AO3's unsubscribe form is a POST carrying `_method=delete`.
            let body = Self.formEncoded([("_method", "delete"), ("authenticity_token", token)])
            let request = try writeRequest(to: url, body: body, csrf: token, referer: workURL, ajax: false)
            let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
            if (200 ... 399).contains(status) { return "Unsubscribed." }
            throw AO3WriteError.rejected(
                AO3Client.writeErrorMessage(in: responseBody) ?? "Couldn't unsubscribe."
            )
        }

        let body = Self.formEncoded([
            ("authenticity_token", token),
            ("subscription[subscribable_id]", String(workID)),
            ("subscription[subscribable_type]", "Work")
        ])
        let request = try writeRequest(
            to: Self.subscriptionsEndpoint(username: username),
            body: body, csrf: token, referer: workURL, ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        if responseBody.localizedCaseInsensitiveContains("already subscribed") {
            return "You're already subscribed."
        }
        if (200 ... 399).contains(status), AO3Client.writeErrorMessage(in: responseBody) == nil {
            return "Subscribed."
        }
        throw AO3WriteError.rejected(
            AO3Client.writeErrorMessage(in: responseBody) ?? "Couldn't subscribe."
        )
    }

    /// Adds the work to the user's Marked-for-Later reading list.
    func markForLater(workID: Int) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        let workURL = Self.workURL(workID)
        let (_, token) = try await fetchCSRFPage(at: workURL)
        let body = Self.formEncoded([("authenticity_token", token)])
        let request = try writeRequest(
            to: Self.markForLaterEndpoint(workID: workID),
            body: body, csrf: token, referer: workURL, ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        if (200 ... 399).contains(status) { return "Marked for later." }
        throw AO3WriteError.rejected(
            AO3Client.writeErrorMessage(in: responseBody) ?? "Couldn't mark for later."
        )
    }

    /// The fields of a new AO3 bookmark.
    struct BookmarkInput: Equatable {
        var notes = ""
        var tags = "" // comma-separated
        var isPrivate = false
        var isRec = false
    }

    /// Creates a bookmark on the work under the chosen "Posting As" pseud when
    /// this form offers it, else the form's own default (see resolvedPostingPseudID).
    func createBookmark(workID: Int, input: BookmarkInput) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        let workURL = Self.workURL(workID)
        let (html, token) = try await fetchCSRFPage(at: workURL)

        var params: [(String, String)] = [
            ("authenticity_token", token),
            ("bookmark[bookmarker_notes]", input.notes),
            ("bookmark[tag_string]", input.tags),
            ("bookmark[collection_names]", ""),
            ("bookmark[private]", input.isPrivate ? "1" : "0"),
            ("bookmark[rec]", input.isRec ? "1" : "0")
        ]
        if let pseud = resolvedPostingPseudID(from: html, field: "bookmark[pseud_id]") {
            params.append(("bookmark[pseud_id]", pseud))
        }
        let request = try writeRequest(
            to: Self.bookmarksEndpoint(workID: workID),
            body: Self.formEncoded(params), csrf: token, referer: workURL, ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        if (200 ... 399).contains(status), AO3Client.writeErrorMessage(in: responseBody) == nil {
            return "Bookmarked."
        }
        throw AO3WriteError.rejected(
            AO3Client.writeErrorMessage(in: responseBody) ?? "Couldn't bookmark this work."
        )
    }

    // MARK: - Helpers

    /// Fetches a page and its CSRF token together — the common first step of
    /// every AO3 write action. Callers that also need the page HTML (pseud/
    /// subscription-state parsing, form-drift detection) read it from the same
    /// fetch; callers that only need the token (kudos, mark-for-later, comment
    /// delete/edit) just discard it. Internal (not private) so sibling
    /// write-action extensions (`AO3CommentActions`) share the one
    /// implementation instead of forking it.
    func fetchCSRFPage(at url: URL) async throws -> (html: String, token: String) {
        let request = try authenticatedRequest(for: url)
        let html = try await AO3Client.shared.authenticatedPageHTML(for: request)
        guard let token = AO3Client.parseCSRFToken(from: html) else {
            throw AO3WriteError.noCSRFToken
        }
        return (html, token)
    }

    /// Turns AO3's write-verdict for a comment-shaped POST (post/reply/edit/
    /// delete/Inbox-bulk-action) into either `onSuccess()` or a thrown error
    /// carrying `rejectionFallback()` when AO3 gave no specific reason.
    /// Deliberately **not** used by `giveKudos` — kudos has its own
    /// "already left kudos" 2xx/422 semantics with no flash-message equivalent,
    /// so folding it in here would be a real behavior change, not deduplication.
    /// Internal (not private) so sibling write-action extensions
    /// (`AO3CommentActions`, `AO3InboxActions`) share the one implementation.
    func commentWriteResult(
        status: Int,
        body: String,
        onSuccess: @autoclosure () -> String,
        rejectionFallback: @autoclosure () -> String
    ) throws -> String {
        switch AO3Client.commentWriteVerdict(status: status, body: body) {
        case .success:
            return onSuccess()
        case .unconfirmed:
            throw AO3WriteError.unconfirmed
        case let .rejected(reason):
            throw AO3WriteError.rejected(reason ?? rejectionFallback())
        }
    }

    /// Builds an authenticated `POST` carrying the CSRF token, form body, and (for
    /// AO3's UJS endpoints like kudos) the AJAX headers AO3 expects. Internal (not
    /// private) so sibling write-action extensions (`AO3CommentActions`) share the
    /// one implementation instead of forking it.
    func writeRequest(
        to url: URL, body: Data, csrf: String, referer: URL, ajax: Bool
    ) throws -> URLRequest {
        var request = try authenticatedRequest(for: url, method: "POST")
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        if ajax {
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            request.setValue("text/javascript, application/javascript, */*",
                             forHTTPHeaderField: "Accept")
        }
        return request
    }

    // MARK: - Endpoints & encoding (mirror AO3's forms; verify against a live session)

    static func workURL(_ workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)")!
    }

    static let kudosEndpoint = URL(string: "https://archiveofourown.org/kudos.js")!
    static func commentsEndpoint(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/comments")!
    }

    /// The page a top-level comment's CSRF + pseud are scraped from. `view_adult`
    /// so an adult work renders the real comment form, not the interstitial.
    static func commentFormURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)?view_adult=true")!
    }

    static func subscriptionsEndpoint(username: String) -> URL {
        URL(string: "https://archiveofourown.org/users/\(username)/subscriptions")!
    }

    static func markForLaterEndpoint(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/mark_for_later")!
    }

    static func bookmarksEndpoint(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/bookmarks")!
    }

    /// Resolves an AO3 form `action` (usually a site-relative path) to an absolute URL.
    static func absoluteURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "https://archiveofourown.org\(path.hasPrefix("/") ? "" : "/")\(path)")
    }

    /// `application/x-www-form-urlencoded` body. Ordered so callers control field
    /// order; keys/values are percent-encoded (RFC 3986 unreserved kept).
    static func formEncoded(_ params: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = params.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}

/// Errors specific to native AO3 write actions. (Network/rate-limit/auth errors come
/// through as `AO3Error`.)
enum AO3WriteError: LocalizedError, Equatable {
    case notSignedIn
    case noCSRFToken
    case emptyComment
    /// The fetched page rendered no `comment[pseud_id]` control (hidden input or
    /// select) for a signed-in comment flow — an interstitial, login bounce, or a
    /// page where AO3 didn't offer the form. Thrown **before** any POST: a
    /// pseud-less comment POST is guaranteed-rejected server-side (guest
    /// validations), and the id is only ever scraped, never synthesized.
    case noPseudControl
    /// The write's final 2xx/3xx page carried neither a recognized error flash
    /// nor a recognized success flash — the write may or may not have landed.
    /// Posts/replies route this into the ambiguous-verification path; edit/
    /// delete/Inbox surface it as an explicit "couldn't confirm".
    case unconfirmed
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Log in to AO3 first."
        case .noCSRFToken: "Couldn't prepare the request. Try again, or open the work on AO3."
        case .emptyComment: "Write a comment first."
        case .noPseudControl:
            "AO3 didn't show a comment form here, so nothing was posted. "
                + "The work may restrict comments — try opening it on AO3."
        case .unconfirmed:
            "AO3 replied but didn't confirm the change went through. "
                + "Check on AO3 before trying again."
        case let .rejected(reason): reason
        }
    }
}
