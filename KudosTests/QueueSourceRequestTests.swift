import Foundation
import Testing
@testable import Kudos

private final class QueueSourceProbe: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var retryAfter: String?

    static func reset(retryAfter: String?) {
        lock.lock()
        requests = []
        self.retryAfter = retryAfter
        lock.unlock()
    }

    static var sent: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let retryAfter = Self.retryAfter
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 429, httpVersion: "HTTP/1.1",
            headerFields: retryAfter.map { ["Retry-After": $0] } ?? [:]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct QueueSourceRequestTests {
    @Test func firstPageCarriesItsOwnFeatureAnd429HoldSurvivesAnotherOpen() async throws {
        let holdKey = AO3Client.queueSourceHoldKey
        for retryAfter in [Optional("120"), nil] {
            UserDefaults.standard.removeObject(forKey: holdKey)
            defer { UserDefaults.standard.removeObject(forKey: holdKey) }
            QueueSourceProbe.reset(retryAfter: retryAfter)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [QueueSourceProbe.self]
            let client = AO3Client(
                session: URLSession(configuration: configuration),
                paceSleep: { _ in }
            )
            let url = try #require(AO3Client.searchURL(filters: AO3SearchFilters(), page: 1))
            let pageTwo = try #require(AO3Client.searchURL(filters: AO3SearchFilters(), page: 2))
            await #expect(throws: AO3Error.self) { try await client.queueSourcePage(pageTwo) }
            #expect(QueueSourceProbe.sent.isEmpty)
            do {
                _ = try await client.queueSourcePage(url)
                Issue.record("Expected 429")
            } catch AO3Error.rateLimited {
            }
            let sent = QueueSourceProbe.sent
            #expect(sent.count == 1)
            #expect(sent.first?.url?.query?.contains("page=1") == true)
            #expect(sent.first?.value(forHTTPHeaderField: "User-Agent")?.contains("feature=queue-source-counts") == true)
            #expect((UserDefaults.standard.object(forKey: holdKey) as? Date ?? .distantPast) > Date())
            do {
                _ = try await client.queueSourcePage(url)
                Issue.record("Expected the persisted 429 hold")
            } catch AO3Error.rateLimited {
            }
            #expect(QueueSourceProbe.sent.count == 1)
        }
    }

    @Test func holdIsCheckedBeforePacing() async throws {
        let holdKey = AO3Client.queueSourceHoldKey
        UserDefaults.standard.removeObject(forKey: holdKey)
        defer { UserDefaults.standard.removeObject(forKey: holdKey) }
        UserDefaults.standard.set(Date().addingTimeInterval(60), forKey: holdKey)
        QueueSourceProbe.reset(retryAfter: nil)
        var paced = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QueueSourceProbe.self]
        // A pending pace interval, so a hold checked after pace() would have slept first.
        let client = AO3Client(
            session: URLSession(configuration: configuration),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { _ in paced += 1 }
        )
        let url = try #require(AO3Client.searchURL(filters: AO3SearchFilters(), page: 1))
        do {
            _ = try await client.queueSourcePage(url)
            Issue.record("Expected the persisted 429 hold")
        } catch AO3Error.rateLimited {
        }
        #expect(paced == 0)
        #expect(QueueSourceProbe.sent.isEmpty)
    }
}
