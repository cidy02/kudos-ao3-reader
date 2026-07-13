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

    // MARK: - Cookie isolation policy (A5-F1)

    /// The anonymous session must be structurally unable to read or write cookies —
    /// not merely start with an empty jar. `httpCookieStorage == nil` is what stops
    /// a signed-in session's cookie (mirrored into `HTTPCookieStorage.shared` by
    /// `AO3CookieBridge` for WebKit's benefit) from silently riding along on a
    /// nominally anonymous search/browse/tag request.
    @Test func anonymousSessionConfigurationDisablesCookieHandling() {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        #expect(config.httpCookieStorage == nil)
        #expect(config.httpShouldSetCookies == false)
        #expect(config.httpCookieAcceptPolicy == .never)
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
