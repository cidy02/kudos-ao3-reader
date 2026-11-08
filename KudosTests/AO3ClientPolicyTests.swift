import Foundation
import Testing
@testable import Kudos

private final class AO3ClientPolicyBundleAnchor {}

/// Stands in for AO3 and counts how many times a scan read is actually sent.
private final class ScanRateLimitProbe: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var hitCount = 0

    static var hits: Int {
        lock.lock()
        defer { lock.unlock() }
        return hitCount
    }

    static func reset() {
        lock.lock()
        hitCount = 0
        lock.unlock()
    }

    // URLProtocol declares these as `class` methods; `static` cannot override them.
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.hitCount += 1
        Self.lock.unlock()
        let url = request.url ?? URL(string: "https://archiveofourown.org/")!
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": "0"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Closes the coverage gap noted in docs/REGRESSION_TEST_MATRIX.md: the retry and
/// pacing policies (docs/AO3_NETWORKING_POLICY.md) were enforced only by review.
struct AO3ClientPolicyTests {
    private func maintenanceFixture() throws -> Data {
        let url = try #require(
            Bundle(for: AO3ClientPolicyBundleAnchor.self)
                .url(forResource: "ao3_maintenance", withExtension: "html")
        )
        return try Data(contentsOf: url)
    }

    private func expectMaintenance(
        statusCode: Int,
        body: Data = Data()
    ) {
        do {
            try AO3Client.checkHTTPResponse(statusCode: statusCode, body: body)
            Issue.record("Expected AO3Error.maintenance")
        } catch AO3Error.maintenance {
            #expect(
                AO3Error.maintenance.errorDescription
                    == "AO3 is down for maintenance. Check status.archiveofourown.org."
            )
        } catch {
            Issue.record("Expected maintenance, got \(error)")
        }
    }

    // MARK: - Maintenance mapping

    @Test func status418MapsToMaintenance() {
        expectMaintenance(statusCode: 418)
    }

    @Test func maintenancePageMapsOnSuccessfulStatus() throws {
        expectMaintenance(statusCode: 200, body: try maintenanceFixture())
    }

    @Test func ordinaryMaintenanceMentionIsNotMatched() throws {
        let ordinary = Data("<html><title>A normal work</title><p>Maintenance tag.</p></html>".utf8)
        try AO3Client.checkHTTPResponse(statusCode: 200, body: ordinary)
    }

    // MARK: - Retry policy

    @Test func scanReadsSurface429WithoutTheClientRetry() async throws {
        ScanRateLimitProbe.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScanRateLimitProbe.self]
        let client = AO3Client(session: URLSession(configuration: config))
        var request = URLRequest(url: URL(string: "https://archiveofourown.org/users/ada/subscriptions?type=works")!)
        request.setValue("test=1", forHTTPHeaderField: "Cookie")

        do {
            _ = try await client.subscriptionsPage(for: request, page: 1, retryTransientFailures: false)
            Issue.record("subscriptions page should surface 429")
        } catch let AO3Error.rateLimited(retryAfter) {
            #expect(retryAfter == 0)
        } catch {
            Issue.record("unexpected subscriptions error \(error)")
        }
        #expect(ScanRateLimitProbe.hits == 1)

        ScanRateLimitProbe.reset()
        var work = URLRequest(url: URL(string: "https://archiveofourown.org/works/1?view_adult=true")!)
        work.setValue("test=1", forHTTPHeaderField: "Cookie")
        do {
            _ = try await client.workMetadata(workID: 1, request: work, retryTransientFailures: false)
            Issue.record("work page should surface 429")
        } catch let AO3Error.rateLimited(retryAfter) {
            #expect(retryAfter == 0)
        } catch {
            Issue.record("unexpected work error \(error)")
        }
        #expect(ScanRateLimitProbe.hits == 1)
    }

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
        #expect(AO3Client.retryDelay(for: AO3Error.maintenance, attempt: 1) == nil)
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
}
