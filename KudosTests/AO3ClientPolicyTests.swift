import Foundation
import Testing
@testable import Kudos

private final class AO3ClientPolicyBundleAnchor {}

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
