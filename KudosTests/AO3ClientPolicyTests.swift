import Foundation
import Testing
@testable import Kudos

/// Closes the coverage gap noted in docs/REGRESSION_TEST_MATRIX.md: the retry and
/// pacing policies (docs/AO3_NETWORKING_POLICY.md) were enforced only by review.
struct AO3ClientPolicyTests {
    // MARK: - Retry policy

    @Test func rateLimitedHonorsRetryAfterWhenLargerThanBackoff() {
        let delay = AO3Client.retryDelay(for: AO3Error.rateLimited(retryAfter: 10), attempt: 1)
        #expect(delay == 10)
    }

    @Test func rateLimitedWithoutHintFallsBackToBackoff() {
        #expect(AO3Client.retryDelay(for: AO3Error.rateLimited(retryAfter: nil), attempt: 1) == 0.5)
        #expect(AO3Client.retryDelay(for: AO3Error.rateLimited(retryAfter: nil), attempt: 2) == 1.0)
    }

    @Test func serverErrorsBackOffExponentially() {
        #expect(AO3Client.retryDelay(for: AO3Error.server(status: 502), attempt: 1) == 0.5)
        #expect(AO3Client.retryDelay(for: AO3Error.server(status: 502), attempt: 2) == 1.0)
        #expect(AO3Client.retryDelay(for: AO3Error.server(status: 502), attempt: 3) == 2.0)
    }

    @Test func transientTransportFailuresRetry() {
        #expect(AO3Client.retryDelay(for: URLError(.timedOut), attempt: 1) != nil)
        #expect(AO3Client.retryDelay(for: URLError(.networkConnectionLost), attempt: 1) != nil)
    }

    @Test func nonTransientFailuresNeverRetry() {
        #expect(AO3Client.retryDelay(for: AO3Error.notFound, attempt: 1) == nil)
        #expect(AO3Client.retryDelay(for: AO3Error.forbidden, attempt: 1) == nil)
        #expect(AO3Client.retryDelay(for: AO3Error.parse, attempt: 1) == nil)
        #expect(AO3Client.retryDelay(for: AO3Error.http(status: 418), attempt: 1) == nil)
        #expect(AO3Client.retryDelay(for: AO3Error.authenticationRequired, attempt: 1) == nil)
        #expect(AO3Client.retryDelay(for: URLError(.cancelled), attempt: 1) == nil)
    }

    // MARK: - Pacing policy

    @Test func firstRequestPaysNoWaitButClaimsTheNextSlot() {
        let now = Date()
        let step = AO3Client.paceStep(now: now, nextAllowed: .distantPast, minInterval: 0.6)
        #expect(step.wait <= 0)
        #expect(step.nextAllowed == now.addingTimeInterval(0.6))
    }

    @Test func rapidCallersQueueBehindEachOtherAtMinIntervalSpacing() {
        let now = Date()
        let first = AO3Client.paceStep(now: now, nextAllowed: .distantPast, minInterval: 0.6)
        let second = AO3Client.paceStep(now: now, nextAllowed: first.nextAllowed, minInterval: 0.6)
        let third = AO3Client.paceStep(now: now, nextAllowed: second.nextAllowed, minInterval: 0.6)
        #expect(abs(second.wait - 0.6) < 0.0001)
        #expect(abs(third.wait - 1.2) < 0.0001)
    }

    @Test func idleGapsDoNotAccumulateCredit() {
        // A long-idle client's next slot is measured from *now*, not from the stale
        // nextAllowed — bursts after idle still space out.
        let now = Date()
        let stale = now.addingTimeInterval(-60)
        let step = AO3Client.paceStep(now: now, nextAllowed: stale, minInterval: 0.6)
        #expect(step.wait <= 0)
        #expect(step.nextAllowed == now.addingTimeInterval(0.6))
    }

    // MARK: - Cookie isolation policy (A5-F1 / T-100)

    /// T-100: the session's cookie jar must be its own **private, ephemeral**
    /// store — never `HTTPCookieStorage.shared` (the jar `AO3CookieBridge` used to
    /// mirror a signed-in session's cookie into, the A5-F1 leak) — so Cloudflare's
    /// own cookies can be kept warm without reopening that leak. `.ephemeral`
    /// configurations always carry their own dedicated cookie storage distinct
    /// from `.shared`, so accept/set being enabled here is safe precisely because
    /// nothing outside this one session can ever read or write into it.
    @Test func anonymousSessionConfigurationUsesAPrivateEphemeralCookieJarNeverTheSharedOne() {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        #expect(config.httpCookieStorage !== HTTPCookieStorage.shared)
        #expect(config.httpShouldSetCookies == true)
        #expect(config.httpCookieAcceptPolicy == .always)
    }

    /// The AO3 auth/session cookie must never appear in the Cloudflare-cookie
    /// header authenticated/write requests append to their own explicit Cookie
    /// header — even if it somehow ended up in the jar, it must be filtered here
    /// too (defense in depth alongside `purgeSessionCookie`).
    @Test func challengeCookieHeaderNeverIncludesTheAO3AuthCookie() {
        let cloudflare = HTTPCookie(properties: [
            .name: "cf_clearance", .value: "abc123",
            .domain: ".archiveofourown.org", .path: "/"
        ])!
        let botManagement = HTTPCookie(properties: [
            .name: "__cf_bm", .value: "def456",
            .domain: ".archiveofourown.org", .path: "/"
        ])!
        let authCookie = HTTPCookie(properties: [
            .name: AO3RequestDefaults.sessionCookieName, .value: "should-never-appear-here",
            .domain: ".archiveofourown.org", .path: "/"
        ])!

        let header = AO3Client.challengeCookieHeader(from: [cloudflare, botManagement, authCookie])
        #expect(header != nil)
        #expect(header?.contains("cf_clearance=abc123") == true)
        #expect(header?.contains("__cf_bm=def456") == true)
        #expect(header?.contains(AO3RequestDefaults.sessionCookieName) == false)
    }

    @Test func challengeCookieHeaderIsNilWhenOnlyTheAuthCookieIsPresent() {
        let authCookie = HTTPCookie(properties: [
            .name: AO3RequestDefaults.sessionCookieName, .value: "secret",
            .domain: ".archiveofourown.org", .path: "/"
        ])!
        #expect(AO3Client.challengeCookieHeader(from: [authCookie]) == nil)
        #expect(AO3Client.challengeCookieHeader(from: []) == nil)
    }

    /// The purge is a structural invariant, not a best-effort cleanup: after it
    /// runs, the auth cookie cannot be read back from the jar for that URL, while
    /// an unrelated cookie in the same jar survives untouched.
    @Test func purgeSessionCookieRemovesOnlyTheAO3AuthCookie() {
        let storage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: "AO3ClientPolicyTests-\(UUID().uuidString)"
        )
        let url = URL(string: "https://archiveofourown.org/")!
        let authCookie = HTTPCookie(properties: [
            .name: AO3RequestDefaults.sessionCookieName, .value: "leaked-guest-session",
            .domain: ".archiveofourown.org", .path: "/"
        ])!
        let cloudflareCookie = HTTPCookie(properties: [
            .name: "cf_clearance", .value: "abc123",
            .domain: ".archiveofourown.org", .path: "/"
        ])!
        storage.setCookie(authCookie)
        storage.setCookie(cloudflareCookie)
        #expect(storage.cookies(for: url)?.contains { $0.name == AO3RequestDefaults.sessionCookieName } == true)

        AO3Client.purgeSessionCookie(from: storage, url: url)

        let remaining = storage.cookies(for: url) ?? []
        #expect(!remaining.contains { $0.name == AO3RequestDefaults.sessionCookieName })
        #expect(remaining.contains { $0.name == "cf_clearance" })
    }

    @Test func purgeSessionCookieToleratesANilStorage() {
        // Must not crash/throw when the configuration's cookie storage is nil.
        AO3Client.purgeSessionCookie(from: nil, url: URL(string: "https://archiveofourown.org/")!)
    }

    /// The authenticated coalescer's key must differ per account (and between an
    /// anonymous and an authenticated request to the same URL), so a mid-flight
    /// account switch or logout/login can never hand one session's in-flight
    /// response to another.
    @Test func authCoalescingKeyDiffersAcrossAccountsAndAnonymousScope() {
        let url = URL(string: "https://archiveofourown.org/works/1")!
        let anonymous = AO3Client.authCoalescingKey(url: url, cookieHeader: nil)
        let accountA = AO3Client.authCoalescingKey(url: url, cookieHeader: "_otwarchive_session=aaa")
        let accountB = AO3Client.authCoalescingKey(url: url, cookieHeader: "_otwarchive_session=bbb")
        #expect(anonymous != accountA)
        #expect(anonymous != accountB)
        #expect(accountA != accountB)
    }

    @Test func authCoalescingKeyDiffersAcrossURLsForTheSameAccount() {
        let cookieHeader = "_otwarchive_session=aaa"
        let workURL = URL(string: "https://archiveofourown.org/works/1")!
        let bookmarksURL = URL(string: "https://archiveofourown.org/users/reader/bookmarks")!
        #expect(
            AO3Client.authCoalescingKey(url: workURL, cookieHeader: cookieHeader)
                != AO3Client.authCoalescingKey(url: bookmarksURL, cookieHeader: cookieHeader)
        )
    }
}
