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
///
/// The live account cookie must never follow a redirect off AO3 — an open
/// redirect, a misconfigured route, or an intermediary domain (a Cloudflare
/// challenge subdomain, say) that happens to echo a cookie of the same name
/// could otherwise carry it to another host (this would reopen A5-F1 through
/// an explicit per-request header, entirely outside the cookie-storage
/// protections `AO3Client`'s session relies on elsewhere). `redirectCookieAction`
/// checks the redirect's actual destination (`AO3RequestDefaults.isTrustedURL`)
/// before ever touching the header, and strips it outright when the target
/// isn't AO3 — never merely "leaves it as Foundation built it."
final class AO3RedirectCookieRelay: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var request = newRequest
        switch Self.redirectCookieAction(
            currentHeader: task.currentRequest?.value(forHTTPHeaderField: "Cookie"),
            responseHeaderFields: response.allHeaderFields,
            responseURL: response.url,
            newRequestURL: newRequest.url
        ) {
        case .leaveUnchanged:
            break
        case let .set(value):
            request.setValue(value, forHTTPHeaderField: "Cookie")
        case .strip:
            request.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        completionHandler(request)
    }

    /// What this redirect should do with the Cookie header — a three-way
    /// decision, not a nilable string, because "make no change" and "strip
    /// whatever is there" are different outcomes that must never be conflated.
    enum RedirectCookieAction: Equatable {
        case leaveUnchanged
        case set(String)
        case strip
    }

    /// Pure (unit-tested): decides what a redirected request's Cookie header
    /// should carry. `.strip` when `newRequestURL` is not an AO3 host — the
    /// live auth cookie (and everything else `currentHeader` carries) must
    /// never follow a redirect off AO3, whether from an open-redirect param, a
    /// misconfigured route, or an intermediary domain (e.g. a Cloudflare
    /// challenge subdomain) that happens to echo a cookie of the same name.
    /// Otherwise defers to `mergedCookieHeader`'s same-host refresh logic,
    /// making no change when it finds nothing to update.
    static func redirectCookieAction(
        currentHeader: String?,
        responseHeaderFields: [AnyHashable: Any],
        responseURL: URL?,
        newRequestURL: URL?
    ) -> RedirectCookieAction {
        guard AO3RequestDefaults.isTrustedURL(newRequestURL) else { return .strip }
        guard let updated = mergedCookieHeader(
            currentHeader: currentHeader, responseHeaderFields: responseHeaderFields, url: responseURL
        ) else { return .leaveUnchanged }
        return .set(updated)
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
