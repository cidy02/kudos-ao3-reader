import Foundation
import Testing
@testable import Kudos

/// `AO3RedirectCookieRelay.mergedCookieHeader` (T-100): keeps a same-host
/// redirect's Cookie header current when the AO3 auth cookie was re-signed by
/// the response (otwarchive's `_otwarchive_session` carries the write's success/
/// error flash across the redirect via Rails' `CookieStore`), without disturbing
/// any other cookie pair on the request.
struct AO3RedirectCookieRelayTests {
    private let url = URL(string: "https://archiveofourown.org/works/1/comments")!

    private func setCookieHeaders(_ pairs: [String]) -> [String: String] {
        // Real HTTP responses may repeat Set-Cookie; HTTPURLResponse folds them
        // into one comma-joined value under the "Set-Cookie" key on Apple
        // platforms' header dictionaries, which HTTPCookie.cookies(...) parses.
        ["Set-Cookie": pairs.joined(separator: ", ")]
    }

    @Test func replacesOnlyTheSessionCookiesValueLeavingOthersUntouched() {
        let current = "_otwarchive_session=stale-value; other_cookie=unchanged"
        let responseHeaders = setCookieHeaders(["_otwarchive_session=fresh-value-with-flash; path=/"])

        let merged = AO3RedirectCookieRelay.mergedCookieHeader(
            currentHeader: current, responseHeaderFields: responseHeaders, url: url
        )

        #expect(merged != nil)
        #expect(merged?.contains("_otwarchive_session=fresh-value-with-flash") == true)
        #expect(merged?.contains("stale-value") == false)
        #expect(merged?.contains("other_cookie=unchanged") == true)
    }

    @Test func appendsTheSessionCookieWhenTheCurrentHeaderDidNotHaveOne() {
        let current = "other_cookie=unchanged"
        let responseHeaders = setCookieHeaders(["_otwarchive_session=fresh; path=/"])

        let merged = AO3RedirectCookieRelay.mergedCookieHeader(
            currentHeader: current, responseHeaderFields: responseHeaders, url: url
        )

        #expect(merged == "other_cookie=unchanged; _otwarchive_session=fresh")
    }

    @Test func returnsNilWhenTheResponseSetsNoSessionCookie() {
        let current = "_otwarchive_session=stale-value"
        let responseHeaders = setCookieHeaders(["unrelated_cookie=123; path=/"])

        #expect(AO3RedirectCookieRelay.mergedCookieHeader(
            currentHeader: current, responseHeaderFields: responseHeaders, url: url
        ) == nil)
    }

    @Test func returnsNilWhenThereIsNoExistingHeaderToUpdate() {
        // Nothing to splice into — the caller leaves the redirect request as
        // Foundation built it rather than inventing a Cookie header from scratch.
        let responseHeaders = setCookieHeaders(["_otwarchive_session=fresh; path=/"])
        #expect(AO3RedirectCookieRelay.mergedCookieHeader(
            currentHeader: nil, responseHeaderFields: responseHeaders, url: url
        ) == nil)
        #expect(AO3RedirectCookieRelay.mergedCookieHeader(
            currentHeader: "", responseHeaderFields: responseHeaders, url: url
        ) == nil)
    }

    @Test func returnsNilWhenThereIsNoURLToResolveCookiesAgainst() {
        let responseHeaders = setCookieHeaders(["_otwarchive_session=fresh; path=/"])
        #expect(AO3RedirectCookieRelay.mergedCookieHeader(
            currentHeader: "_otwarchive_session=stale", responseHeaderFields: responseHeaders, url: nil
        ) == nil)
    }

    @Test func handlesMultipleUnrelatedExistingCookiePairs() {
        let current = "cf_clearance=cf1; _otwarchive_session=stale; __cf_bm=cf2"
        let responseHeaders = setCookieHeaders(["_otwarchive_session=fresh-flash-bearing; path=/"])

        let merged = AO3RedirectCookieRelay.mergedCookieHeader(
            currentHeader: current, responseHeaderFields: responseHeaders, url: url
        )

        #expect(merged?.contains("cf_clearance=cf1") == true)
        #expect(merged?.contains("__cf_bm=cf2") == true)
        #expect(merged?.contains("_otwarchive_session=fresh-flash-bearing") == true)
        #expect(merged?.contains("stale") == false)
    }

    // MARK: - redirectCookieAction (cross-host leak guard)

    /// The live account session cookie must never follow a redirect off AO3 —
    /// whether from an open-redirect parameter, a misconfigured route, or an
    /// intermediary domain (a Cloudflare challenge subdomain, say) that happens
    /// to echo a cookie of the same name. `.strip` must win regardless of
    /// what the response otherwise set.
    @Test func stripsTheCookieHeaderWhenTheRedirectLeavesAO3() {
        let responseHeaders = setCookieHeaders(["_otwarchive_session=fresh-with-flash; path=/"])
        let action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader: "_otwarchive_session=live-session-value",
            responseHeaderFields: responseHeaders,
            responseURL: url,
            newRequestURL: URL(string: "https://attacker.example.com/")!
        )
        #expect(action == .strip)
    }

    @Test func stripsWhenTheRedirectTargetIsNotHTTPS() {
        let action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader: "_otwarchive_session=live-session-value",
            responseHeaderFields: [:],
            responseURL: url,
            newRequestURL: URL(string: "http://archiveofourown.org/")!
        )
        #expect(action == .strip)
    }

    @Test func stripsWhenThereIsNoRedirectTargetURLAtAll() {
        let action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader: "_otwarchive_session=live-session-value",
            responseHeaderFields: [:],
            responseURL: url,
            newRequestURL: nil
        )
        #expect(action == .strip)
    }

    @Test func setsTheRefreshedCookieWhenTheRedirectStaysOnAO3() {
        let responseHeaders = setCookieHeaders(["_otwarchive_session=fresh-with-flash; path=/"])
        let action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader: "_otwarchive_session=stale; other_cookie=unchanged",
            responseHeaderFields: responseHeaders,
            responseURL: url,
            newRequestURL: URL(string: "https://archiveofourown.org/works/1")!
        )
        #expect(action == .set("_otwarchive_session=fresh-with-flash; other_cookie=unchanged"))
    }

    @Test func setsTheRefreshedCookieWhenTheRedirectStaysOnAnAO3Subdomain() {
        let responseHeaders = setCookieHeaders(["_otwarchive_session=fresh; path=/"])
        let action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader: "_otwarchive_session=stale",
            responseHeaderFields: responseHeaders,
            responseURL: url,
            newRequestURL: URL(string: "https://download.archiveofourown.org/works/1")!
        )
        #expect(action == .set("_otwarchive_session=fresh"))
    }

    @Test func leavesTheHeaderUnchangedWhenAO3RedirectSetsNoSessionCookie() {
        // A same-host redirect that just isn't a write's flash-bearing kind
        // (e.g. a plain page move) must not be touched at all — not stripped,
        // not rewritten.
        let action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader: "_otwarchive_session=stale; other_cookie=unchanged",
            responseHeaderFields: [:],
            responseURL: url,
            newRequestURL: URL(string: "https://archiveofourown.org/works/1")!
        )
        #expect(action == .leaveUnchanged)
    }
}
