import Foundation
import Testing
@testable import Kudos

/// Local stand-in for `URLSession`. `protocolClasses` handles the load, so a
/// regression that still dispatches does not POST to AO3.
private final class AO3WriteDispatchProbe: URLProtocol, @unchecked Sendable {
    struct Hit: Sendable {
        var cookie: String?
        var preparedWriteSession: String?
        var handlesCookies: Bool
    }

    private static let lock = NSLock()
    private static var hits: [Hit] = []

    static func reset() {
        lock.lock()
        hits = []
        lock.unlock()
    }

    static func recorded() -> [Hit] {
        lock.lock()
        defer { lock.unlock() }
        return hits
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let hit = Hit(
            cookie: request.value(forHTTPHeaderField: "Cookie"),
            preparedWriteSession: request.value(
                forHTTPHeaderField: AO3Client.preparedWriteSessionHeader
            ),
            handlesCookies: request.httpShouldHandleCookies
        )
        Self.lock.lock()
        Self.hits.append(hit)
        Self.lock.unlock()

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("fence-ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `submitWrite` used to await `pace()` and then POST the Cookie it was handed.
/// A generation change inside that wait still sent the old account's write.
@Suite(.serialized)
@MainActor
struct AO3WriteDispatchFenceTests {
    private func makeAuth() -> AO3AuthService {
        AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
    }

    private func probeSession() -> URLSession {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [AO3WriteDispatchProbe.self]
        return URLSession(configuration: config)
    }

    private func preparedWrite(on auth: AO3AuthService) throws -> URLRequest {
        try auth.writeRequest(
            to: AO3AuthService.kudosEndpoint,
            body: Data("kudo=1".utf8),
            csrf: "csrf-token",
            referer: AO3AuthService.workURL(1),
            ajax: true
        )
    }

    /// A held generation still sends exactly once, with the explicit Cookie and
    /// without the stamp header that must never leave the process.
    @Test func anUnchangedGenerationStillDispatchesOnce() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let request = try preparedWrite(on: auth)
        let stamp = auth.writeSessionStamp
        #expect(
            request.value(forHTTPHeaderField: AO3Client.preparedWriteSessionHeader) == stamp
        )

        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { _ in }
        )
        let (status, body) = try await auth.submitWrite(request, using: client)

        #expect(status == 201)
        #expect(body == "fence-ok")
        let hits = AO3WriteDispatchProbe.recorded()
        #expect(hits.count == 1)
        #expect(hits.first?.handlesCookies == false)
        #expect(hits.first?.preparedWriteSession == nil)
        #expect(hits.first?.cookie?.contains("_otwarchive_session=session-alice") == true)
        #expect(auth.writeSessionStamp == stamp)
    }

    /// The generation that built the Cookie changes while `pace()` is suspended.
    /// Parent behavior dispatched after the sleep. This must not.
    @Test func aGenerationChangeDuringThePacingWaitDoesNotDispatch() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let request = try preparedWrite(on: auth)
        let prepared = auth.sessionGeneration
        let entered = Signal()
        let release = Signal()
        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { _ in
                await entered.fire()
                await release.wait()
            }
        )

        let task = Task {
            try await auth.submitWrite(request, using: client)
        }
        await entered.wait()
        #expect(auth.sessionGeneration == prepared)
        await auth.logout()
        #expect(auth.sessionGeneration != prepared)
        await release.fire()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }

    /// A change after `writeRequest` and before `submitWrite` is the same queued
    /// write. The service that prepared it must no longer authorize it.
    @Test func aGenerationChangeAfterTheRequestWasBuiltDoesNotDispatch() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let request = try preparedWrite(on: auth)
        let prepared = auth.sessionGeneration
        await auth.logout()
        #expect(auth.sessionGeneration != prepared)

        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { _ in }
        )

        await #expect(throws: CancellationError.self) {
            try await auth.submitWrite(request, using: client)
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }

    /// A second service can have the same integer generation. It still must not
    /// authorize a request carrying the first service's Cookie.
    @Test func anotherAuthServiceAtTheSameGenerationDoesNotDispatch() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let request = try preparedWrite(on: auth)
        let otherAuth = makeAuth()
        await otherAuth.login(username: "bob", password: "pw")
        #expect(otherAuth.sessionGeneration == auth.sessionGeneration)

        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { _ in }
        )

        await #expect(throws: CancellationError.self) {
            try await otherAuth.submitWrite(request, using: client)
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }

    /// Every production caller uses `writeRequest`. A caller that bypasses it
    /// must fail closed rather than silently submitting an unfenced write.
    @Test func anUnstampedWriteDoesNotDispatch() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        let client = AO3Client(session: probeSession())
        let request = URLRequest(url: AO3AuthService.kudosEndpoint)

        await #expect(throws: CancellationError.self) {
            try await auth.submitWrite(request, using: client)
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }
}
