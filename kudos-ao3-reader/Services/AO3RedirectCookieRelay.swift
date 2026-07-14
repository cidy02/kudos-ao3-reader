import Foundation

/// Keeps a same-host AO3 redirect's `Cookie` header current for requests whose
/// cookies are set explicitly rather than via ambient session storage
/// (`authenticatedHTML`/`submitWrite` both set `httpShouldHandleCookies = false`
/// — see `AO3Client`'s session-configuration doc for why: the auth cookie must
/// never live in shared session state, only in the per-request header built from
/// `AO3AuthService`'s own persisted `AO3Session`).
///
/// Without this, a same-host 302 (otwarchive redirects every successful write to
/// a rendering page) is auto-followed carrying the *stale, pre-request* Cookie
/// header — because disabling ambient cookie handling also disables capturing a
/// redirect response's own `Set-Cookie`, and Foundation otherwise just forwards
/// the original request's headers unchanged across a same-host redirect. otwarchive
/// uses Rails' signed `CookieStore` for `_otwarchive_session`
/// (`config/initializers/session_store.rb`), so the write's success/error flash is
/// serialized *into* that cookie's value and delivered via the redirect's own
/// `Set-Cookie` — a stale cookie on the followed GET means the flash was never
/// there to read, and a fully successful write reads back as `.unconfirmed`.
///
/// Stateless and shared across every task (each redirect callback only reads/
/// writes the one task's own request/response pair, no shared mutable state), so
/// it is safe under arbitrary request concurrency, including two different
/// accounts' requests racing on the actor.
final class AO3RedirectCookieRelay: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var request = newRequest
        if let updated = Self.mergedCookieHeader(
            currentHeader: task.currentRequest?.value(forHTTPHeaderField: "Cookie"),
            responseHeaderFields: response.allHeaderFields,
            url: response.url
        ) {
            request.setValue(updated, forHTTPHeaderField: "Cookie")
        }
        completionHandler(request)
    }

    /// Pure (unit-tested): replaces only the AO3 session cookie's value in
    /// `currentHeader` with whatever `responseHeaderFields`' `Set-Cookie` carries
    /// for it, leaving every other cookie pair in `currentHeader` untouched. nil
    /// when there is nothing to update (no existing header to update against, or
    /// the response set no session cookie) — the caller then leaves the redirect
    /// request exactly as Foundation built it.
    static func mergedCookieHeader(
        currentHeader: String?,
        responseHeaderFields: [AnyHashable: Any],
        url: URL?
    ) -> String? {
        guard let currentHeader, !currentHeader.isEmpty, let url,
              let stringHeaders = responseHeaderFields as? [String: String]
        else { return nil }
        let setCookies = HTTPCookie.cookies(withResponseHeaderFields: stringHeaders, for: url)
        guard let updated = setCookies.first(where: { $0.name == AO3RequestDefaults.sessionCookieName })
        else { return nil }

        var pairs: [(name: String, value: String)] = currentHeader
            .components(separatedBy: "; ")
            .compactMap { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }
        if let index = pairs.firstIndex(where: { $0.name == updated.name }) {
            pairs[index] = (updated.name, updated.value)
        } else {
            pairs.append((updated.name, updated.value))
        }
        return pairs.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
