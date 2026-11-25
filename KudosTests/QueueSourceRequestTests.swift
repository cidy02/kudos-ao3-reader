import Foundation
import Testing
@testable import Kudos

private final class QueueSourceProbe: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var retryAfter: String?
    private static var statusCode = 429
    private static var body = Data()

    static func reset(retryAfter: String?, statusCode: Int = 429, body: Data = Data()) {
        lock.lock()
        requests = []
        self.retryAfter = retryAfter
        self.statusCode = statusCode
        self.body = body
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
        let statusCode = Self.statusCode
        let body = Self.body
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
            headerFields: retryAfter.map { ["Retry-After": $0] } ?? [:]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
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

    @Test func allFourSourceKindsFetchPageOneAnonymouslyAndRejectPageTwoOrUntrustedHost() async throws {
        let holdKey = AO3Client.queueSourceHoldKey
        UserDefaults.standard.removeObject(forKey: holdKey)
        defer { UserDefaults.standard.removeObject(forKey: holdKey) }

        let html = """
        <html><body>
        <ol class="work index group">
          <li id="work_101" class="work blurb group">
            <div class="header module">
              <h4 class="heading"><a href="/works/101">New Fic</a> by <a rel="author" href="/users/alice/pseuds/alice">alice</a></h4>
              <p class="datetime">02 Jan 2025</p>
            </div>
          </li>
        </ol>
        </body></html>
        """
        QueueSourceProbe.reset(retryAfter: nil, statusCode: 200, body: Data(html.utf8))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QueueSourceProbe.self]
        let client = AO3Client(
            session: URLSession(configuration: configuration),
            paceSleep: { _ in }
        )

        let authorRoute = try #require(AO3AuthorRoute(username: "alice", pseud: "pen"))
        let seriesBase = try #require(URL(string: "https://archiveofourown.org/series/42"))
        let tagBase = try #require(AO3Client.tagWorksURL(tagName: "Slow Burn"))
        let pageOneURLs = [
            try #require(AO3Client.searchURL(filters: AO3SearchFilters(), page: 1)),
            authorRoute.contentURL(.works, page: 1),
            try #require(AO3Client.seriesPageURL(seriesBase, page: 1)),
            AO3Client.filteredWorksURL(tagBase, filters: QueueSourceChecks.tagBaselineFilters, page: 1)
        ]
        let forbiddenURLs = [
            authorRoute.contentURL(.works, page: 2),
            try #require(AO3Client.seriesPageURL(seriesBase, page: 2)),
            AO3Client.filteredWorksURL(tagBase, filters: QueueSourceChecks.tagBaselineFilters, page: 2),
            try #require(URL(string: "https://archiveofourown.org.evil.com/series/42"))
        ]

        for bad in forbiddenURLs {
            await #expect(throws: AO3Error.self) { _ = try await client.queueSourceFetch(bad) }
        }
        #expect(QueueSourceProbe.sent.isEmpty)

        for url in pageOneURLs {
            let fetched = try await client.queueSourceFetch(url)
            #expect(fetched.url == url)
            #expect(fetched.page.works.count == 1)
            #expect(fetched.page.works.first?.id == 101)
            #expect(fetched.html.contains("work_101"))
        }

        let sent = QueueSourceProbe.sent
        #expect(sent.count == 4)
        for request in sent {
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("feature=queue-source-counts") == true)
        }
    }

    private final class WaitLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [TimeInterval] = []
        func add(_ value: TimeInterval) { lock.lock(); values.append(value); lock.unlock() }
        var all: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return values }
    }

    private func makeClient(
        waits: WaitLog = WaitLog(), configure: (URLSessionConfiguration) -> Void = { _ in }
    ) -> AO3Client {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QueueSourceProbe.self]
        configure(configuration)
        return AO3Client(
            session: URLSession(configuration: configuration),
            paceSleep: { waits.add($0) }
        )
    }

    private static let listing = """
    <html><body><ol class="work index group">
      <li id="work_101" class="work blurb group"><div class="header module">
        <h4 class="heading"><a href="/works/101">New Fic</a> by <a rel="author" href="/users/alice/pseuds/alice">alice</a></h4>
        <p class="datetime">02 Jan 2025</p></div></li>
    </ol></body></html>
    """

    @Test func repeatedMixedCaseOrPortedPageQueriesNeverReachTheNetwork() async throws {
        UserDefaults.standard.removeObject(forKey: AO3Client.queueSourceHoldKey)
        QueueSourceProbe.reset(retryAfter: nil, statusCode: 200, body: Data(Self.listing.utf8))
        let client = makeClient()
        for raw in [
            "https://archiveofourown.org/series/1?page=1&page=2",
            "https://archiveofourown.org/series/1?PAGE=2",
            "https://archiveofourown.org/series/1?page",
            "https://archiveofourown.org:8443/series/1?page=1"
        ] {
            let url = try #require(URL(string: raw))
            await #expect(throws: AO3Error.self) { _ = try await client.queueSourceFetch(url) }
        }
        #expect(QueueSourceProbe.sent.isEmpty)
    }

    @Test func secondFetchWaitsOutTheThreeSecondQueueSourceSpacing() async throws {
        UserDefaults.standard.removeObject(forKey: AO3Client.queueSourceHoldKey)
        QueueSourceProbe.reset(retryAfter: nil, statusCode: 200, body: Data(Self.listing.utf8))
        let waits = WaitLog()
        let client = makeClient(waits: waits)
        let first = try #require(URL(string: "https://archiveofourown.org/series/1"))
        let second = try #require(URL(string: "https://archiveofourown.org/series/2"))
        _ = try await client.queueSourceFetch(first)
        #expect(waits.all.allSatisfy { $0 < 2.5 })
        _ = try await client.queueSourceFetch(second)
        #expect(QueueSourceProbe.sent.count == 2)
        // paceSleep records instead of sleeping, so the second start still owes ~3 s.
        #expect(waits.all.contains { $0 >= 2.5 && $0 <= 3.0 })
    }

    @Test func forbiddenAndMaintenanceStopWithoutARetry() async throws {
        UserDefaults.standard.removeObject(forKey: AO3Client.queueSourceHoldKey)
        let url = try #require(URL(string: "https://archiveofourown.org/series/1"))

        QueueSourceProbe.reset(retryAfter: nil, statusCode: 403)
        var client = makeClient()
        await #expect(throws: AO3Error.self) { _ = try await client.queueSourceFetch(url) }
        #expect(QueueSourceProbe.sent.count == 1)

        QueueSourceProbe.reset(retryAfter: nil, statusCode: 418)
        client = makeClient()
        do {
            _ = try await client.queueSourceFetch(url)
            Issue.record("Expected maintenance")
        } catch AO3Error.maintenance {
        }
        #expect(QueueSourceProbe.sent.count == 1)
        // The maintenance hold keeps the next source from being asked at all.
        await #expect(throws: AO3Error.self) { _ = try await client.queueSourceFetch(url) }
        #expect(QueueSourceProbe.sent.count == 1)
    }

    @Test func theSessionCookieIsNeverSentAndNeverLeftBehind() async throws {
        UserDefaults.standard.removeObject(forKey: AO3Client.queueSourceHoldKey)
        QueueSourceProbe.reset(retryAfter: nil, statusCode: 200, body: Data(Self.listing.utf8))
        let url = try #require(URL(string: "https://archiveofourown.org/series/1"))
        var storage: HTTPCookieStorage?
        let client = makeClient { configuration in
            storage = configuration.httpCookieStorage
            let cookie = HTTPCookie(properties: [
                .domain: "archiveofourown.org", .path: "/",
                .name: AO3RequestDefaults.sessionCookieName, .value: "secret"
            ])
            if let cookie { configuration.httpCookieStorage?.setCookie(cookie) }
        }
        _ = try await client.queueSourceFetch(url)
        let sent = try #require(QueueSourceProbe.sent.first)
        #expect(sent.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(sent.httpShouldHandleCookies == false)
        #expect(storage?.cookies(for: url)?.contains { $0.name == AO3RequestDefaults.sessionCookieName } != true)
    }
}
