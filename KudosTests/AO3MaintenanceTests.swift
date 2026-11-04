import Foundation
import Synchronization
import Testing
@testable import Kudos

/// AO3's "down for maintenance" page, captured live on 2026-11-03 (Cloudflare served it
/// as HTTP 418 for every URL). The app must name it, never retry it, and stop sending
/// requests for a short hold so a library refresh doesn't keep knocking.
@Suite(.serialized)
struct AO3MaintenanceTests {
    private final class BundleAnchor {}

    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try Data(contentsOf: url)
    }

    @Test func theCapturedMaintenancePageIsRecognised() throws {
        #expect(AO3Client.isMaintenancePage(try Self.fixture("ao3_maintenance")))
    }

    @Test func ordinaryAO3PagesAreNot() throws {
        #expect(!AO3Client.isMaintenancePage(try Self.fixture("ao3_author_profile")))
        #expect(!AO3Client.isMaintenancePage(Data("<h2>Request temporarily denied.</h2>".utf8)))
    }

    /// A rejected comment or form comes back with the reader's own words in it, escaped.
    @Test func echoedReaderTextIsNotTheMaintenancePage() {
        let echoed = [
            "<textarea>I wrote this while the archive is down for maintenance.</textarea>",
            "<p>&lt;h2&gt;The archive is down for maintenance.&lt;/h2&gt;</p>"
        ]
        for body in echoed {
            #expect(!AO3Client.isMaintenancePage(Data(body.utf8)))
        }
    }

    @Test func maintenanceIsNotRetriedButKeptCopiesMayShow() {
        #expect(AO3Client.retryDelay(for: AO3Error.maintenance, attempt: 1) == nil)
        #expect(AO3Error.maintenance.allowsStalePage)
        #expect(UserFacingError.message(for: AO3Error.maintenance).contains("down for maintenance"))
        #expect(UserFacingError.systemImage(for: AO3Error.maintenance) == "wrench.and.screwdriver")
    }

    @Test func oneMaintenanceAnswerHoldsTheNextRequestsOffTheNetwork() async throws {
        MaintenanceStubProtocol.body = try Self.fixture("ao3_maintenance")
        MaintenanceStubProtocol.loads.withLock { $0 = 0 }
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [MaintenanceStubProtocol.self]
        let client = AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })

        for path in ["works/1", "works/2", "media"] {
            await #expect(throws: AO3Error.maintenance) {
                _ = try await client.getHTML(URL(string: "https://archiveofourown.org/\(path)")!)
            }
        }
        // The first request met the page; the hold answered the other two locally.
        #expect(MaintenanceStubProtocol.loads.withLock { $0 } == 1)
    }

    @Test func pullToRefreshAsksAO3AgainDuringTheHold() async throws {
        MaintenanceStubProtocol.body = try Self.fixture("ao3_maintenance")
        MaintenanceStubProtocol.loads.withLock { $0 = 0 }
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [MaintenanceStubProtocol.self]
        let client = AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })

        _ = try? await client.getHTML(URL(string: "https://archiveofourown.org/works/3")!)
        await client.invalidateCachedResponses()
        _ = try? await client.getHTML(URL(string: "https://archiveofourown.org/works/4")!)
        #expect(MaintenanceStubProtocol.loads.withLock { $0 } == 2)
    }
}

/// Answers every load with AO3's maintenance page as a 418 and counts the loads.
private final class MaintenanceStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    static let loads = Mutex(0)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.loads.withLock { $0 += 1 }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 418, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
