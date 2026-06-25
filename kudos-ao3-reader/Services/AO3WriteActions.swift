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
        let token = try await csrfToken(forPageAt: workURL)

        let body = Self.formEncoded([
            ("authenticity_token", token),
            ("kudo[commentable_id]", String(workID)),
            ("kudo[commentable_type]", "Work"),
        ])
        let request = try writeRequest(
            to: Self.kudosEndpoint, body: body, csrf: token, referer: workURL, ajax: true
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        switch status {
        case 200...299:
            return "Kudos left."
        case 422 where responseBody.localizedCaseInsensitiveContains("already left kudos"):
            return "You've already left kudos here."
        default:
            throw AO3WriteError.rejected(
                AO3Client.writeErrorMessage(in: responseBody) ?? "AO3 didn't accept the kudos."
            )
        }
    }

    /// Posts a comment on a work under the user's default pseud. The caller must have
    /// confirmed the user's intent. Returns a success message; throws on failure.
    func postComment(workID: Int, content: String) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AO3WriteError.emptyComment }

        let workURL = Self.workURL(workID)
        // One GET serves both the CSRF token and the default pseud the form pre-selects.
        let pageRequest = try authenticatedRequest(for: workURL)
        let html = try await AO3Client.shared.authenticatedPageHTML(for: pageRequest)
        guard let token = AO3Client.parseCSRFToken(from: html) else {
            throw AO3WriteError.noCSRFToken
        }

        var params: [(String, String)] = [
            ("authenticity_token", token),
            ("comment[comment_content]", text),
        ]
        if let pseud = AO3Client.parseDefaultPseudID(from: html) {
            params.append(("comment[pseud_id]", pseud))
        }
        let request = try writeRequest(
            to: Self.commentsEndpoint(workID: workID),
            body: Self.formEncoded(params), csrf: token, referer: workURL, ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        // Success is a 2xx/3xx with no re-rendered error list (AO3 re-renders the form
        // with an error list when a comment is rejected).
        if (200...399).contains(status), AO3Client.writeErrorMessage(in: responseBody) == nil {
            return "Comment posted."
        }
        throw AO3WriteError.rejected(
            AO3Client.writeErrorMessage(in: responseBody) ?? "AO3 couldn't post the comment."
        )
    }

    // MARK: - Helpers

    private func csrfToken(forPageAt url: URL) async throws -> String {
        let request = try authenticatedRequest(for: url)
        let html = try await AO3Client.shared.authenticatedPageHTML(for: request)
        guard let token = AO3Client.parseCSRFToken(from: html) else {
            throw AO3WriteError.noCSRFToken
        }
        return token
    }

    /// Builds an authenticated `POST` carrying the CSRF token, form body, and (for
    /// AO3's UJS endpoints like kudos) the AJAX headers AO3 expects.
    private func writeRequest(
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

    /// `application/x-www-form-urlencoded` body. Ordered so callers control field
    /// order; keys/values are percent-encoded (RFC 3986 unreserved kept).
    static func formEncoded(_ params: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = params.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
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
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Log in to AO3 first."
        case .noCSRFToken: "Couldn't prepare the request. Try again, or open the work on AO3."
        case .emptyComment: "Write a comment first."
        case .rejected(let reason): reason
        }
    }
}
